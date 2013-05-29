
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

function! BreakHeaderLine(lnum, maxwidth)
    let str = getline(a:lnum)
    if strlen(str) <= a:maxwidth
        return 0
    endif
    let breakpos = 0 
    let startpos = max([0, match(str, ':')])
    while 0 <= startpos && startpos <= a:maxwidth
        let breakpos = startpos
        let startpos = match(str, ',', startpos + 1)
    endwhile
    if breakpos > 0
        exec ':' . a:lnum . 'd'
        call append(a:lnum - 1, str[: breakpos])
        let nextlinestart = match(str, '[^[:blank:]]', breakpos + 1)
        if nextlinestart < 0
            return 0
        endif
        call append(a:lnum, ' ' . str[nextlinestart :])
        return BreakHeaderLine(a:lnum+1, a:maxwidth)
    endif
    return 1
endfunction

function! EmailFormatExpr()
    if mode() =~# '[iR]' && &formatoptions =~# 'a'
        return 1
    endif
    if empty(GetHeaderField(v:lnum))
        return 1
    endif
    let maxwidth = 78
    if &textwidth > 0
        let maxwidth = &textwidth
    endif
    call BreakHeaderLine(v:lnum, maxwidth)
    return 0 
endfunction

set formatexpr=EmailFormatExpr()

nnoremap <silent> Q /^\(\s*>\)\@!<CR>
onoremap <silent> Q V/^.*\n\(\s*>\)\@!<CR>
nnoremap <silent> S /^.*\n--\s*\_$<CR>
onoremap <silent> S V/^.*\n.*\n--\s*\_$<CR>

set spell spelllang=en_us textwidth=78
set omnifunc=QueryCommandComplete

let g:gcc_pattern = '^\(To\|Cc\|Bcc\|Reply-To\):'
let g:SuperTabDefaultCompletionType = "\<c-x>\<c-o>"
