"TODO print messages when on visual mode. I only see VISUAL, not the messages.

" Function interface philosophy:
"
" - functions take arbitrary line numbers as parameters.
"    Current cursor line is only a suitable default parameter.
"
" - only functions that bind directly to user actions:
"
"    - print error messages.
"       All intermediate functions limit themselves return `0` to indicate an error.
"
"    - move the cursor. All other functions do not move the cursor.
"
" This is how you should view headers for the header mappings:
"
"   |BUFFER
"   |
"   |Outside any header
"   |
" a-+# a
"   |
"   |Inside a
"   |
" a-+
" b-+## b
"   |
"   |inside b
"   |
" b-+
" c-+### c
"   |
"   |Inside c
"   |
" c-+
" d-|# d
"   |
"   |Inside d
"   |
" d-+
" e-|e
"   |====
"   |
"   |Inside e
"   |
" e-+

" For each level, contains the regexp that matches at that level only.
"
let s:levelRegexpDict = {
    \ 1: '\v^(#[^#]@=|.+\n\=+$)',
    \ 2: '\v^(##[^#]@=|.+\n-+$)',
    \ 3: '\v^###[^#]@=',
    \ 4: '\v^####[^#]@=',
    \ 5: '\v^#####[^#]@=',
    \ 6: '\v^######[^#]@='
\ }

" Matches any header level of any type.
"
" This could be deduced from `s:levelRegexpDict`, but it is more
" efficient to have a single regexp for this.
"
let s:headersRegexp = '\v^(#|.+\n(\=+|-+)$)'

" Returns the line number of the first header before `line`, called the
" current header.
"
" If there is no current header, return `0`.
"
" @param a:1 The line to look the header of. Default value: `getpos('.')`.
"
function! s:GetHeaderLineNum(...)
    if a:0 == 0
        let l:l = line('.')
    else
        let l:l = a:1
    endif
    while(l:l > 0)
        if join(getline(l:l, l:l + 1), "\n") =~ s:headersRegexp
            return l:l
        endif
        let l:l -= 1
    endwhile
    return 0
endfunction

" -  if inside a header goes to it.
"    Return its line number.
"
" -  if on top level outside any headers,
"    print a warning
"    Return `0`.
"
function! s:MoveToCurHeader()
    let l:lineNum = s:GetHeaderLineNum()
    if l:lineNum !=# 0
        call cursor(l:lineNum, 1)
    else
        echo 'outside any header'
        "normal! gg
    endif
    return l:lineNum
endfunction

" Move cursor to next header of any level.
"
" If there are no more headers, print a warning.
"
function! s:MoveToNextHeader()
    if search(s:headersRegexp, 'W') == 0
        "normal! G
        echo 'no next header'
    endif
endfunction

" Move cursor to previous header (before current) of any level.
"
" If it does not exist, print a warning.
"
function! s:MoveToPreviousHeader()
    let l:curHeaderLineNumber = s:GetHeaderLineNum()
    let l:noPreviousHeader = 0
    if l:curHeaderLineNumber <= 1
        let l:noPreviousHeader = 1
    else
        let l:previousHeaderLineNumber = s:GetHeaderLineNum(l:curHeaderLineNumber - 1)
        if l:previousHeaderLineNumber == 0
            let l:noPreviousHeader = 1
        else
            call cursor(l:previousHeaderLineNumber, 1)
        endif
    endif
    if l:noPreviousHeader
        echo 'no previous header'
    endif
endfunction

" - if line is inside a header, return the header level (h1 -> 1, h2 -> 2, etc.).
"
" - if line is at top level outside any headers, return `0`.
"
function! s:GetHeaderLevel(...)
    if a:0 == 0
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:linenum = s:GetHeaderLineNum(l:line)
    if l:linenum !=# 0
        return s:GetLevelOfHeaderAtLine(l:linenum)
    else
        return 0
    endif
endfunction

