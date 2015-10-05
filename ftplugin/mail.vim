" This function breaks a string into an array of strings with specified maximum
" width, breaking after the specified pattern, and prepending lines beyond the
" first with the given prefix. Blanks are stripped from the beginning of
" subsequent lines, though support may be added for specifying a different
" pattern for this in the future.
function! s:BreakLine(linein, maxwidth, breakafter, prefix)
    " ignore \n when calculating string length since this is used as the marker
    " char for insert formatting..
    if strlen(substitute(substitute(a:linein, "\n", '', 'g'), '.', 'x', 'g'))
      \ <= a:maxwidth 
        return [a:linein]
    endif
    let startpos = 0
    let breakpos = 0
    while 0 <= startpos && startpos < a:maxwidth
        let breakpos = startpos
        let startpos = match(a:linein, a:breakafter, startpos + 1)
    endwhile
    if breakpos > -1
        let linesout = [a:linein[: breakpos]]
        let startpos = match(a:linein, '\m\S', breakpos + 1)
        if startpos < 0
            return linesout
        endif
        return linesout + s:BreakLine(a:prefix . a:linein[startpos :], 
                                    \ a:maxwidth, a:breakafter, a:prefix)
    endif
    return [a:linein]
endfunction

function! s:BreakHeaderField(linein, maxwidth, fieldname)
    let breakafter = '\m\s'
    if a:fieldname =~# '\v^From|To|Cc|Bcc|Reply-To$'
        let breakafter = '\m,'
    endif
    return s:BreakLine(a:linein, a:maxwidth, breakafter, ' ')
endfunction

function! s:BreakBodyText(linein, maxwidth, prefix)
    return s:BreakLine(a:prefix . a:linein, a:maxwidth, '\m\s', a:prefix)
endfunction

function! s:ExtractFieldName(field)
    let field = substitute(a:field, "\n", '', 'g') " ignore insert markers
    return matchstr(field, '\m^[!-9;-~]\+\ze:') " specified by rfc
endfunction

function! s:FindFieldName(lnum)
    let fieldname = ''
    let i = 1
    while i <= a:lnum
        let currline = getline(i)
        let currfieldname = s:ExtractFieldName(currline)
        if ! empty(currfieldname)
            let fieldname = currfieldname
        " if it's not a field line and doesn't start with one blank, we're out
        " of the header
        elseif currline !~ '\m^\s.*$' 
            return ''
        endif
        let i += 1
    endwhile
    return fieldname
endfunction

function! s:SeparatePrefix(linein)
    let pos = match(a:linein, '\m^[>[:blank:]\n]*\zs[^>[:blank:]\n]') 
    if pos < 0
        let prefixin = a:linein
        let lineout = ''
    elseif pos == 0
        let prefixin = ''
        let lineout = a:linein
    else
        let prefixin = a:linein[: pos - 1]
        let lineout = a:linein[pos :]
    endif
    let pos = match(prefixin, '\m>\|$')
    let prefixout = repeat(' ', (pos / 4) * 4)
    while pos < strlen(prefixin)
        let pos += 1
        let newpos = match(prefixin, '\m>\|$', pos)
        let bcount = ((newpos - pos) / 4) * 4
        let prefixout .= '>' . repeat(' ', bcount)
        let pos = newpos
    endwhile
    if ! empty(prefixout) && prefixout =~ '> *$'
        let prefixout .= ' '
    endif
    return [prefixout, lineout]
endfunction

function! s:FormatEmailBlock(lnum, lcount, maxwidth)

    let linesin = getline(a:lnum, a:lnum + a:lcount - 1) 
    let linesout = []

    let currunit = linesin[0]
    let currfieldname = s:FindFieldName(a:lnum)

    let i = 1
    while ! empty(currfieldname) && i < len(linesin)

        let nextline = linesin[i]

        if nextline =~ '\m^\s\+\S'
            let currunit .= nextline
        else
            let linesout += 
              \ s:BreakHeaderField(currunit, a:maxwidth, currfieldname)
            let currfieldname = s:ExtractFieldName(nextline)
            let currunit = nextline
        endif

        let i += 1

    endwhile

    if ! empty(currfieldname)
        let linesout += s:BreakHeaderField(currunit, a:maxwidth, currfieldname)
    else

        let [currprefix, currunit] = s:SeparatePrefix(currunit)
        while i < len(linesin)
            let [nextprefix, nextline] = s:SeparatePrefix(linesin[i])
            if nextline =~ '\m^--\s*$' " never spill over into signature...
                break
            endif
            if nextline =~ '\m^\s*$' || nextprefix !=# currprefix
                let linesout += 
                  \ s:BreakBodyText(currunit, a:maxwidth, currprefix)
                let currunit = nextline
                let currprefix = nextprefix
            else
                if currunit =~ '\m^\s*$'
                    let linesout += [currprefix] " don't clobber last space
                elseif currunit =~ '\S$' && nextline =~ '^\S'
                    let currunit .= ' '
                endif
                let currunit .= nextline
            endif
            let i += 1
        endfor

        let linesout += s:BreakBodyText(currunit, a:maxwidth, currprefix)

        if i < len(linesin) " only here for signature...
            let linesout += linesin[i :]
        endif

    endif

    let lcountdiff = len(linesout) - a:lcount
    if lcountdiff > 0
        call append(a:lnum, repeat([""], lcountdiff))
    elseif lcountdiff < 0
        silent execute ':' . a:lnum . ',' . (a:lnum - lcountdiff - 1) . 'd'
    endif
    call setline(a:lnum, linesout)

    return 0

endfunction

