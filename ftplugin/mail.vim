" FIXME: long lines, scope, configuration
" FIXME: normalize regular expressions

" This function breaks a string into an array of strings with specified maximum
" width, breaking after the specified pattern, and prepending lines beyond the
" first with the given prefix. Blanks are stripped from the beginning of
" subsequent lines, though support may be added for specifying a different
" pattern for this in the future.

" FIXME: right strip text or start from right
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

function! BreakHeaderField(linein, maxwidth, fieldname)
    let breakbefore = '[[:blank:]][[:blank:]]*'
    if a:fieldname =~? '^\(from\|reply-to\|to\|cc\|bcc\|resent-from\|resent-to\|resent-cc\|resent-bcc\)'
        let breakbefore = ',\zs.\ze'
    endif
    return BreakLine(a:linein, a:maxwidth, breakbefore, ' ')
endfunction

function! BreakParagraph(linein, maxwidth, prefix)
    return BreakLine(a:prefix . a:linein, a:maxwidth, '[[:blank:]]', a:prefix)
endfunction

function! ExtractFieldName(field)
    return matchstr(a:field, '^\zs[!-9;-~][!-9;-~]*\ze:') 
endfunction

function! FindFieldName(lnum)
    let fieldname = ''
    let i = 1
    while i <= a:lnum
        let currline = getline(i)
        let currfieldname = ExtractFieldName(currline)
        if ! empty(currfieldname)
            let fieldname = currfieldname
        " if it's not a field line and doesn't start with one blank, we're out
        " of the header
        elseif currline !~ '^\s.*$' 
            return ''
        endif
        let i += 1
    endwhile
    return fieldname
endfunction

" FIXME: configurable variables for quote char, tab stop width, minimum spacing?
function! SeparatePrefix(linein)
    let pos = match(a:linein, '^[>[:blank:]]*\zs[^>[:blank:]]\ze') 
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
    let pos = match(prefixin, '>\|$')
    let prefixout = repeat(' ', (pos / 4) * 4)
    while pos < len(prefixin)
        let pos += 1
        let newpos = match(prefixin, '>\|$', pos)
        let bcount = max([((newpos - pos) / 4) * 4, 1])
        let prefixout .= '>' . repeat(' ', bcount)
        let pos = newpos
    endwhile
    return [prefixout, lineout]
endfunction

function! FormatEmailBlock(lnum, lcount, maxwidth)

    let linesin = getline(a:lnum, a:lnum + a:lcount - 1) 
    let linesout = []

    let currunit = linesin[0]
    let currfieldname = FindFieldName(a:lnum)

    let i = 1
    while ! empty(currfieldname) && i < len(linesin)

        let nextline = linesin[i]

        if nextline =~ '^[[:blank:]][[:blank:]]*[^[:blank:]]'
            let currunit .= nextline
        else
            let linesout += BreakHeaderField(currunit, a:maxwidth, currfieldname)
            let currfieldname = ExtractFieldName(nextline)
            let currunit = nextline
        endif

        let i += 1

    endwhile

    if ! empty(currfieldname)
        let linesout += BreakHeaderField(currunit, a:maxwidth, currfieldname)
    else

        let [currprefix, currunit] = SeparatePrefix(currunit)
        while i < len(linesin)
            let [nextprefix, nextline] = SeparatePrefix(linesin[i])
            if nextline =~ '^--\s*$' " never spill over into signature...
                break
            endif
            if nextline =~ '^\s*$' || nextprefix !=# currprefix
                let linesout += BreakParagraph(currunit, a:maxwidth, currprefix)
                let currunit = nextline
                let currprefix = nextprefix
            else
                if currunit =~ '^\s*$'
                    let linesout += [""] " don't clobber last space
                elseif currunit =~ '^.*[^\s]$' && nextline =~ '^[^\s].*$'
                    let currunit .= ' '
                endif
                let currunit .= nextline
            endif
            let i += 1
        endfor

        let linesout += BreakParagraph(currunit, a:maxwidth, currprefix)

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
    let marker = "\n" " \n should not appear in any of the one-line strings...
    if len(linein) < a:maxwidth " + cwidth?
        return 0
    endif

    " -2 because columns are 1 indexed AND cursor moves on before printing char
    let linein = linein[: cnum - 2] . marker . linein[cnum - 1 :]
    let fieldname = FindFieldName(lnum)
    if empty(fieldname)
        let [prefix, linein] = SeparatePrefix(linein)
        let linesout = BreakParagraph(linein, a:maxwidth, prefix)
    else
        let linesout = BreakHeaderField(linein, a:maxwidth, fieldname)
    endif

    let i = -1
    let j = -1
    while i < 0 && j < len(linesout) 
        let j += 1
        let i = match(linesout[j], marker) 
    endwhile
    
    let linesout[j] = substitute(linesout[j], marker, '', '')

    " FIXME: intelligent overflow handling should merge with following line...
    if len(linesout) > 1
        call append(lnum, repeat([""], len(linesout) - 1))
    endif

    call setline(lnum, linesout)
    call cursor(lnum + j, i + 1)

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