" Return list of headers and their levels.
"
function! s:GetHeaderList()
    let l:bufnr = bufnr('%')
    let l:fenced_block = 0
    let l:front_matter = 0
    let l:header_list = []
    let l:vim_markdown_frontmatter = get(g:, 'vim_markdown_frontmatter', 0)
    let l:fence_str = ''
    for i in range(1, line('$'))
        let l:lineraw = getline(i)
        let l:l1 = getline(i+1)
        let l:line = substitute(l:lineraw, '#', "\\\#", 'g')
        " exclude lines in fenced code blocks
        if l:line =~# '\v^[[:space:]>]*(`{3,}|\~{3,})\s*(\w+)?\s*$'
            if l:fenced_block == 0
                let l:fenced_block = 1
                let l:fence_str = matchstr(l:line, '\v(`{3,}|\~{3,})')
            elseif l:fenced_block == 1 && matchstr(l:line, '\v(`{3,}|\~{3,})') ==# l:fence_str
                let l:fenced_block = 0
                let l:fence_str = ''
            endif
        " exclude lines in frontmatters
        elseif l:vim_markdown_frontmatter == 1
            if l:front_matter == 1
                if l:line ==# '---'
                    let l:front_matter = 0
                endif
            elseif i == 1
                if l:line ==# '---'
                    let l:front_matter = 1
                endif
            endif
        endif
        " match line against header regex
        if join(getline(i, i + 1), "\n") =~# s:headersRegexp && l:line =~# '^\S'
            let l:is_header = 1
        else
            let l:is_header = 0
        endif
        if l:is_header ==# 1 && l:fenced_block ==# 0 && l:front_matter ==# 0
            " remove hashes from atx headers
            if match(l:line, '^#') > -1
                let l:line = substitute(l:line, '\v^#*[ ]*', '', '')
                let l:line = substitute(l:line, '\v[ ]*#*$', '', '')
            endif
            " append line to list
            let l:level = s:GetHeaderLevel(i)
            let l:item = {'level': l:level, 'text': l:line, 'lnum': i, 'bufnr': bufnr}
            let l:header_list = l:header_list + [l:item]
        endif
    endfor
    return l:header_list
endfunction

" Returns the level of the header at the given line.
"
" If there is no header at the given line, returns `0`.
"
function! s:GetLevelOfHeaderAtLine(linenum)
    let l:lines = join(getline(a:linenum, a:linenum + 1), "\n")
    for l:key in keys(s:levelRegexpDict)
        if l:lines =~ get(s:levelRegexpDict, l:key)
            return l:key
        endif
    endfor
    return 0
endfunction

" Move cursor to parent header of the current header.
"
" If it does not exit, print a warning and do nothing.
"
function! s:MoveToParentHeader()
    let l:linenum = s:GetParentHeaderLineNumber()
    if l:linenum != 0
        call setpos("''", getpos('.'))
        call cursor(l:linenum, 1)
    else
        echo 'no parent header'
    endif
endfunction

" Return the line number of the parent header of line `line`.
"
" If it has no parent, return `0`.
"
function! s:GetParentHeaderLineNumber(...)
    if a:0 == 0
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:level = s:GetHeaderLevel(l:line)
    if l:level > 1
        let l:linenum = s:GetPreviousHeaderLineNumberAtLevel(l:level - 1, l:line)
        return l:linenum
    endif
    return 0
endfunction

" Return the line number of the previous header of given level.
" in relation to line `a:1`. If not given, `a:1 = getline()`
"
" `a:1` line is included, and this may return the current header.
"
" If none return 0.
"
function! s:GetNextHeaderLineNumberAtLevel(level, ...)
    if a:0 < 1
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:l = l:line
    while(l:l <= line('$'))
        if join(getline(l:l, l:l + 1), "\n") =~ get(s:levelRegexpDict, a:level)
            return l:l
        endif
        let l:l += 1
    endwhile
    return 0
endfunction

" Return the line number of the previous header of given level.
" in relation to line `a:1`. If not given, `a:1 = getline()`
"
" `a:1` line is included, and this may return the current header.
"
" If none return 0.
"
function! s:GetPreviousHeaderLineNumberAtLevel(level, ...)
    if a:0 == 0
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:l = l:line
    while(l:l > 0)
        if join(getline(l:l, l:l + 1), "\n") =~ get(s:levelRegexpDict, a:level)
            return l:l
        endif
        let l:l -= 1
    endwhile
    return 0
endfunction

