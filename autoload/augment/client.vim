" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Client for interacting with the server process

let s:client = {}

" If provided, launch the server from a user-provided command
if exists('g:augment_job_command')
    let s:job_command = g:augment_job_command
else
    let server_file = expand('<sfile>:h:h:h') . '/dist/server.js'
    let s:job_command = ['node', server_file, '--stdio']
endif

function! s:VimNotify(method, params) dict abort
    let message = {
                \ 'jsonrpc': '2.0',
                \ 'method': a:method,
                \ 'params': a:params,
                \ }

    call ch_sendexpr(self.job, message)
endfunction

function! s:VimRequest(method, params) dict abort
    let self.request_id += 1
    let message = {
                \ 'jsonrpc': '2.0',
                \ 'id': self.request_id,
                \ 'method': a:method,
                \ 'params': a:params,
                \ }

    call ch_sendexpr(self.job, message)
    let self.requests[self.request_id] = [a:method, a:params]
endfunction

function! s:NvimNotify(method, params) dict abort
    call luaeval('require("augment").notify(_A[1], _A[2], _A[3])', [self.client_id, a:method, a:params])
endfunction

function! s:NvimRequest(method, params) dict abort
    " Passing an empty dictionary results in a malformed table in lua
    let params = empty(a:params) ? [] : a:params
    call luaeval('require("augment").request(_A[1], _A[2], _A[3])', [self.client_id, a:method, params])
    " For nvim tracking the request methods and params is handled in the lua code
endfunction

" Handle a chat chunk notification
function! s:HandleChatChunk(client, params) abort
    let text = a:params.value.text
    let chat_buf = bufnr(a:params.token)
    if chat_buf == -1
        call augment#log#Error('Could not find chat buffer ' . a:params.token)
        return
    endif

    let lines = split(text, "\n", v:true)
    let last_line = getbufline(chat_buf, '$')[0]
    silent! call setbufline(chat_buf, '$', last_line . lines[0])
    silent! call appendbufline(chat_buf, '$', lines[1:])
endfunction

