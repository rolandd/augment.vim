" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Entry point for augment vim integration

if exists('g:loaded_augment')
    finish
endif
let g:loaded_augment = 1

function! s:CheckEditorCompatibility() abort
    " NOTE(mpauly): I'm not aware of any compatibility issues with neovim, but
    " as they come up we can add them here.
    if !has('nvim')
        if v:version < 901
            let major_version = v:version / 100
            let minor_version = v:version % 100
            call augment#DisplayError('Current Vim version ' . major_version . '.' . minor_version . ' less than minimum supported version 9.1')
            return v:false
        endif
    endif
    return v:true
endfunction

function! s:CheckRuntimeCompatibility() abort
    let job_command = augment#client#GetJobCommand()
    if len(job_command) == 0
        call augment#DisplayError('Failed to determine the Augment runtime. Did you set `g:augment_job_command` to an empty list?')
        return v:false
    endif

    let s:runtime = job_command[0]
    if !executable(s:runtime)
        call augment#DisplayError('The Augment runtime (' . s:runtime . ') was not found. If node is available on your system under a different name, you can set the `g:augment_node_command` variable. See `:help g:augment_node_command` for more details.')
        return v:false
    endif

    " Check the runtime version asynchronously
    function! s:HandleRuntimeVersion() abort
        if !exists('s:runtime_version')
            call augment#log#Warn('Failed to determine the Augment runtime version. Command `' . s:runtime . ' --version` returned no output.')
            return
        endif

        let version_match = matchlist(s:runtime_version, 'v\(\d\+\)\.\d\+\.\d\+')
        if empty(version_match)
            call augment#log#Warn('Failed to parse runtime version: ' . s:runtime_version)
            return
        endif

        let major_version = str2nr(version_match[1])
        if major_version == 0
            call augment#log#Warn('Failed to parse runtime version: ' . s:runtime_version)
            return
        endif

        " NOTE(mpauly): While Node v22 is the version we've tested most, I
        " believe any version >= 19 should work fine. Native file watching for
        " linux wasn't introduced until v19, so we definitely want to require
        " that.
        if major_version < 19
            call augment#DisplayError('Unsupported runtime version: ' . s:runtime_version . '. Please use Node.js version 22 or later.')
            return
        endif

        call augment#log#Info('Using runtime (Node.js) version: ' . s:runtime_version)
    endfunction

    let version_command = [s:runtime, '--version']
    if has("nvim")
        function! s:OnStdout(job_id, data, event) abort
            if !empty(a:data) && !empty(a:data[0])
                let s:runtime_version = a:data[0]
            endif
        endfunction

        function! s:OnExit(job_id, exit_code, event) abort
            call s:HandleRuntimeVersion()
        endfunction

        let s:runtime_version_job = jobstart(version_command, {
            \ 'on_stdout': function('s:OnStdout'),
            \ 'on_exit': function('s:OnExit'),
            \ })
        call timer_start(1, {_ -> jobstop(s:runtime_version_job)})
    else
        function! s:OnOut(channel, message) abort
            if !empty(a:message)
                let s:runtime_version = a:message
            endif
        endfunction

        function! s:OnExit(job, status) abort
            call s:HandleRuntimeVersion()
        endfunction

        let s:runtime_version_job = job_start(version_command, {
            \ 'out_cb': function('s:OnOut'),
            \ 'exit_cb': function('s:OnExit'),
            \ })
        call timer_start(1000, {_ -> job_stop(s:runtime_version_job)})
    endif

    return v:true
endfunction

function! s:SetupVirtualText() abort
    if &t_Co == 256
        hi def AugmentSuggestionHighlight guifg=#808080 ctermfg=244
    elseif &t_Co >= 16
        hi def AugmentSuggestionHighlight guifg=#808080 ctermfg=8
    else
        call augment#log#Warn('Your terminal supports only ' . &t_Co . ' colors. Augment virtual text works best with at least 16 colors. Please check the value of the "t_Co" option and environment variable "$TERM."')
        hi def AugmentSuggestionHighlight guifg=#808080 ctermfg=6
    endif

    " For vim, create a prop type for the virtual text. For nvim we use the
    " AugmentSuggestion namespace which doesn't require setup.
    if !has('nvim')
        call prop_type_add('AugmentSuggestion', {'highlight': 'AugmentSuggestionHighlight'})
    endif
endfunction

function! s:SetupKeybinds() abort
    if !exists('g:augment_disable_tab_mapping') || !g:augment_disable_tab_mapping
        inoremap <tab> <cmd>call augment#Accept("\<tab>")<cr>
    endif
endfunction

" Setup commands
command! -range -nargs=* -complete=custom,augment#CommandComplete Augment <line1>,<line2> call augment#Command(<range>, <q-args>)

if !s:CheckEditorCompatibility()
    finish
endif
if !s:CheckRuntimeCompatibility()
    finish
endif

call s:SetupVirtualText()
call s:SetupKeybinds()

augroup augment_vim
    autocmd!

    autocmd VimEnter * call augment#OnVimEnter()
    autocmd BufEnter * call augment#OnBufEnter()
    autocmd TextChanged * call augment#OnTextChanged()
    autocmd TextChangedI * call augment#OnTextChangedI()
    autocmd CursorMovedI * call augment#OnCursorMovedI()
    autocmd InsertEnter * call augment#OnInsertEnter()
    autocmd InsertLeavePre * call augment#OnInsertLeavePre()
augroup END

let g:augment_initialized = v:true