" Move cursor to next sibling header.
"
" If there is no next siblings, print a warning and don't move.
"
function! s:MoveToNextSiblingHeader()
    let l:curHeaderLineNumber = s:GetHeaderLineNum()
    let l:curHeaderLevel = s:GetLevelOfHeaderAtLine(l:curHeaderLineNumber)
    let l:curHeaderParentLineNumber = s:GetParentHeaderLineNumber()
    let l:nextHeaderSameLevelLineNumber = s:GetNextHeaderLineNumberAtLevel(l:curHeaderLevel, l:curHeaderLineNumber + 1)
    let l:noNextSibling = 0
    if l:nextHeaderSameLevelLineNumber == 0
        let l:noNextSibling = 1
    else
        let l:nextHeaderSameLevelParentLineNumber = s:GetParentHeaderLineNumber(l:nextHeaderSameLevelLineNumber)
        if l:curHeaderParentLineNumber == l:nextHeaderSameLevelParentLineNumber
            call cursor(l:nextHeaderSameLevelLineNumber, 1)
        else
            let l:noNextSibling = 1
        endif
    endif
    if l:noNextSibling
        echo 'no next sibling header'
    endif
endfunction

" Move cursor to previous sibling header.
"
" If there is no previous siblings, print a warning and do nothing.
"
function! s:MoveToPreviousSiblingHeader()
    let l:curHeaderLineNumber = s:GetHeaderLineNum()
    let l:curHeaderLevel = s:GetLevelOfHeaderAtLine(l:curHeaderLineNumber)
    let l:curHeaderParentLineNumber = s:GetParentHeaderLineNumber()
    let l:previousHeaderSameLevelLineNumber = s:GetPreviousHeaderLineNumberAtLevel(l:curHeaderLevel, l:curHeaderLineNumber - 1)
    let l:noPreviousSibling = 0
    if l:previousHeaderSameLevelLineNumber == 0
        let l:noPreviousSibling = 1
    else
        let l:previousHeaderSameLevelParentLineNumber = s:GetParentHeaderLineNumber(l:previousHeaderSameLevelLineNumber)
        if l:curHeaderParentLineNumber == l:previousHeaderSameLevelParentLineNumber
            call cursor(l:previousHeaderSameLevelLineNumber, 1)
        else
            let l:noPreviousSibling = 1
        endif
    endif
    if l:noPreviousSibling
        echo 'no previous sibling header'
    endif
endfunction

function! s:Toc(...)
    if a:0 > 0
        let l:window_type = a:1
    else
        let l:window_type = 'vertical'
    endif


    let l:cursor_line = line('.')
    let l:cursor_header = 0
    let l:header_list = s:GetHeaderList()
    let l:indented_header_list = []
    if len(l:header_list) == 0
        echom 'Toc: No headers.'
        return
    endif
    let l:header_max_len = 0
    let l:vim_markdown_toc_autofit = get(g:, 'vim_markdown_toc_autofit', 0)
    for h in l:header_list
        " set header number of the cursor position
        if l:cursor_header == 0
            let l:header_line = h.lnum
            if l:header_line == l:cursor_line
                let l:cursor_header = index(l:header_list, h) + 1
            elseif l:header_line > l:cursor_line
                let l:cursor_header = index(l:header_list, h)
            endif
        endif
        " indent header based on level
        let l:text = repeat('  ', h.level-1) . h.text
        " keep track of the longest header size (heading level + title)
        let l:total_len = strdisplaywidth(l:text)
        if l:total_len > l:header_max_len
            let l:header_max_len = l:total_len
        endif
        " append indented line to list
        let l:item = {'lnum': h.lnum, 'text': l:text, 'valid': 1, 'bufnr': h.bufnr, 'col': 1}
        let l:indented_header_list = l:indented_header_list + [l:item]
    endfor
    call setloclist(0, l:indented_header_list)

    if l:window_type ==# 'horizontal'
        lopen
    elseif l:window_type ==# 'vertical'
        vertical lopen
        " auto-fit toc window when possible to shrink it
        if (&columns/2) > l:header_max_len && l:vim_markdown_toc_autofit == 1
            " header_max_len + 1 space for first header + 3 spaces for line numbers
            execute 'vertical resize ' . (l:header_max_len + 1 + 3)
        else
            execute 'vertical resize ' . (&columns/2)
        endif
    elseif l:window_type ==# 'tab'
        tab lopen
    else
        lopen
    endif
    setlocal modifiable
    for i in range(1, line('$'))
        " this is the location-list data for the current item
        let d = getloclist(0)[i-1]
        call setline(i, d.text)
    endfor
    setlocal nomodified
    setlocal nomodifiable
    execute 'normal! ' . l:cursor_header . 'G'
