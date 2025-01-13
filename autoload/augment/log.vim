" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Logging functionality

" Return the file to be used for logging. If the user has provided a log file,
" use that. Otherwise, create a temporary one.
function! s:GetLogFile() abort
    if exists('g:augment_log_file')
        let log_file = g:augment_log_file
    else
        let log_file = tempname() . '-augment.log'
    endif

    " Write an empty line to attempt to create the file if it doesn't exist
    " and clear its contents if it does
    try
        call writefile([], log_file)
    catch
    endtry

    return log_file
endfunction

let s:log_file = s:GetLogFile()

" Format and write a message to the log. Note that this will silently fail if
" the log file can't be written to.
function! s:Log(message, level) abort
    if filewritable(s:log_file)
        let timestamp = strftime('%Y-%m-%d %H:%M:%S')
        let formatted = timestamp . ' ' . a:level . ' ' . a:message

        call writefile([formatted], s:log_file, 'a')

        " Update the contents of the log buffer if it is open
        if bufexists(s:log_file)
            let bufnr = bufnr(s:log_file)
            if bufnr != -1
                let lines = readfile(s:log_file)
                call setbufvar(bufnr, '&modifiable', 1)
                call setbufline(bufnr, 1, lines)
                call setbufvar(bufnr, '&modifiable', 0)
            endif
        endif
    endif
endfunction

function! augment#log#Debug(message) abort
    if exists('g:augment_debug') && g:augment_debug
        call s:Log(a:message, '[DEBUG]')
    endif
endfunction

function! augment#log#Info(message) abort
    call s:Log(a:message, '[INFO]')
endfunction

function! augment#log#Warn(message) abort
    call s:Log(a:message, '[WARN]')
endfunction

function! augment#log#Error(message) abort
    call s:Log(a:message, '[ERROR]')
endfunction

" Open the log file in a read-only buffer
function! augment#log#Show() abort
    if !filewritable(s:log_file)
        echoerr 'Unable to open log file at: ' . s:log_file
        return
    endif

    execute 'botright split ' . s:log_file
    setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable
endfunction
