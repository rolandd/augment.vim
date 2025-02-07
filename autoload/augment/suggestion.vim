" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Functions for interacting with augment suggestions

" Clear the suggestion
function! augment#suggestion#Clear(...) abort
    if has('nvim')
        let ns_id = nvim_create_namespace('AugmentSuggestion')
        call nvim_buf_clear_namespace(0, ns_id, 0, -1)
    else
        call prop_remove({'type': 'AugmentSuggestion', 'all': v:true})
    endif

    let current = exists('b:_augment_suggestion') ? b:_augment_suggestion : {}
    let b:_augment_suggestion = {}

    " Send the reject resolution, checking optional argument to skip
    let skip_resolution = a:0 > 0 ? a:1 : v:false
    if !empty(current) && !skip_resolution
        call augment#client#Client().Notify('augment/resolveCompletion', {
                    \ 'requestId': current.request_id,
                    \ 'accept': v:false,
                    \ })
        call augment#log#Debug('Rejected completion with request_id=' . current.request_id . ' text=' . string(current.lines))
    endif

    return current
endfunction

" Show a suggestion
function! augment#suggestion#Show(text, request_id, req_line, req_col, req_changedtick) abort
    if len(a:text) == 0
        return
    endif

    call augment#suggestion#Clear()

    " Save the suggestion information in a buffer-local variable
    let b:_augment_suggestion = {
                \ 'lines': split(a:text, "\n", 1),
                \ 'request_id': a:request_id,
                \ 'req_line': a:req_line,
                \ 'req_col': a:req_col,
                \ 'req_changedtick': a:req_changedtick,
                \ }

    " Text properties don't render tabs, so manually add the correct spacing
    let tab_spaces = repeat(' ', &tabstop)
    let lines = a:text->substitute("\t", tab_spaces, 'g')->split("\n", 1)

    " Show the suggestion in ghost text
    if has('nvim')
        let ns_id = nvim_create_namespace('AugmentSuggestion')

        let virt_text = [[lines[0], 'AugmentSuggestionHighlight']]
        let virt_lines = mapnew(lines[1:], {_, val -> [[val, 'AugmentSuggestionHighlight']]})
        let opts = {
                    \ 'virt_text_pos': 'inline',
                    \ 'virt_text': virt_text,
                    \ 'virt_lines': virt_lines,
                    \ }

        call nvim_buf_set_extmark(0, ns_id, line('.') - 1, col('.') - 1, opts)
    else
        call prop_add(line('.'), col('.'), {
                    \ 'type': 'AugmentSuggestion',
                    \ 'text': lines[0],
                    \ })

        for line in lines[1:]
            " Since vim won't display a text prop line that's empty, add a space
            let line_text = line != '' ? line : ' '
            call prop_add(line('.'), 0, {
                        \ 'type': 'AugmentSuggestion',
                        \ 'text_align': 'below',
                        \ 'text': line_text,
                        \ })
        endfor
    endif
endfunction

" Accept the currently active suggestion if one is available, returning true
" if there was a suggestion to accept and false otherwise
function! augment#suggestion#Accept() abort
    let info = augment#suggestion#Clear(v:true)
    if !has_key(info, 'lines')
        return v:false
    endif
    let lines = info.lines

    " Check buffer state is as expected
    if line('.') != info.req_line || col('.') != info.req_col || b:changedtick != info.req_changedtick
        let buf_state = '{line=' . line('.') . ', col=' . col('.') . ', changedtick=' . b:changedtick . '}'
        let buf_expected = '{line=' . info.req_line . ', col=' . info.req_col . ', changedtick=' . info.req_changedtick . '}'
        call augment#log#Warn(
                    \ 'Attempted to accept completion "' . string(lines)
                    \ . '" with buffer state ' . buf_state
                    \ . ' and expected ' . buf_expected
                    \ )
        return v:false
    endif

    if empty(lines)
        return v:false
    endif

    " Add the first line of the suggestion
    let before = strpart(getline(line('.')), 0, col('.') - 1)
    let after = strpart(getline(line('.')), col('.') - 1)
    call setline(line('.'), before . lines[0] . after)

    " Add the rest of the suggestion
    for i in range(len(lines) - 1, 1, -1)
        call append(line('.'), lines[i])
    endfor

    " Put the cursor at the end of the accepted text
    if len(lines) == 1
        call cursor(line('.'), col('.') + len(lines[0]))
    else
        call cursor(line('.') + len(lines) - 1, len(lines[-1]) + 1)
    endif

    " Send the accept resolution
    call augment#client#Client().Notify('augment/resolveCompletion', {
                \ 'requestId': info.request_id,
                \ 'accept': v:true,
                \ })
    call augment#log#Debug('Accepted completion with request_id=' . info.request_id . ' text=' . string(lines))

    return v:true
endfunction