endfunction

function! s:InsertToc(format, ...)
    if a:0 > 0
        if type(a:1) != type(0)
            echohl WarningMsg
            echomsg '[vim-markdown] Invalid argument, must be an integer >= 2.'
            echohl None
            return
        endif
        let l:max_level = a:1
        if l:max_level < 2
            echohl WarningMsg
            echomsg '[vim-markdown] Maximum level cannot be smaller than 2.'
            echohl None
            return
        endif
    else
        let l:max_level = 0
    endif

    let l:toc = []
    let l:header_list = s:GetHeaderList()
    if len(l:header_list) == 0
        echom 'InsertToc: No headers.'
        return
    endif

    if a:format ==# 'numbers'
        let l:h2_count = 0
        for header in l:header_list
            if header.level == 2
                let l:h2_count += 1
            endif
        endfor
        let l:max_h2_number_len = strlen(string(l:h2_count))
    else
        let l:max_h2_number_len = 0
    endif

    let l:h2_count = 0
    for header in l:header_list
        let l:level = header.level
        if l:level == 1
            " skip level-1 headers
            continue
        elseif l:max_level != 0 && l:level > l:max_level
            " skip unwanted levels
            continue
        elseif l:level == 2
            " list of level-2 headers can be bullets or numbers
            if a:format ==# 'bullets'
                let l:indent = ''
                let l:marker = '* '
            else
                let l:h2_count += 1
                let l:number_len = strlen(string(l:h2_count))
                let l:indent = repeat(' ', l:max_h2_number_len - l:number_len)
                let l:marker = l:h2_count . '. '
            endif
        else
            let l:indent = repeat(' ', l:max_h2_number_len + 2 * (l:level - 2))
            let l:marker = '* '
        endif
        let l:text = '[' . header.text . ']'
        let l:link = '(#' . substitute(tolower(header.text), '\v[ ]+', '-', 'g') . ')'
        let l:line = l:indent . l:marker . l:text . l:link
        let l:toc = l:toc + [l:line]
    endfor

    call append(line('.'), l:toc)
endfunction

" Convert Setex headers in range `line1 .. line2` to Atx.
"
" Return the number of conversions.
"
function! s:SetexToAtx(line1, line2)
    let l:originalNumLines = line('$')
    execute 'silent! ' . a:line1 . ',' . a:line2 . 'substitute/\v(.*\S.*)\n\=+$/# \1/'

    let l:changed = l:originalNumLines - line('$')
    execute 'silent! ' . a:line1 . ',' . (a:line2 - l:changed) . 'substitute/\v(.*\S.*)\n-+$/## \1'
    return l:originalNumLines - line('$')
endfunction

" If `a:1` is 0, decrease the level of all headers in range `line1 .. line2`.
"
" Otherwise, increase the level. `a:1` defaults to `0`.
"
function! s:HeaderDecrease(line1, line2, ...)
    if a:0 > 0
        let l:increase = a:1
    else
        let l:increase = 0
    endif
    if l:increase
        let l:forbiddenLevel = 6
        let l:replaceLevels = [5, 1]
        let l:levelDelta = 1
    else
        let l:forbiddenLevel = 1
        let l:replaceLevels = [2, 6]
        let l:levelDelta = -1
    endif
    for l:line in range(a:line1, a:line2)
        if join(getline(l:line, l:line + 1), "\n") =~ s:levelRegexpDict[l:forbiddenLevel]
            echomsg 'There is an h' . l:forbiddenLevel . ' at line ' . l:line . '. Aborting.'
            return
        endif
    endfor
    let l:numSubstitutions = s:SetexToAtx(a:line1, a:line2)
    let l:flags = (&gdefault ? '' : 'g')
    for l:level in range(replaceLevels[0], replaceLevels[1], -l:levelDelta)
        execute 'silent! ' . a:line1 . ',' . (a:line2 - l:numSubstitutions) . 'substitute/' . s:levelRegexpDict[l:level] . '/' . repeat('#', l:level + l:levelDelta) . '/' . l:flags
    endfor
