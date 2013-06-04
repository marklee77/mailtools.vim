" TODO: configuration
" FIXME: need virtual column support for accented chars

" This function breaks a string into an array of strings with specified maximum
" width, breaking after the specified pattern, and prepending lines beyond the
" first with the given prefix. Blanks are stripped from the beginning of
" subsequent lines, though support may be added for specifying a different
" pattern for this in the future.
function! s:BreakLine(linein, maxwidth, breakbefore, prefix)
    " ignore \n when calculating string length since this is used as the marker
    " char for insert formatting..
    if strlen(substitute(a:linein, "\n", '', 'g')) <= a:maxwidth 
        return [a:linein]
    endif
    let startpos = 0
    let breakpos = 0
    while 0 <= startpos && startpos <= a:maxwidth
        let breakpos = startpos
        let startpos = match(a:linein, a:breakbefore, startpos + 1)
    endwhile
    if breakpos > 0
        let linesout = [a:linein[: breakpos - 1]]
        let startpos = match(a:linein, '\m\S', breakpos)
        if startpos < 0
            return linesout
        endif
        return linesout + s:BreakLine(a:prefix . a:linein[startpos :], 
                                    \ a:maxwidth, a:breakbefore, a:prefix)
    endif
    return [a:linein]
endfunction

function! s:BreakHeaderField(linein, maxwidth, fieldname)
    let breakbefore = '\m\s'
    if a:fieldname =~# '\v^From|To|Cc|Bcc|Reply-To$'
        let breakbefore = '\m,\zs.\ze'
    endif
    return s:BreakLine(a:linein, a:maxwidth, breakbefore, ' ')
endfunction

function! s:BreakParagraph(linein, maxwidth, prefix)
    return s:BreakLine(a:prefix . a:linein, a:maxwidth, '\m\s', a:prefix)
endfunction

function! s:ExtractFieldName(field)
    let field = substitute(a:field, "\n", '', 'g')
    return matchstr(field, '\m^\zs[!-9;-~]\+\ze:') 
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

" TODO: configurable variables for quote char, tab stop width, minimum spacing?
function! s:SeparatePrefix(linein)
    " \n can be in the prefix initially, but we throw it away since if the user
    " is in the prefix there shouldn't be any reason to update the cursor
    " position
    let pos = match(a:linein, '\m^[>[:blank:]\n]*\zs[^>[:blank:]\n]\ze') 
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
    let prefixin = substitute(prefixin, "\n", '', 'g') " prefix shouldn't wrap
    let pos = match(prefixin, '\m>\|$')
    let prefixout = repeat(' ', (pos / 4) * 4)
    while pos < len(prefixin)
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

" FIXME: some spaces being lost
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
                  \ s:BreakParagraph(currunit, a:maxwidth, currprefix)
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

        let linesout += s:BreakParagraph(currunit, a:maxwidth, currprefix)

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

" TODO: vcharwidth support wanted?
function! s:CharWidth(char)
    if empty(a:char)
        return 0
    endif
    return 1
endfunction

" FIXME: adding a character to the prefix that causes an overflow can be a
" problem....
" problem at end of line right now...
function! s:FormatEmailInsert(char, maxwidth)
    let lnum = line('.')
    let linein = getline(lnum)
    let cwidth = s:CharWidth(a:char)

    if len(linein) + cwidth < a:maxwidth
        return 0
    endif

    let cnum = col('.')
    let vcnum = cnum
    let fieldname = s:FindFieldName(lnum)

    " -2 because columns are 1 indexed AND cursor moves on before printing char
    let linein = linein[: cnum - 2] . a:char . "\n" . linein[cnum - 1 :]

    if empty(fieldname)
        let [prefix, linein] = s:SeparatePrefix(linein)
        let linesout = s:BreakParagraph(linein, a:maxwidth, prefix)
    else
        let linesout = s:BreakHeaderField(linein, a:maxwidth, fieldname)
    endif

    " FIXME: handle overflow by merging in block...
    if len(linesout) > 1
        call append(lnum, repeat([""], len(linesout) - 1))
    endif

    " find first \n to get new line and column numbers...
    let i = -1
    let j = -1
    while i < 0 && j < len(linesout) 
        let j += 1
        let i = match(linesout[j], "\n")
    endwhile

    " remove marker...
    if j < len(linesout)
        let linesout[j] = substitute(linesout[j], a:char . "\n", '', 'g')
    endif

    " data out
    call setline(lnum, linesout)

    " move cursor if necessary
    if i > -1
        call cursor(lnum + j, i)
    endif

    return 0

endfunction

function! FormatEmailText()

    if mode() =~# '\m[iR]' && &formatoptions =~# 'a'
        return 1
    elseif mode() !~# '\m[niR]' || (mode() =~# '\m[iR]' && v:count != 1) || 
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

" function! NumLinesToSig()
"    let cur_line = line('.')
"    let last_line = line('$')
"    let i = 0
"    while cur_line + i < last_line && getline(cur_line + i + 1) !~ '^--\s*$'
"        let i += 1
"    endwhile
"    return i + 1
"endfunction

set formatexpr=FormatEmailText()

nnoremap <silent> Q /^\(\s*>\)\@!<CR>
onoremap <silent> Q V/^.*\n\(\s*>\)\@!<CR>
nnoremap <silent> S /^.*\n--\s*\_$<CR>
onoremap <silent> S V/^.*\n.*\n--\s*\_$<CR>

set spell spelllang=en_us textwidth=78

" FIXME: move these to vimrc?
let g:gcc_pattern = '^\(To\|Cc\|Bcc\|Reply-To\):'
let b:SuperTabDisabled=0
let g:SuperTabDefaultCompletionType = "\<c-x>\<c-o>"

function! QueryWrapper(findstart, base)
    let results = QueryCommandComplete(a:findstart, a:base)
    if ! empty(results)
        return results
    endif
    let entry = {}
    let entry.word = "\t"
    let entry.abbr = "\t"
    let entry.menu = "\t"
    let entry.icase = 1
    return [entry]
endfunction

"set omnifunc=QueryCommandComplete
"set omnifunc=QueryWrapper
