" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" Entry point for augment vim integration

if exists('g:loaded_augment')
    finish
endif
let g:loaded_augment = 1

" TODO(mpauly): Update the required vim version after we have a better idea of
" what exact features we need. Version 9.1 is a conservative choice and many
" 9.0.X should also work (Copilot uses 9.0.0185).

" Check for version compatibility
if has('nvim')
    " TODO(mpauly): compitibility check for nvim
else
    if v:version < 901
        function! s:ShowVersionWarning()
            let major_version = v:version / 100
            let minor_version = v:version % 100
            echohl WarningMsg
            echom 'Augment: Current Vim version ' . major_version . '.' . minor_version . ' less than minimum supported version 9.1'
            echohl None
        endfunction

        augroup augment_vim_version_check
            autocmd!
            autocmd VimEnter * call s:ShowVersionWarning()
        augroup END

        finish
    endif
endif

" Setup commands
command! -range -nargs=* -complete=custom,augment#CommandComplete Augment <line1>,<line2> call augment#Command(<range>, <q-args>)

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