endfunction

" Format table under cursor.
"
" Depends on Tabularize.
"
function! s:TableFormat()
    let l:pos = getpos('.')

    if get(g:, 'vim_markdown_borderless_table', 0)
      " add `|` to the beginning of the line if it isn't present
      normal! {
      call search('|')
      execute 'silent .,''}s/\v^(\s{0,})\|?([^\|])/\1|\2/e'

      " add `|` to the end of the line if it isn't present
      normal! {
      call search('|')
      execute 'silent .,''}s/\v([^\|])\|?(\s{0,})$/\1|\2/e'
    endif

    normal! {
    " Search instead of `normal! j` because of the table at beginning of file edge case.
    call search('|')
    normal! j
    " Remove everything that is not a pipe, colon or hyphen next to a colon othewise
    " well formated tables would grow because of addition of 2 spaces on the separator
    " line by Tabularize /|.
    let l:flags = (&gdefault ? '' : 'g')
    execute 's/\(:\@<!-:\@!\|[^|:-]\)//e' . l:flags
    execute 's/--/-/e' . l:flags
    Tabularize /\(\\\)\@<!|
    " Move colons for alignment to left or right side of the cell.
    execute 's/:\( \+\)|/\1:|/e' . l:flags
    execute 's/|\( \+\):/|:\1/e' . l:flags
    execute 's/|:\?\zs[ -]\+\ze:\?|/\=repeat("-", len(submatch(0)))/' . l:flags
    call setpos('.', l:pos)
endfunction

" Wrapper to do move commands in visual mode.
"
function! s:VisMove(f)
    norm! gv
    call function(a:f)()
endfunction

" Map in both normal and visual modes.
"
function! s:MapNormVis(rhs,lhs)
    execute 'nn <buffer><silent> ' . a:rhs . ' :call ' . a:lhs . '()<cr>'
    execute 'vn <buffer><silent> ' . a:rhs . ' <esc>:call <sid>VisMove(''' . a:lhs . ''')<cr>'
endfunction

" Parameters:
"
" - step +1 for right, -1 for left
"
" TODO: multiple lines.
"
function! s:FindCornerOfSyntax(lnum, col, step)
    let l:col = a:col
    let l:syn = synIDattr(synID(a:lnum, l:col, 1), 'name')
    while synIDattr(synID(a:lnum, l:col, 1), 'name') ==# l:syn
        let l:col += a:step
    endwhile
    return l:col - a:step
endfunction

" Return the next position of the given syntax name,
" inclusive on the given position.
"
" TODO: multiple lines
"
function! s:FindNextSyntax(lnum, col, name)
    let l:col = a:col
    let l:step = 1
    while synIDattr(synID(a:lnum, l:col, 1), 'name') !=# a:name
        let l:col += l:step
    endwhile
    return [a:lnum, l:col]
endfunction

function! s:FindCornersOfSyntax(lnum, col)
    return [<sid>FindLeftOfSyntax(a:lnum, a:col), <sid>FindRightOfSyntax(a:lnum, a:col)]
endfunction

function! s:FindRightOfSyntax(lnum, col)
    return <sid>FindCornerOfSyntax(a:lnum, a:col, 1)
endfunction

function! s:FindLeftOfSyntax(lnum, col)
    return <sid>FindCornerOfSyntax(a:lnum, a:col, -1)
endfunction

" Returns:
"
" - a string with the the URL for the link under the cursor
" - an empty string if the cursor is not on a link
"
" TODO
"
" - multiline support
" - give an error if the separator does is not on a link
"
function! s:Markdown_GetUrlForPosition(lnum, col)
    let l:lnum = a:lnum
    let l:col = a:col
    let l:syn = synIDattr(synID(l:lnum, l:col, 1), 'name')

    if l:syn ==# 'mkdInlineURL' || l:syn ==# 'mkdURL' || l:syn ==# 'mkdLinkDefTarget'
        " Do nothing.
    elseif l:syn ==# 'mkdLink'
        let [l:lnum, l:col] = <sid>FindNextSyntax(l:lnum, l:col, 'mkdURL')
        let l:syn = 'mkdURL'
    elseif l:syn ==# 'mkdDelimiter'
        let l:line = getline(l:lnum)
        let l:char = l:line[col - 1]
        if l:char ==# '<'
            let l:col += 1
        elseif l:char ==# '>' || l:char ==# ')'
            let l:col -= 1
        elseif l:char ==# '[' || l:char ==# ']' || l:char ==# '('
            let [l:lnum, l:col] = <sid>FindNextSyntax(l:lnum, l:col, 'mkdURL')
        else
            return ''
        endif
    else
        return ''
    endif

    let [l:left, l:right] = <sid>FindCornersOfSyntax(l:lnum, l:col)
    return getline(l:lnum)[l:left - 1 : l:right - 1]
endfunction

" Front end for GetUrlForPosition.
"
function! s:OpenUrlUnderCursor()
    let l:url = s:Markdown_GetUrlForPosition(line('.'), col('.'))
    if l:url !=# ''
      if l:url =~? 'http[s]\?:\/\/[[:alnum:]%\/_#.-]*'
        "Do nothing
      else
        let l:url = expand(expand('%:h').'/'.l:url)
      endif
      call s:VersionAwareNetrwBrowseX(l:url)
    else
        echomsg 'The cursor is not on a link.'
    endif
endfunction

" We need a definition guard because we invoke 'edit' which will reload this
" script while this function is running. We must not replace it.
if !exists('*s:EditUrlUnderCursor')
    function s:EditUrlUnderCursor()
        let l:editmethod = ''
        " determine how to open the linked file (split, tab, etc)
        if exists('g:vim_markdown_edit_url_in')
          if g:vim_markdown_edit_url_in ==# 'tab'
            let l:editmethod = 'tabnew'
          elseif g:vim_markdown_edit_url_in ==# 'vsplit'
            let l:editmethod = 'vsp'
          elseif g:vim_markdown_edit_url_in ==# 'hsplit'
            let l:editmethod = 'sp'
          else
            let l:editmethod = 'edit'
          endif
        else
          " default to current buffer
          let l:editmethod = 'edit'
        endif
        let l:url = s:Markdown_GetUrlForPosition(line('.'), col('.'))
        if l:url !=# ''
            if get(g:, 'vim_markdown_autowrite', 0)
                write
            endif
            let l:anchor = ''
            if get(g:, 'vim_markdown_follow_anchor', 0)
                let l:parts = split(l:url, '#', 1)
                if len(l:parts) == 2
                    let [l:url, l:anchor] = parts
                    let l:anchorexpr = get(g:, 'vim_markdown_anchorexpr', '')
                    if l:anchorexpr !=# ''
                        let l:anchor = eval(substitute(
                            \ l:anchorexpr, 'v:anchor',
                            \ escape('"'.l:anchor.'"', '"'), ''))
                    endif
                endif
            endif
            if l:url !=# ''
                let l:ext = ''
                if get(g:, 'vim_markdown_no_extensions_in_markdown', 0)
                    " use another file extension if preferred
                    if exists('g:vim_markdown_auto_extension_ext')
                        let l:ext = '.'.g:vim_markdown_auto_extension_ext
                    else
                        let l:ext = '.md'
                    endif
                endif
                let l:url = fnameescape(fnamemodify(expand('%:h').'/'.l:url.l:ext, ':.'))
                execute l:editmethod l:url
            endif
            if l:anchor !=# ''
                call search(l:anchor, 's')
            endif
        else
            execute l:editmethod . ' <cfile>'
        endif
    endfunction
endif

function! s:VersionAwareNetrwBrowseX(url)
    if has('patch-7.4.567')
        call netrw#BrowseX(a:url, 0)
    else
        call netrw#NetrwBrowseX(a:url, 0)
    endif
endf

function! s:MapNotHasmapto(lhs, rhs)
    if !hasmapto('<Plug>' . a:rhs)
        execute 'nmap <buffer>' . a:lhs . ' <Plug>' . a:rhs
        execute 'vmap <buffer>' . a:lhs . ' <Plug>' . a:rhs
    endif
endfunction

call <sid>MapNormVis('<Plug>Markdown_MoveToNextHeader', '<sid>MoveToNextHeader')
call <sid>MapNormVis('<Plug>Markdown_MoveToPreviousHeader', '<sid>MoveToPreviousHeader')
call <sid>MapNormVis('<Plug>Markdown_MoveToNextSiblingHeader', '<sid>MoveToNextSiblingHeader')
call <sid>MapNormVis('<Plug>Markdown_MoveToPreviousSiblingHeader', '<sid>MoveToPreviousSiblingHeader')
call <sid>MapNormVis('<Plug>Markdown_MoveToParentHeader', '<sid>MoveToParentHeader')
call <sid>MapNormVis('<Plug>Markdown_MoveToCurHeader', '<sid>MoveToCurHeader')
nnoremap <Plug>Markdown_OpenUrlUnderCursor :call <sid>OpenUrlUnderCursor()<cr>
nnoremap <Plug>Markdown_EditUrlUnderCursor :call <sid>EditUrlUnderCursor()<cr>

if !get(g:, 'vim_markdown_no_default_key_mappings', 0)
    call <sid>MapNotHasmapto(']]', 'Markdown_MoveToNextHeader')
    call <sid>MapNotHasmapto('[[', 'Markdown_MoveToPreviousHeader')
    call <sid>MapNotHasmapto('][', 'Markdown_MoveToNextSiblingHeader')
    call <sid>MapNotHasmapto('[]', 'Markdown_MoveToPreviousSiblingHeader')
    call <sid>MapNotHasmapto(']u', 'Markdown_MoveToParentHeader')
    call <sid>MapNotHasmapto(']h', 'Markdown_MoveToCurHeader')
    call <sid>MapNotHasmapto('gx', 'Markdown_OpenUrlUnderCursor')
    call <sid>MapNotHasmapto('ge', 'Markdown_EditUrlUnderCursor')
endif

command! -buffer -range=% HeaderDecrease call s:HeaderDecrease(<line1>, <line2>)
command! -buffer -range=% HeaderIncrease call s:HeaderDecrease(<line1>, <line2>, 1)
command! -buffer -range=% SetexToAtx call s:SetexToAtx(<line1>, <line2>)
command! -buffer -range TableFormat call s:TableFormat()
command! -buffer Toc call s:Toc()
command! -buffer Toch call s:Toc('horizontal')
command! -buffer Tocv call s:Toc('vertical')
command! -buffer Toct call s:Toc('tab')
command! -buffer -nargs=? InsertToc call s:InsertToc('bullets', <args>)
command! -buffer -nargs=? InsertNToc call s:InsertToc('numbers', <args>)

" Heavily based on vim-notes - http://peterodding.com/code/vim/notes/
if exists('g:vim_markdown_fenced_languages')
    let s:filetype_dict = {}
    for s:filetype in g:vim_markdown_fenced_languages
        let key = matchstr(s:filetype, '[^=]*')
        let val = matchstr(s:filetype, '[^=]*$')
        let s:filetype_dict[key] = val
    endfor
else
    let s:filetype_dict = {
        \ 'c++': 'cpp',
        \ 'viml': 'vim',
        \ 'bash': 'sh',
        \ 'ini': 'dosini'
    \ }
endif

function! s:MarkdownHighlightSources(force)
    " Syntax highlight source code embedded in notes.
    " Look for code blocks in the current file
    let filetypes = {}
    for line in getline(1, '$')
        let ft = matchstr(line, '\(`\{3,}\|\~\{3,}\)\s*\zs[0-9A-Za-z_+-]*\ze.*')
        if !empty(ft) && ft !~# '^\d*$' | let filetypes[ft] = 1 | endif
    endfor
    if !exists('b:mkd_known_filetypes')
        let b:mkd_known_filetypes = {}
    endif
    if !exists('b:mkd_included_filetypes')
        " set syntax file name included
        let b:mkd_included_filetypes = {}
    endif
    if !a:force && (b:mkd_known_filetypes == filetypes || empty(filetypes))
        return
    endif

    " Now we're ready to actually highlight the code blocks.
    let startgroup = 'mkdCodeStart'
    let endgroup = 'mkdCodeEnd'
    for ft in keys(filetypes)
        if a:force || !has_key(b:mkd_known_filetypes, ft)
            if has_key(s:filetype_dict, ft)
                let filetype = s:filetype_dict[ft]
            else
                let filetype = ft
            endif
            let group = 'mkdSnippet' . toupper(substitute(filetype, '[+-]', '_', 'g'))
            if !has_key(b:mkd_included_filetypes, filetype)
                let include = s:SyntaxInclude(filetype)
                let b:mkd_included_filetypes[filetype] = 1
            else
                let include = '@' . toupper(filetype)
            endif
            let command_backtick = 'syntax region %s matchgroup=%s start="^\s*`\{3,}\s*%s.*$" matchgroup=%s end="\s*`\{3,}$" keepend contains=%s%s'
            let command_tilde    = 'syntax region %s matchgroup=%s start="^\s*\~\{3,}\s*%s.*$" matchgroup=%s end="\s*\~\{3,}$" keepend contains=%s%s'
            execute printf(command_backtick, group, startgroup, ft, endgroup, include, has('conceal') && get(g:, 'vim_markdown_conceal', 1) && get(g:, 'vim_markdown_conceal_code_blocks', 1) ? ' concealends' : '')
            execute printf(command_tilde,    group, startgroup, ft, endgroup, include, has('conceal') && get(g:, 'vim_markdown_conceal', 1) && get(g:, 'vim_markdown_conceal_code_blocks', 1) ? ' concealends' : '')
            execute printf('syntax cluster mkdNonListItem add=%s', group)

            let b:mkd_known_filetypes[ft] = 1
        endif
    endfor
endfunction

function! s:SyntaxInclude(filetype)
    " Include the syntax highlighting of another {filetype}.
    let grouplistname = '@' . toupper(a:filetype)
    " Unset the name of the current syntax while including the other syntax
    " because some syntax scripts do nothing when "b:current_syntax" is set
    if exists('b:current_syntax')
        let syntax_save = b:current_syntax
        unlet b:current_syntax
    endif
    try
        execute 'syntax include' grouplistname 'syntax/' . a:filetype . '.vim'
        execute 'syntax include' grouplistname 'after/syntax/' . a:filetype . '.vim'
    catch /E484/
        " Ignore missing scripts
    endtry
    " Restore the name of the current syntax
    if exists('syntax_save')
        let b:current_syntax = syntax_save
    elseif exists('b:current_syntax')
        unlet b:current_syntax
    endif
    return grouplistname
endfunction

function! s:IsHighlightSourcesEnabledForBuffer()
    " Enable for markdown buffers, and for liquid buffers with markdown format
    return &filetype =~# 'markdown' || get(b:, 'liquid_subtype', '') =~# 'markdown'
endfunction

function! s:MarkdownRefreshSyntax(force)
    " Use != to compare &syntax's value to use the same logic run on
    " $VIMRUNTIME/syntax/synload.vim.
    "
    " vint: next-line -ProhibitEqualTildeOperator
    if s:IsHighlightSourcesEnabledForBuffer() && line('$') > 1 && &syntax != 'OFF'
        call s:MarkdownHighlightSources(a:force)
    endif
endfunction

function! s:MarkdownClearSyntaxVariables()
    if s:IsHighlightSourcesEnabledForBuffer()
        unlet! b:mkd_included_filetypes
    endif
endfunction

augroup Mkd
    " These autocmd calling s:MarkdownRefreshSyntax need to be kept in sync with
    " the autocmds calling s:MarkdownSetupFolding in after/ftplugin/markdown.vim.
    " autocmd! * <buffer>
    " autocmd BufWinEnter <buffer> call s:MarkdownRefreshSyntax(1)
    " autocmd BufUnload <buffer> call s:MarkdownClearSyntaxVariables()
    " autocmd BufWritePost <buffer> call s:MarkdownRefreshSyntax(0)
    " autocmd InsertEnter,InsertLeave <buffer> call s:MarkdownRefreshSyntax(0)
    " autocmd CursorHold,CursorHoldI <buffer> call s:MarkdownRefreshSyntax(0)
augroup END
