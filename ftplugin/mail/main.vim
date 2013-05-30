
function! NumLinesToSig()
    let cur_line = line('.')
    let last_line = line('$')
    let i = 0
    while cur_line + i < last_line && getline(cur_line + i + 1) !~ '^--\s*$'
        let i += 1
    endwhile
    return i + 1
endfunction

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

" FIXME: break char is header dependent...
function! BreakHeaderLine(linein, maxwidth)
    if strlen(a:linein) <= a:maxwidth
        return [a:linein]
    endif
    let breakpos = 0 
    let startpos = max([0, match(a:linein, ':')])
    while 0 <= startpos && startpos <= a:maxwidth
        let breakpos = startpos
        let startpos = match(a:linein, ',', startpos + 1)
    endwhile
    if breakpos > 0
        let linesout = [a:linein[: breakpos]]
        let nextlinestart = match(a:linein, '[^[:blank:]]', breakpos + 1)
        if nextlinestart < 0
            return linesout
        endif
        return linesout + BreakHeaderLine(' ' . a:linein[nextlinestart :], a:maxwidth)
    endif
    return [a:linein]
endfunction

function! FormatHeaderBlock(lnum, lcount, maxwidth)
    let linesin = getline(a:lnum, a:lnum + a:lcount - 1) 
    let linesout = []
    let currline = linesin[0]
    let curridx = 1
    while curridx < a:lcount
        let h = matchstr(linesin[curridx], '^\zs[!-~][!-~]*\ze:')
        if empty(h)
            let currline .= linesin[curridx]
        else
            let linesout += BreakHeaderLine(currline, a:maxwidth)
            let currline = linesin[curridx]
        endif
        let curridx += 1
    endwhile
    let linesout += BreakHeaderLine(currline, a:maxwidth)
    if len(linesin) == 1 && len(linesout) == 1 " FIXME: hack
        return 0
    endif
    exec ':' . a:lnum . ',' . (a:lnum + a:lcount - 1) . 'd'
    call append(a:lnum - 1, linesout)
    return 0
endfunction

function! EmailFormat()

    if mode() =~# '[iR]' && &formatoptions =~# 'a'
        return 1
    elseif mode() !~# '[niR]' || (mode() =~# '[iR]' && v:count != 1) ||v:char =~# '\s'
        echohl ErrorMsg
        echomsg "Assert(formatexpr): Unknown State: " mode() v:lnum v:count string(v:char)
        echohl None
        return 1
    endif

    " only do special formatting for header...
    if empty(GetHeaderField(s:lnum))
        return 1
    endif

    " rfc says 78 characters max, but let user override...
    let s:maxwidth = 78
    if &textwidth > 0
        let s:maxwidth = &textwidth
    endif

    if mode() == 'n'
        return FormatHeaderBlock(v:lnum, v:count, s:maxwidth)
    endif

    if v:char == ''
        return FormatHeaderBlock(line('.'), 1, s:maxwidth)
    endif

    return 0 
endfunction

set formatexpr=EmailFormat()

nnoremap <silent> Q /^\(\s*>\)\@!<CR>
onoremap <silent> Q V/^.*\n\(\s*>\)\@!<CR>
nnoremap <silent> S /^.*\n--\s*\_$<CR>
onoremap <silent> S V/^.*\n.*\n--\s*\_$<CR>

set spell spelllang=en_us textwidth=78
set omnifunc=QueryCommandComplete

let g:gcc_pattern = '^\(To\|Cc\|Bcc\|Reply-To\):'
let g:SuperTabDefaultCompletionType = "\<c-x>\<c-o>"
