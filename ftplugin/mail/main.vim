
" function! NumLinesToSig()
"    let cur_line = line('.')
"    let last_line = line('$')
"    let i = 0
"    while cur_line + i < last_line && getline(cur_line + i + 1) !~ '^--\s*$'
"        let i += 1
"    endwhile
"    return i + 1
"endfunction

function! GetHeaderField(lnum)
    let i = 1
    let header = ''
    while i <= a:lnum
        let text = getline(i)
        let h = matchstr(text, '^\zs[!-~][!-~]*\ze:')
        if ! empty(h)
            let header = h
        elseif text !~ '^\s.*$'
            return ''
        endif
        let i += 1
   endwhile
   return header
endfunction

function! InHeader(lnum)
    return ! empty(GetHeaderField(lnum)
endfunction

function! BreakHeaderLine(linein, maxwidth, pattern)
    if strlen(a:linein) <= a:maxwidth
        return [a:linein]
    endif
    let startpos = max([0, match(a:linein, ':')])
    let breakpos = startpos
    while 0 <= startpos && startpos <= a:maxwidth
        let breakpos = startpos
        let startpos = match(a:linein, a:pattern, startpos + 1)
    endwhile
    if breakpos > 0
        let linesout = [a:linein[: breakpos]]
        let nextlinestart = match(a:linein, '[^[:blank:]]', breakpos + 1)
        if nextlinestart < 0
            return linesout
        endif
        return linesout + BreakHeaderLine(' ' . a:linein[nextlinestart :], a:maxwidth, a:pattern)
    endif
    return [a:linein]
endfunction

" FIXME: break char is header dependent...
function! FormatHeaderBlock(lnum, lcount, maxwidth)
    let linesin = getline(a:lnum, a:lnum + a:lcount - 1) 
    let linesout = []
    let currfield = linesin[0]
    for currline in linesin[1 :]
        if empty(matchstr(currline, '^\zs[!-~][!-~]*\ze:'))
            let currfield .= currline
        else
            let linesout += BreakHeaderLine(currfield, a:maxwidth, ',')
            let currfield = currline
        endif
    endfor
    let linesout += BreakHeaderLine(currfield, a:maxwidth, ',')
    let lcountdiff = len(linesout) - a:lcount
    if lcountdiff > 0
        call append(a:lnum, repeat([""], lcountdiff))
    elseif lcountdiff < 0
        silent execute ':' . a:lnum . ',' . (a:lnum - lcountdiff - 1) . 'd'
    endif
    call setline(a:lnum, linesout)
    return 0
endfunction

" FIXME: tab widths, or VCharWidth?
function! CharWidth(char)
    if empty(a:char)
        return 0
    endif
    return 1
endfunction

" FIXME: handle variable width characters and tabs...
function! FormatHeaderInsert(char, maxwidth)
    let cnum = col('.')
    let vcnum = cnum
    let lnum = line('.')
    let linein = getline(lnum)
    let cwidth = CharWidth(a:char)
    if len(linein) < a:maxwidth
        return 0
    endif
    let linesout = BreakHeaderLine(linein[: cnum - 1] . a:char, a:maxwidth, ',')
    let ncnum = len(linesout[-1]) - cwidth + 1
    let nlnum = lnum + len(linesout) - 1
    let linesout = linesout[:-2] + BreakHeaderLine(linesout[-1][: -1 - cwidth] . linein[cnum :], a:maxwidth, ',')
    if len(linesout) > 1
        call append(lnum, repeat([""], len(linesout) - 1))
    endif
    call setline(lnum, linesout)
    call cursor(nlnum, ncnum)
    return 0
endfunction

function! FormatEmailText()

    if mode() =~# '[iR]' && &formatoptions =~# 'a'
        return 1
    elseif mode() !~# '[niR]' || (mode() =~# '[iR]' && v:count != 1) ||v:char =~# '\s'
        echohl ErrorMsg
        echomsg "Assert(formatexpr): Unknown State: " mode() v:lnum v:count string(v:char)
        echohl None
        return 1
    endif

    " only do special formatting for header...
    if ! InHeader(s:lnum)
        return 1
    endif

    " rfc says 78 characters max, but let user override...
    let s:maxwidth = 78
    if &textwidth > 0
        let s:maxwidth = &textwidth
    endif

    if mode() =~# '[iR]'
        return FormatHeaderInsert(v:char, s:maxwidth)
    endif

    return FormatHeaderBlock(v:lnum, v:count, s:maxwidth)
endfunction

set formatexpr=FormatEmailText()

nnoremap <silent> Q /^\(\s*>\)\@!<CR>
onoremap <silent> Q V/^.*\n\(\s*>\)\@!<CR>
nnoremap <silent> S /^.*\n--\s*\_$<CR>
onoremap <silent> S V/^.*\n.*\n--\s*\_$<CR>

set spell spelllang=en_us textwidth=78
set omnifunc=QueryCommandComplete

let g:gcc_pattern = '^\(To\|Cc\|Bcc\|Reply-To\):'
let g:SuperTabDefaultCompletionType = "\<c-x>\<c-o>"
