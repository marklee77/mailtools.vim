" FIXME: long lines and scope

" This function breaks a string into an array of strings with specified maximum
" width, breaking after the specified pattern, and prepending lines beyond the
" first with the given prefix.  Blanks are stripped from the beginning of
" subsequent lines, though support may be added for specifying a different
" pattern for this in the future.
function! BreakLine(linein, maxwidth, breakbefore, startat, prefix)
    if strlen(a:linein) <= a:maxwidth
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
        let startpos = match(a:linein, a:startat, breakpos)
        if startpos < 0
            return linesout
        endif
        return linesout + BreakLine(a:prefix . a:linein[startpos :], a:maxwidth, a:breakbefore, a:startat, a:prefix)
    endif
    return [a:linein]
endfunction

function! ExtractFieldName(linein)
   return matchstr(a:linein, '^\zs[!-9;-~][!-9;-~]*\ze:') 
endfunction

function! FindFieldName(lnum)
    let i = 1
    let header = ''
    while i <= a:lnum
        let text = getline(i)
        let h = ExtractFieldName(text)
        if ! empty(h)
            let header = h
        " if it's not a field line and doesn't start with one blank, we're out
        " of the header
        elseif text !~ '^\s.*$' 
            return ''
        endif
        let i += 1
   endwhile
   return header
endfunction

function! InHeader(lnum)
    return ! empty(FindFieldName(a:lnum))
endfunction

function! GetBreakBefore(field)
    if a:field =~? '^\(from\|reply-to\|to\|cc\|bcc\|resent-from\|resent-to\|resent-cc\|resent-bcc\)'
        return ',\zs.\ze'
    endif
    return ' '
endfunction

" basically, there are three units: headers, body text, and quote text.
" oh, also sig separator and sig...
" FIXME: need to add support for quote text...
" need an inheader state variable...
function! FormatEmailBlock(lnum, lcount, maxwidth)
    let linesin = getline(a:lnum, a:lnum + a:lcount - 1) 
    let linesout = []
    let currunit = linesin[0]
    let currfieldname = FindFieldName(a:lnum)
    let inheader = ! empty(currfieldname)
    let breakbefore = GetBreakBefore(currfieldname)
    let startat = '[^[:blank:]]'
    let prefix = ''
    if ! empty(currfieldname)
        let prefix = ' '
    endif
    for currline in linesin[1 :]

        let currfieldname = ExtractFieldName(currline)
        if currline !~ '^\s*$' && ((! inheader) || empty(currfieldname))
            " add a space if there isn't one already...
            if currunit =~ '^.*[^\s]$' && currline =~ '^[^\s].*$'
                let currunit .= ' '
            endif
            let currunit .= currline
        else

            let linesout += BreakLine(currunit, a:maxwidth, breakbefore, startat, prefix)

            if inheader && currline =~ '^\s*$'
                let inheader = 0
                let prefix = ''
            endif

            if currunit !~ '^\s*$' && currline =~ '^\s*$'
                let linesout += [""]
            endif

            let breakbefore = GetBreakBefore(currfieldname)
            let currunit = currline

        endif
    endfor
    let linesout += BreakLine(currunit, a:maxwidth, breakbefore, startat, prefix)
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
" FIXME: doesn't handle it well if there is text after the cursor...
function! FormatEmailInsert(char, maxwidth)
    let cnum = col('.')
    let vcnum = cnum
    let lnum = line('.')
    let linein = getline(lnum)
    let cwidth = CharWidth(a:char)
    let breakpattern = HeaderBreakPattern(GetHeaderField(lnum))
    if empty(breakpattern)
        return 1
    endif
    if len(linein) < a:maxwidth
        return 0
    endif
    let linesout = BreakHeaderLine(linein[: cnum - 1] . a:char, a:maxwidth, breakpattern)
    let ncnum = len(linesout[-1]) - cwidth + 1
    let nlnum = lnum + len(linesout) - 1
    let linesout = linesout[:-2] + BreakHeaderLine(linesout[-1][: -1 - cwidth] . linein[cnum :], a:maxwidth, breakpattern)
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

    " rfc says 78 characters max, but let user override...
    let s:maxwidth = 78
    if &textwidth > 0
        let s:maxwidth = &textwidth
    endif

    if mode() =~# '[iR]'
        return 1
        "return FormatHeaderInsert(v:char, s:maxwidth)
    endif

    return FormatEmailBlock(v:lnum, v:count, s:maxwidth)

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
set omnifunc=QueryCommandComplete

let g:gcc_pattern = '^\(To\|Cc\|Bcc\|Reply-To\):'
let g:SuperTabDefaultCompletionType = "\<c-x>\<c-o>"
