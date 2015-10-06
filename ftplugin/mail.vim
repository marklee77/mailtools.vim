" This function breaks a string into an array of strings with specified maximum
" width, breaking after the specified pattern, and prepending lines beyond the
" first with the given prefix. Blanks are stripped from the beginning of
" subsequent lines, though support may be added for specifying a different
" pattern for this in the future.
function! s:BreakLine(linein, maxwidth, breakafter, minbreak, prefix)
    if strlen(substitute(a:linein, '.', 'x', 'g')) <= a:maxwidth
        return [a:linein]
    endif
    let startpos = 0
    let breakpos = -1
    while 0 <= startpos && (breakpos < a:minbreak || startpos <= a:maxwidth)
        let breakpos = startpos
        let startpos = match(a:linein, a:breakafter, startpos + 1)
    endwhile
    if breakpos >= a:minbreak
        let linesout = [a:linein[: breakpos]]
        let startpos = match(a:linein, '\m\S', breakpos + 1)
        if startpos < breakpos + 1
            return linesout
        endif
        return linesout + s:BreakLine(a:prefix . a:linein[startpos :],
                                    \ a:maxwidth, a:breakafter, a:minbreak, a:prefix)
    endif
    return [a:linein]
endfunction

function! s:BreakHeaderField(linein, maxwidth, fieldname)
    let breakafter = '\m\s'
    if a:fieldname =~# '\v^From|To|Cc|Bcc|Reply-To$'
        let breakafter = '\m,'
    endif
    return s:BreakLine(a:linein, a:maxwidth, breakafter, 2, ' ')
endfunction

function! s:BreakBodyText(linein, maxwidth, prefix)
    return s:BreakLine(a:prefix . a:linein, a:maxwidth, '\m\s', strlen(a:prefix), a:prefix)
endfunction

function! s:ExtractFieldName(field)
    return matchstr(a:field, '\m^[!-9;-~]\+\ze:') " specified by rfc
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
        elseif currline !~# '\m^\s'
            return ''
        endif
        let i += 1
    endwhile
    return fieldname
endfunction

" This is a little bit tricky, but basically go along and count >'s separated
" only by whitespace to get the quote depth. If ever there are 4 or more
" consecutive whitespace character then the text is pre-formatted, so anything
" past the 4 spaces should be considered part of the line proper. Construct a
" new prefix that is the quote depth consecutive > characters, followed by a
" space if the quote depth is more than 0 to improve readability. Follow that
" with four spaces if the text is pre-formatted. As an additional consideration,
" if the quote depth is at least one, then pre-formatted text should be detected
" if there are 4 or more spaces, but presented with 5 spaces to be consistent.
function! s:SeparatePrefix(linein)

    let quotedepth = 0
    let preformatted = 0
    let prefixinlen = 0
    
    while prefixinlen < strlen(a:linein)
        let pos = match(a:linein, '\m\s*\zs\S\|$', prefixinlen)
        if pos == -1 
            break
        elseif pos - prefixinlen > 3
            let prefixinlen += 4    
            let preformatted = 1
            break
        elseif a:linein[pos] !=# '>'
            let prefixinlen = pos
            break
        endif
        let quotedepth += 1
        let prefixinlen = pos + 1
    endwhile

    if prefixinlen == 0
        let prefixout = ''
        let lineout   = a:linein
    else
        let prefixout = repeat('>', quotedepth)
        if quotedepth
            let prefixout .= ' '
        endif
        if preformatted
            let prefixout .= '    '
        endif
        if quotedepth && preformatted && a:linein[prefixinlen] =~ '\m\s'
            let prefixinlen += 1
        endif
        let lineout = a:linein[prefixinlen :]
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

function! s:FormatEmailInsert(char, maxwidth)
    let lnum = line('.')
    let linein = getline(lnum)

    if strlen(substitute(linein, '.', 'x', 'g')) < a:maxwidth
        return 0
    endif

    let cnum = col('.')
    let fieldname = s:FindFieldName(lnum)

    let linetemp = "\n" . linein[cnum - 1 :]
    if cnum > 1
        let linetemp = linein[: cnum - 2] . linetemp
    endif

    let j = 1
    if empty(fieldname)
        let [prefix, linein] = s:SeparatePrefix(linetemp)
        let linesout = s:BreakBodyText(linein, a:maxwidth, prefix)
        while j < len(linesout)
            let [nextprefix, nextline] = s:SeparatePrefix(getline(lnum + j))
            if nextline =~ '\m^\%(--\)\=\s*$' || nextprefix !=# prefix
                break
            endif
            let [lastprefix, lastline] = s:SeparatePrefix(linesout[j])
            if lastline =~ '\m\S$' && nextline =~ '\m^\S'
                let lastline .= ' '
            endif
            let lastline .= nextline
            let linesout = linesout[: j - 1] + 
              \ s:BreakBodyText(lastline, a:maxwidth, prefix)
            let j += 1
        endwhile
    else
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

    " find \n to get new line and column numbers...
    let i = -1
    let j = -1
    while i < 0 && j < len(linesout) 
        let j += 1
        let i = match(linesout[j], '\m\n')
    endwhile
    let nlnum = lnum + j
    let ncnum = i + 1

    " remove marker
    if j < len(linesout)
        let linesout[j] = substitute(linesout[j], '\m\n', '', 'g')
    endif
    
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
    let lnum = pos[1]

    " strip off trailing spaces, except on current line
    execute 'silent! 1;' . (pos[1] - 1) . 's/\m\s*$//'
    execute 'silent! '   . (pos[1] + 1) . ';$s/\m\s*$//'

    " enforce one space after header names
    silent! 1;/\m^$/s/\m^\w\+:\zs\s*\%(\_S\)\@=/ /

    " put a space back after signature delimiter
    silent! $?\m^--$?s/$/ /

    " compress quote characters
    while search('^>\+\s\+>', 'w') > 0
        silent! s/\m^>\+\zs\s\+>/>/
    endwhile
    silent! %s/\m^>\+\zs\%([^[:space:]>]\)\@=/ /

    " un-space stuff from
    silent! 1/\m^$/;/\m^-- $/s/\m^\s\(\s*\)\zeFrom\_s/\1/
    
    " put spaces back at ends of lines in paragraph lines, where paragraph lines
    " are defined as lines including at least 2 sequential letters, followed by
    " lines with the same quote prefix (nothing or some number of > followed by
    " a space) that starts with no more than 3 spaces followed by an optional
    " opening punctuation mark, one of "*([{@~|>, that is immediately followed
    " by a letter or digit.
    silent! 1/\m^$/;/\m^-- $/s/\m^\(>\+\s\|\).*\a\{2,}.*\S\zs\%(\_$\n\1 \{,3}["*(\[{@~|<]\=[0-9A-Za-z]\)\@=/ /

    " space stuff from
    silent! 1/\m^$/;/\m^-- $/s/\m^\ze\s*From\_s/ /

    call setpos('.', pos)
endfunction

function! SetEmail(address, sigfile)
    let pos = getpos('.')
    call FixFlowed()
    execute 'silent! 1;/\m^$/s/\m^From:\zs.*/ ' . a:address . '/'
    silent! /\m^-- /,$d
    execute '$normal o-- '
    execute 'r ' . a:sigfile
    call setpos('.', pos)
endfunction