" FIXME: take line num from v:lnum instead of line('.')?
function! s:FormatEmailInsert(char, maxwidth)
    let lnum = line('.')
    let linein = getline(lnum)

    if strlen(substitute(linein, '.', 'x', 'g')) < a:maxwidth
        return 0
    endif

    let cnum = col('.')
    let vcnum = cnum
    let fieldname = s:FindFieldName(lnum)

    let linetemp = a:char . "\n" . linein[cnum - 1 :]
    if cnum > 1
        let linetemp = linein[: cnum - 2] . linetemp
    endif

    let j = 1
    if empty(fieldname)
        let [prefix, linein] = s:SeparatePrefix(linetemp)
        let linesout = s:BreakBodyText(linein, a:maxwidth, prefix)
        while j < len(linesout)
            let [nextprefix, nextline] = s:SeparatePrefix(getline(lnum + j))
            " FIXME: first test does not need to be done on every iteration...
            if cnum > a:maxwidth || nextline =~ '\m^\%(--\)\=\s*$' || 
              \ nextprefix !=# prefix
                break
            endif
            let lastline = linesout[j]
            if lastline =~ '\m\S$' && nextline =~ '\m^\S'
                let lastline .= ' '
            endif
            let lastline .= nextline
            " FIXME: hmmm, what about breaking very long lines? need to merge
            " remainder of array with last line of break body text call...
            let linesout = linesout[: j - 1] + 
              \ s:BreakBodyText(lastline, a:maxwidth, prefix)
            let j += 1
        endwhile
    else
        " FIXME: check cnum as breakbody above?
        let linesout = s:BreakHeaderField(linetemp, a:maxwidth, fieldname)
        while j < len(linesout)
            let nextline = getline(lnum + j)
            if nextline !~# '\m^\s\+\S'
                break
            endif
            let lastline = linesout[j] . nextline
            let linesout = linesout[: j - 1] + 
              \ s:BreakHeaderField(lastline, a:maxwidth, fieldname)
            let j += 1
        endwhile
    endif

    " insert extra blank lines if needed
    if len(linesout) > j
        call append(lnum, repeat([""], len(linesout) - j))
    endif

    " find first \n to get new line and column numbers...
    let i = -1
    let j = -1
    while i < 0 && j < len(linesout) 
        let j += 1
        let i = match(linesout[j], '\m' . escape(a:char, '*\^$.~[]') . "\n")
    endwhile
    let nlnum = lnum + j
    let ncnum = i + 1

    " remove marker and inserted character...
    if j < len(linesout)
        let linesout[j] = substitute(linesout[j], 
          \ '\m' . escape(a:char, '*\^$.~[]') . "\n", '', 'g')
        let j += 1
    endif
    
    " just remove \n so prefixes work...
    while j < len(linesout)
        let linesout[j] = substitute(linesout[j], "\n", '', 'g')
        let j += 1
    endwhile

    " data out
    call setline(lnum, linesout)

    " move cursor if necessary
    if i > -1
        call cursor(nlnum, ncnum)
    endif

    return 0

endfunction

function! FormatEmailText()

    if mode() !~# '\m[niR]' || (mode() =~# '\m[iR]' && v:count != 1) || 
      \ v:char =~# '\m\s'
        echohl ErrorMsg
        echomsg "Assert(formatexpr): Unknown State: " 
          \ mode() v:lnum v:count string(v:char)
        echohl None
        return 1
    endif

    " rfc says 78 characters max, but let user override...
    let s:maxwidth = 78
    if &textwidth > 0
        let s:maxwidth = &textwidth
    endif

    if mode() =~# '\m[iR]'
        return s:FormatEmailInsert(v:char, s:maxwidth)
    endif

    return s:FormatEmailBlock(v:lnum, v:count, s:maxwidth)

endfunction

function! FixFlowed()
    let pos = getpos('.')

    " compress quote characters
    while search('^>\+\s\+>', 'w') > 0
        silent! s/\m^>\+\zs\s\+>/>/
    endwhile
    silent! %s/\m^>\+\zs\%([^[:space:]>]\)\@=/ /

    " strip off trailing spaces
    silent! %s/\m\s*$//

    " enforce one space after header names
    silent! 1;/\m^$/s/\m^\w\+:\zs\s*\%(\_S\)\@=/ /

    " put a space back after signature delimiter
    silent! $?\m^--$?s/$/ /

    " un-space stuff from
    silent! 1/\m^$/;/\m^-- $/s/\m^\s\(\s*\)\zeFrom\_s/\1/
    
    " put spaces back at ends of lines in paragraph lines, where paragraph lines
    " are defined as lines followed by lines with the same quote prefix (nothing
    " or some number of > followed by a space) that starts with no more than 3
    " spaces followed by an optional opening punctuation mark, one of "*([{@~|>,
    " that is immediately followed by a letter or digit.
    silent! 1/\m^$/;/\m^-- $/s/\m^\(>\+\s\|\).*\S\zs\%(\_$\n\1 \{,3}["*(\[{@~|<]\=[0-9A-Za-z]\)\@=/ /

    " space stuff from
    silent! 1/\m^$/;/\m^-- $/s/\m^\ze\s*From\_s/ /

    call setpos('.', pos)
endfunction

function! SetEmail(address, sigfile)
    let pos = getpos('.')
    call FixFlowed()
    execute '1;/\m^$/s/\m^From:\zs.*/ ' . a:address . '/'
    silent! /\m^-- /,$d
    execute '$normal o-- '
    execute 'r ' . a:sigfile
    call setpos('.', pos)
endfunction

