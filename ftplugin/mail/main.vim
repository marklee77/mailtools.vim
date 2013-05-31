" FIXME: long lines, scope, configuration
" FIXME: break line is hacky...

" This function breaks a string into an array of strings with specified maximum
" width, breaking after the specified pattern, and prepending lines beyond the
" first with the given prefix.  Blanks are stripped from the beginning of
" subsequent lines, though support may be added for specifying a different
" pattern for this in the future.
function! BreakLine(linein, maxwidth, breakbefore, prefix)
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
        let startpos = match(a:linein, '[^[:blank:]]', breakpos)
        if startpos < 0
            return linesout
        endif
        return linesout + BreakLine(a:prefix . a:linein[startpos :], a:maxwidth, a:breakbefore, a:prefix)
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
    return '[[:blank:]][[:blank:]]*'
endfunction

" FIXME: configurable?
function! ExtractQuotePrefix(linein)
   return matchstr(a:linein, '^[[:blank:]]*>[[:blank:]>]*') 
endfunction

" FIXME: need to add support for quote text...
" need an inheader state variable...
" ugh, loses emails...
function! FormatEmailBlock(lnum, lcount, maxwidth)

    let linesin = getline(a:lnum, a:lnum + a:lcount - 1) 
    let linesout = []

    let currunit = linesin[0]
    let currfieldname = FindFieldName(a:lnum)
    let inheader = ! empty(currfieldname)

    let nextlineidx = 1

    while inheader && nextlineidx < len(linesin)
        let nextline = linesin[nextlineidx]
        if nextline =~ '^\s*$'
            let inheader = 0
        else
            let nextfieldname = ExtractFieldName(nextline)
        endif
        if inheader && empty(nextfieldname)    
            let currunit .= nextline
        else
            let breakbefore = GetBreakBefore(currfieldname)
            let linesout += BreakLine(currunit, a:maxwidth, breakbefore, ' ')
            let currunit = nextline
            let currfieldname = nextfieldname
        endif
        let nextlineidx += 1
    endwhile

    if inheader
        let breakbefore = GetBreakBefore(currfieldname)
        let linesout += BreakLine(currunit, a:maxwidth, breakbefore, ' ')
    endif

    let currquoteprefix = ExtractQuotePrefix(currunit)
    let currunit = currunit[len(currquoteprefix) :]

    while nextlineidx < len(linesin)
        let nextline = linesin[nextlineidx]
        let nextquoteprefix = ExtractQuotePrefix(nextline)
        let nextline = nextline[len(nextquoteprefix) :]
        if nextline =~ '^\s*$' || nextquoteprefix !~ '^' . currquoteprefix . '[[:blank:]]*$'
            let linesout += BreakLine(currquoteprefix . currunit, a:maxwidth, '[[:blank:]][[:blank:]]*', currquoteprefix)
            let currunit = nextline
            let currquoteprefix = nextquoteprefix
        else
            if currunit =~ '^\s*$'
                let linesout += [""] " don't clobber last space
            elseif currunit =~ '^.*[^\s]$' && nextline =~ '^[^\s].*$'
                let currunit .= ' '
            endif
            let currunit .= nextline
        endif
        let nextlineidx += 1
    endfor
    
    if ! inheader
        let linesout += BreakLine(currquoteprefix . currunit, a:maxwidth, '[[:blank:]][[:blank:]]*', currquoteprefix)
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

" FIXME: tab widths, or VCharWidth?
function! CharWidth(char)
    if empty(a:char)
        return 0
    endif
    return 1
endfunction

" FIXME: handle variable width characters and tabs...
function! FormatEmailInsert(char, maxwidth)
    let cnum = col('.')
    let vcnum = cnum
    let lnum = line('.')
    let linein = getline(lnum)
    let cwidth = CharWidth(a:char)
    if len(linein) + cwidth < a:maxwidth
        return 1
    endif
    let fieldname = FindFieldName(lnum)
    if empty(fieldname)
        return 1 " yeah, needs work...
        let breakbefore = '[[:blank:]][[:blank:]]*'
        let prefix = ''
    else
        let breakbefore = GetBreakBefore(fieldname)
        let prefix = ' '
    endif

    let linesout = BreakLine(linein, a:maxwidth, breakbefore, prefix)
    if len(linesout) > 1 && cnum > len(linesout[0])
        let nlnum = lnum + 1
        " if we've moved down to the second line, the new column is the same,
        " minus the length of the first line, including any spaces that may have
        " been stripped from the end.
        " let spacesdeleted = len(linein) - len(linesout[0]) - len(linesout[1])
        " let ncnum = cnum - len(linesout[0]) - spacesdeleted
        let ncnum = cnum + len(linesout[1]) - len(linein)
    endif

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
        return FormatEmailInsert(v:char, s:maxwidth)
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

let g:gcc_pattern = '^\(To\|Cc\|Bcc\|Reply-To\):'
let g:SuperTabDefaultCompletionType = "\<c-x>\<c-o>"
set omnifunc=QueryCommandComplete
