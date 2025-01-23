" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Utilities for chat

function! s:GetBufSelection(line_start, col_start, line_end, col_end) abort
    if a:line_start == a:line_end
        return getline(a:line_start)[a:col_start - 1:a:col_end - 1]
    endif

    let lines = []
    call add(lines, getline(a:line_start)[a:col_start - 1:])
    call extend(lines, getline(a:line_start + 1, a:line_end - 1))
    call add(lines, getline(a:line_end)[0:a:col_end - 1])
    return join(lines, "\n")
endfunction

function! augment#chat#GetSelectedText() abort
    " If in visual mode use the current selection
    if mode() ==# 'v' || mode() ==# 'V'
        let [line_one, col_one] = getpos('.')[1:2]
        let [line_two, col_two] = getpos('v')[1:2]

        " . may be before or after v, so need to do some sorting
        if line_one < line_two
            let line_start = line_one
            let col_start = col_one
            let line_end = line_two
            let col_end = col_two
        elseif line_one > line_two
            let line_start = line_two
            let col_start = col_two
            let line_end = line_one
            let col_end = col_one
        else
            " If the lines are the same, the columns may be different
            let line_start = line_one
            let line_end = line_two
            if col_one <= col_two
                let col_start = col_one
                let col_end = col_two
            else
                let col_start = col_two
                let col_end = col_one
            endif
        endif

        " . and v return column positions one lower than '< and '>
        let col_start += 1
        let col_end += 1

        " In visual line mode, the columns will be incorrect
        if mode() ==# 'V'
            let col_start = 1
            let col_end = v:maxcol
        endif

        return s:GetBufSelection(line_start, col_start, line_end, col_end)
    endif

    " Otherwise, assume '< and '> are populated with the correct selection
    let [line_start, col_start] = getpos("'<")[1:2]
    let [line_end, col_end] = getpos("'>")[1:2]
    return s:GetBufSelection(line_start, col_start, line_end, col_end)
endfunction

function! augment#chat#CreateBuffer(bufname) abort
    botright vnew
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal wrap
    setlocal linebreak
    execute 'file ' . a:bufname
    setlocal readonly
    setlocal filetype=markdown
endfunction
