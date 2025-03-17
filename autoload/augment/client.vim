" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Client for interacting with the server process

" Custom LSP response error codes
let s:AUGMENT_ERROR_UNAUTHORIZED = 401

let s:client = {}

function! augment#client#GetJobCommand() abort
    " If provided, launch the server from a user-provided command
    if exists('g:augment_job_command')
        return g:augment_job_command
    endif

    let server_file = expand('<script>:h:h:h') . '/dist/server.js'

    " If provided, use a user-provided node command
    if exists('g:augment_node_command')
        let s:node_command = g:augment_node_command
    else
        let s:node_command = 'node'
    endif
    return [s:node_command, server_file, '--stdio']
endfunction

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

" Handle the augment/chatChunk notification
function! s:HandleChatChunk(client, params) abort
    let text = a:params.text
    call augment#chat#AppendText(text)
endfunction

" Handle the window/logMessage notification
function! s:HandleLogMessage(client, params) abort
    if a:params.type == 1  " Error
        call augment#log#Error(a:params.message)
    elseif a:params.type == 2  " Warning
        call augment#log#Warn(a:params.message)
    elseif a:params.type == 3 || a:params.type == 4  " Info, Log
        call augment#log#Info(a:params.message)
    elseif a:params.type == 5  " Debug
        call augment#log#Debug(a:params.message)
    else
        call augment#log#Warn('Unknown log message type: ' . string(a:params.type) . '. Message: ' . string(a:params.message))
    endif
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
        " If the user is not logged in, ignore the error
        if a:err.code == s:AUGMENT_ERROR_UNAUTHORIZED
            return
        endif

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

    " If the user has exited insert mode, ignore the response
    if mode() !=# 'i'
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
        echom 'Augment: Error signing in: ' . a:err.message
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
    let disabled = exists('g:augment_disable_completions') && g:augment_disable_completions
    if has_key(a:result, 'syncPercentage')
        let syncPercentage = a:result.syncPercentage == 100 ? 'fully' : printf('%d%%', a:result.syncPercentage)
        let syncText = printf(' (workspace %s synced)', syncPercentage)
    else
        let syncText = ''
    endif

    if !loggedIn
        echom 'Augment: Not signed in. Run ":Augment signin" to start the sign in flow or ":h augment" for more information on the plugin.'
    elseif disabled
        echom printf('Augment%s: Signed in, completions disabled.', syncText)
    else
        echom printf('Augment%s: Signed in.', syncText)
    endif
endfunction

" Handle the augment/chat response
function! s:HandleChat(client, params, result, err) abort
    if a:err isnot v:null
        " NOTE(mpauly): For chat we want to show the error to the user even if
        " they're not logged in. This helps disambiguate between a
        " network/slow response error and an authentication error.

        call augment#log#Error('augment/chat response error: ' . string(a:err))
        return
    endif

    call augment#log#Info('Received chat response with request_id=' . a:result.requestId)

    " Add an extra newline so that the messages are spaced properly
    call augment#chat#AppendText("\n\n")
    call augment#chat#AppendHistory(a:params.message, a:result.text, a:result.requestId)

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
    let current_version = augment#version#Version()
    if latest_version !=# current_version
        let is_prerelease = a:result.isPrerelease
        let warning_message = printf('Your plugin version v%s is lower than the latest %s version v%s. Please update your plugin to receive the latest features and bug fixes.',
                    \ current_version,
                    \ is_prerelease ? 'prerelease' : 'stable',
                    \ latest_version)
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

    " Validate the the workspace folders are a list
    if type(g:augment_workspace_folders) == v:t_list
        let folders_list = g:augment_workspace_folders
    elseif type(g:augment_workspace_folders) == v:t_string
        let folders_list = [g:augment_workspace_folders]
    else
        call augment#log#Error('Workspace folders set to invalid value: ' . string(g:augment_workspace_folders) . '. See `:h g:augment_workspace_folders` for configuration instructions.')
        return []
    endif

    let valid_folders = []
    for folder in folders_list
        if type(folder) != v:t_string
            call augment#log#Error('Expected workspace folder type to be string. Got: ' . string(folder))
        else
            let abs_path = fnamemodify(folder, ':p')
            if !isdirectory(abs_path)
                call augment#log#Error('The following workspace folder does not exist: ' . abs_path)
            else
                call add(valid_folders, folder)
            endif
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
    let plugin_version = augment#version#Version()
    call augment#log#Info('Starting Augment Server v' . plugin_version)

    " If debugging is enabled, set the AUGMENT_LOG_LEVEL environment variable
    " which will enable debug logging in the server
    if exists('g:augment_debug') && g:augment_debug
        let $AUGMENT_LOG_LEVEL = 'debug'
        echom 'Augment: Debugging enabled'
    endif

    " Set the message handlers
    let notification_handlers = {
                \ 'augment/chatChunk': function('s:HandleChatChunk'),
                \ 'window/logMessage': function('s:HandleLogMessage'),
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

    " Convert any workspace folders to URIs for the language server
    let workspace_folders = s:GetWorkspaceFolders()

    " Start the server and send the initialize request
    let job_command = augment#client#GetJobCommand()
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
                    \ [job_command, notification_methods, workspace_folders])
    else
        " Vim-specific client setup
        call extend(client, {
                    \ 'request_id': 0,
                    \ 'requests': {},
                    \ 'Notify': function('s:VimNotify'),
                    \ 'Request': function('s:VimRequest'),
                    \ })

        let client.job = job_start(job_command, {
                    \ 'noblock': 1,
                    \ 'stoponexit': 'term',
                    \ 'in_mode': 'lsp',
                    \ 'out_mode': 'lsp',
                    \ 'out_cb': function('s:OnMessage', [client]),
                    \ 'err_cb': function('s:OnError', [client]),
                    \ 'exit_cb': function('s:OnExit', [client]),
                    \ })

        let vim_version = printf('%d.%d.%d', v:version / 100, v:version % 100, v:versionlong % 1000)
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
    call client.Request('augment/pluginVersion', {'version': plugin_version})

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