" Handle the initialize response
function! s:HandleInitialize(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('initialize response error: ' . string(a:err))
        return
    endif

    call a:client.Notify('initialized', {})
endfunction

" Handle the textDocument/completion response
function! s:HandleCompletion(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('Recieved error ' . string(a:err) . ' for completion with params: ' . string(a:params))
        return
    endif

    let req_changedtick = a:params.textDocument.version
    let req_line = a:params.position.line + 1
    let req_col = a:params.position.character + 1

    " If the buffer has changed or cursor has moved since the request was made, ignore the response
    if line('.') != req_line || col('.') != req_col || b:changedtick != req_changedtick
        return
    endif

    " If response has no completions, ignore the response
    if len(a:result) == 0
        return
    endif

    " Show the completion
    let text = a:result[0].insertText
    let request_id = a:result[0].label
    call augment#suggestion#Show(text, request_id, req_line, req_col, req_changedtick)

    call augment#log#Info('Received completion with request_id=' . request_id . ' text=' . text)

    " Trigger the CompletionUpdated autocommand (used for testing)
    silent doautocmd User CompletionUpdated
endfunction

" Handle the augment/login response
function! s:HandleLogin(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('augment/login response error: ' . string(a:err))
        return
    endif

    if a:result.loggedIn
        echom 'Augment: Already logged in.'
        return
    endif

    let url = a:result.url
    let prompt = printf("Please complete authentication in your browser...\n%s\n\nAfter authenticating, you will receive a code.\nPaste the code in the prompt below.", url)
    let code = inputsecret(prompt . "\n\nEnter the authentication code: ")
    call a:client.Request('augment/token', {'code': code})
endfunction

" Handle the augment/token response
function! s:HandleToken(client, params, result, err) abort
    if a:err isnot v:null
        echohl ErrorMsg
        echom 'Augment: Error signing in, please try again.'
        echohl None
        call augment#log#Error('augment/token response error: ' . string(a:err))
        return
    endif

    echom 'Augment: Sign in successful.'
endfunction

" Handle the augment/logout response
function! s:HandleLogout(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('augment/logout response error: ' . string(a:err))
        return
    endif

    echom 'Augment: Sign out successful.'
endfunction

" Handle the augment/status response
function! s:HandleStatus(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('augment/status response error: ' . string(a:err))
        return
    endif

    let loggedIn = a:result.loggedIn
    let enabled = exists('g:augment_enabled') ? g:augment_enabled : v:true
    if has_key(a:result, 'syncPercentage')
        let syncPercentage = a:result.syncPercentage == 100 ? 'fully' : printf('%d%%', a:result.syncPercentage)
        let syncText = printf(' (workspace %s synced)', syncPercentage)
    else
        let syncText = ''
    endif

    if !loggedIn
        echom 'Augment: Not signed in. Run ":Augment signin" to start the sign in flow or ":h augment" for more information on the plugin.'
    elseif !enabled
        echom printf('Augment%s: Signed in, disabled.', syncText)
    else
        echom printf('Augment%s: Signed in, enabled.', syncText)
    endif
endfunction

" Handle the augment/chat response
function! s:HandleChat(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('augment/chat response error: ' . string(a:err))
        return
    endif

    call augment#log#Info('Received chat response with request_id=' . a:result.label . ' buffer=' . a:params.partialResultToken)

    " Update contents of chat buffer
    let text = a:result.text
    if !empty(text)
        let chat_buf = bufnr(a:params.partialResultToken)
        if chat_buf == -1
            call augment#log#Error('Could not find chat buffer ' . a:params.partialResultToken)
            return
        endif
        silent! call setbufline(chat_buf, 1, split(text, '\n'))
    endif

    " Trigger the ChatResponse autocommand (used for testing)
    silent doautocmd User ChatResponse
endfunction

" Handle the augment/pluginVerion response
function! s:HandlePluginVersion(client, params, result, err) abort
    if a:err isnot v:null
        call augment#log#Error('augment/pluginVersion response error: ' . string(a:err))
        return
    endif

    " Check version against current, displaying a warning message if outdated
    let latest_version = a:result.version
    let current_version = 'v' . augment#version#Version()
    if latest_version !=# current_version
        let warning_message = join([
                    \ 'Your plugin version ',
                    \ current_version,
                    \ ' is lower than the latest version ',
                    \ latest_version,
                    \ '. Please update your plugin to receive the latest features and bug fixes.'
                    \ ], '')
        call augment#log#Warn(warning_message)

        " If the user has suppressed the version warning, don't show it
        if exists('g:augment_suppress_version_warning') && g:augment_suppress_version_warning
            return
        endif

        echohl WarningMsg
        echom 'Augment: ' . warning_message
        echohl None
    endif
endfunction

" Process a message from the server
function! s:OnMessage(client, channel, message) abort
    if has_key(a:message, 'id')
        " Process a response
        if !has_key(a:client.requests, a:message.id)
            call augment#log#Warn('Received response for unknown request: ' . string(a:message))
            return
        endif

        let [method, params] = remove(a:client.requests, a:message.id)

        if !has_key(a:client.response_handlers, method)
            call augment#log#Warn('Unprocessed server response: ' . string(a:message))
        else
            let result = get(a:message, 'result', v:null)
            let err = get(a:message, 'error', v:null)
            call a:client.response_handlers[method](a:client, params, result, err)
        endif
    else
        " Process a notification
        let method = a:message.method
        if !has_key(a:client.notification_handlers, method)
            call augment#log#Warn('Unprocessed server notification: ' . string(a:message))
        else
            call a:client.notification_handlers[method](a:client, a:message.params)
        endif
    endif
endfunction

" Handle a server notification in nvim (called from lua)
function! augment#client#NvimNotification(method, params) abort
    let client = augment#client#Client()
    if !has_key(client.notification_handlers, a:method)
        call augment#log#Warn('Unprocessed server notification: ' . string(a:method) . ': ' . string(a:params))
    else
        call client.notification_handlers[a:method](client, a:params)
    endif
endfunction

" Handle a server response in nvim (called from lua)
function! augment#client#NvimResponse(method, params, result, err) abort
    let client = augment#client#Client()
    if !has_key(client.response_handlers, a:method)
        call augment#log#Warn('Unprocessed server response to ' . string(a:method) . ': ' . string(a:result))
    else
        call client.response_handlers[a:method](client, a:params, a:result, a:err)
    endif
endfunction

" Handle a server error
function! s:OnError(client, channel, message) abort
    call augment#log#Error('Received error message from server: ' . string(a:message))
endfunction

" Handle the server exiting
function! s:OnExit(client, channel, message) abort
    if has_key(s:client, "job")
        call remove(s:client, "job")
        call augment#log#Error('Augment exited: ' . string(a:message))
    else
        call augment#log#Erorr('Augment (untracked) exited:' . string(a:message))
    endif
endfunction

function! s:GetWorkspaceFolders() abort
    " Convert any workspace folder paths to URIs for the language server
    if !exists('g:augment_workspace_folders')
        return []
    endif

    let valid_folders = []
    for folder in g:augment_workspace_folders
        let abs_path = fnamemodify(folder, ':p')
        if !isdirectory(abs_path)
            call augment#log#Error('The following workspace folder does not exist: ' . abs_path)
        else
            call add(valid_folders, folder)
        endif
    endfor

    let workspace_folders = map(copy(valid_folders), {_, folder ->
                \ {'uri': 'file://' . fnamemodify(folder, ':p'),
                \  'name': fnamemodify(folder, ':t')}})

    " Log the workspace folders
    call augment#log#Info('Using workspace folders: ' . string(workspace_folders))
    return workspace_folders
endfunction

" Run a new server and create a new client object
function! s:New() abort
    call augment#log#Info('Starting augment server')

    " Set the message handlers
    let notification_handlers = {
                \ 'augment/chatChunk': function('s:HandleChatChunk'),
                \ }
    let response_handlers = {
                \ 'initialize': function('s:HandleInitialize'),
                \ 'textDocument/completion': function('s:HandleCompletion'),
                \ 'augment/login': function('s:HandleLogin'),
                \ 'augment/token': function('s:HandleToken'),
                \ 'augment/logout': function('s:HandleLogout'),
                \ 'augment/status': function('s:HandleStatus'),
                \ 'augment/chat': function('s:HandleChat'),
                \ 'augment/pluginVersion': function('s:HandlePluginVersion'),
                \ }

    " Create the client object
    let client = {
                \ 'notification_handlers': notification_handlers,
                \ 'response_handlers': response_handlers,
                \ }


    " Check that the runtime environment is installed. If not, return a partially initialized client
    if executable(s:job_command[0]) == 0
        call augment#log#Error('The Augment runtime (' . s:job_command[0] . ') was not found.')
        return client
    endif

    " Convert any workspace folders to URIs for the language server
    let workspace_folders = s:GetWorkspaceFolders()

    " Start the server and send the initialize request
    if has('nvim')
        " Nvim-specific client setup
        call extend(client, {
                    \ 'Notify': function('s:NvimNotify'),
                    \ 'Request': function('s:NvimRequest'),
                    \ })

        " The nvim lsp client setup requires a list of notification methods to set up its handlers
        let notification_methods = keys(notification_handlers)

        " If the client exits, lua will notify NvimOnExit()
        let client.client_id = luaeval('require("augment").start_client(_A[1], _A[2], _A[3])',
                    \ [s:job_command, notification_methods, workspace_folders])
    else
        " Vim-specific client setup
        call extend(client, {
                    \ 'request_id': 0,
                    \ 'requests': {},
                    \ 'Notify': function('s:VimNotify'),
                    \ 'Request': function('s:VimRequest'),
                    \ })

        let client.job = job_start(s:job_command, {
                    \ 'noblock': 1,
                    \ 'stoponexit': 'term',
                    \ 'in_mode': 'lsp',
                    \ 'out_mode': 'lsp',
                    \ 'out_cb': function('s:OnMessage', [client]),
                    \ 'err_cb': function('s:OnError', [client]),
                    \ 'exit_cb': function('s:OnExit', [client]),
                    \ })

        let vim_version = printf('%d.%d.%d', v:version / 100, v:version % 100, v:versionlong % 1000)
        let plugin_version = augment#version#Version()
        let initialization_options = {
                    \ 'editor': 'vim',
                    \ 'vimVersion': vim_version,
                    \ 'pluginVersion': plugin_version,
                    \ }

        call client.Request('initialize', {
                    \ 'processId': getpid(),
                    \ 'capabilities': {},
                    \ 'initializationOptions': initialization_options,
                    \ 'workspaceFolders': workspace_folders,
                    \ })
    endif

    " Request the plugin version from the server
    call client.Request('augment/pluginVersion', {})

    return client
endfunction

" OnExit notification function for nvim plugin.
function! augment#client#NvimOnExit(code, signal, client_id) abort
    let msg = printf("code: %d, signal %d", a:code, a:signal)
    if has_key(s:client, "client_id")
        call remove(s:client, "client_id")
        call augment#log#Error('Augment exited: ' . msg)
    else
        call augment#log#Erorr('Augment (untracked) exited:' . msg)
    endif
endfunction

" Return the client, creating a new one if needed
function! augment#client#Client() abort
    if empty(s:client)
        let s:client = s:New()
    endif
    return s:client
endfunction
