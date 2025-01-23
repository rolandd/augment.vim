" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Handlers for autocommands and keybinds

" Check whether the server started. Errors to start should be reported in the
" Augment-log.
function! s:IsRunning() abort
    let client = augment#client#Client()
    return exists('client.client_id') || exists('client.job')
endfunction

let s:NOT_RUNNING_MSG = 'The Augment language server is not running. See ":Augment log" for more details.'

" Get the text of the current buffer, accounting for the newline at the end
function! s:GetBufText() abort
    return join(getline(1, '$'), "\n") . "\n"
endfunction

" Notify the server that a buffer has been opened
function! s:OpenBuffer() abort
    if !s:IsRunning()
        return
    endif

    let client = augment#client#Client()
    if has('nvim')
        call luaeval('require("augment").open_buffer(_A[1], _A[2])', [client.client_id, bufnr('%')])
    else
        let uri = 'file://' . expand('%:p')
        let text = s:GetBufText()
        call client.Notify('textDocument/didOpen', {
                    \ 'textDocument': {
                    \   'uri': uri,
                    \   'languageId': &filetype,
                    \   'version': b:changedtick,
                    \   'text': text,
                    \ },
                    \ })
    endif
endfunction

" Notify the server that a buffer has been updated
function! s:UpdateBuffer() abort
    if !s:IsRunning()
        return
    endif

    " The nvim lsp client does this automatically
    if !has('nvim')
        " Only send a change notification if the buffer has changed (as
        " tracked by b:changedtick)
        if exists('b:_augment_buf_tick') && b:_augment_buf_tick == b:changedtick
            return
        endif
        let b:_augment_buf_tick = b:changedtick

        let uri = 'file://' . expand('%:p')
        let text = s:GetBufText()
        call augment#client#Client().Notify('textDocument/didChange', {
                    \ 'textDocument': {
                    \   'uri': uri,
                    \   'version': b:changedtick,
                    \ },
                    \ 'contentChanges': [{'text': text}],
                    \ })
    endif
endfunction

" Request a completion from the server
function! s:RequestCompletion() abort
    if !s:IsRunning()
        return
    endif

    " Don't send a request if disabled
    if exists('g:augment_enabled') && !g:augment_enabled
        return
    endif

    " If there was a previous completion request with the same buffer version
    " (tracked by b:changedtick), don't send another
    if exists('b:_augment_comp_tick') && b:_augment_comp_tick == b:changedtick
        return
    endif
    let b:_augment_comp_tick = b:changedtick

    let uri = 'file://' . expand('%:p')
    let text = join(getline(1, '$'), "\n")
    " TODO: remove version-- we use it elsewhere but it's not in the spec
    call augment#client#Client().Request('textDocument/completion', {
                \ 'textDocument': {
                \   'uri': uri,
                \   'version': b:changedtick,
                \ },
                \ 'position': {
                \   'line': line('.') - 1,
                \   'character': col('.') - 1,
                \ },
                \ })
endfunction

" Show the log
function! s:CommandLog(...) abort
    call augment#log#Show()
endfunction

" Send sign-in request to the language server
function! s:CommandSignIn(...) abort
    if !s:IsRunning()
        echohl WarningMsg
        echo s:NOT_RUNNING_MSG
        echohl None
        return
    endif

    call augment#client#Client().Request('augment/login', {})
endfunction

" Send sign-out request to the language server
function! s:CommandSignOut(...) abort
    if !s:IsRunning()
        echohl WarningMsg
        echo s:NOT_RUNNING_MSG
        echohl None
        return
    endif

    call augment#client#Client().Request('augment/logout', {})
endfunction

function! s:CommandEnable(...) abort
    let g:augment_enabled = v:true
endfunction

function! s:CommandDisable(...) abort
    let g:augment_enabled = v:false
endfunction

function! s:CommandStatus(...) abort
    if !s:IsRunning()
        echohl WarningMsg
        echo s:NOT_RUNNING_MSG
        echohl None
        return
    endif

    call augment#client#Client().Request('augment/status', {})
endfunction

function! s:CommandChat(range, args) abort
    if exists('g:augment_enabled') && !g:augment_enabled
        echohl WarningMsg
        echo 'Augment: Not enabled. Run ":Augment enable" to enable the plugin.'
        echohl None
        return
    endif

    if !s:IsRunning()
        echohl WarningMsg
        echo s:NOT_RUNNING_MSG
        echohl None
        return
    endif

    " If range arguments were provided (when using :Augment chat) or in visual
    " mode, get the selected text
    if a:range == 2 || mode() ==# 'v' || mode() ==# 'V'
        let selected_text = augment#chat#GetSelectedText()
    else
        let selected_text = ''
    endif

    " Use the message from the additional command arguments if provided, or
    " prompt the user for a message
    let message = empty(a:args) ? input('Message: ') : a:args

    " Handle cancellation or empty input
    if message ==# '' || message =~# '^\s*$'
        redraw
        echo 'Chat cancelled'
        return
    endif

    " Create new buffer for chat response
    let chat_bufname = 'AugmentChat-' . strftime("%Y%m%d-%H%M%S")
    let current_win = bufwinid(bufnr('%'))
    call augment#chat#CreateBuffer(chat_bufname)
    call win_gotoid(current_win)

    call augment#log#Info(
                \ 'Making chat request in buffer ' . chat_bufname
                \ . ' with selected_text="' . selected_text
                \ . '"' . ' message="' . message . '"')

    let params = {
        \ 'textDocumentPosition': {
        \     'textDocument': {
        \         'uri': 'file://' . expand('%:p'),
        \     },
        \     'position': {
        \         'line': line('.') - 1,
        \         'character': col('.') - 1,
        \     },
        \ },
        \ 'message': message,
    \ 'partialResultToken': chat_bufname,
    \ }

    " Add selected text if available
    if !empty(selected_text)
        let params['selectedText'] = selected_text
    endif

    call augment#client#Client().Request('augment/chat', params)
endfunction

" Handle user commands
let s:command_handlers = {
    \ 'log': function('s:CommandLog'),
    \ 'signin': function('s:CommandSignIn'),
    \ 'signout': function('s:CommandSignOut'),
    \ 'enable': function('s:CommandEnable'),
    \ 'disable': function('s:CommandDisable'),
    \ 'status': function('s:CommandStatus'),
    \ 'chat': function('s:CommandChat'),
    \ }

function! augment#Command(range, args) abort range
    if empty(a:args)
        call s:command_handlers['status']()
        return
    endif

    let command = split(a:args)[0]
    for [name, Handler] in items(s:command_handlers)
        " Note that ==? is case-insensitive comparison
        if command ==? name
            " Call the command handler with the count of range arguments as
            " the first parameter, followed by the rest of the arguments to
            " the command as a single string
            let command_args = substitute(a:args, '^\S*\s*', '', '')
            call Handler(a:range, command_args)
            return
        endif
    endfor

    echohl WarningMsg
    echo 'Augment: Unknown command: "' . command . '"'
    echohl None
endfunction

function! augment#CommandComplete(ArgLead, CmdLine, CursorPos) abort
    return keys(s:command_handlers)->join("\n")
endfunction

" Autocommand handlers
function! augment#OnVimEnter() abort
    call augment#client#Client()
endfunction

function! augment#OnBufEnter() abort
    call s:OpenBuffer()
endfunction

function! augment#OnTextChanged() abort
    call s:UpdateBuffer()
endfunction

function! augment#OnTextChangedI() abort
    " Since CursorMovedI is always called before TextChangedI, the suggestion will already be cleared
    call s:UpdateBuffer()
    call s:RequestCompletion()
endfunction

function! augment#OnCursorMovedI() abort
    call augment#suggestion#Clear()
endfunction

function! augment#OnInsertEnter() abort
    call s:UpdateBuffer()
    call s:RequestCompletion()
endfunction

function! augment#OnInsertLeavePre() abort
    call augment#suggestion#Clear()
endfunction

" Accept the currently active suggestion if one is available, otherwise insert
" the fallback text provided as the first argument
function! augment#Accept(...) abort
    " If no fallback was provided, don't add any text
    let fallback = a:0 >= 1 ? a:1 : ''

    if !augment#suggestion#Accept()
        call feedkeys(fallback, 'nt')
    endif
endfunction
