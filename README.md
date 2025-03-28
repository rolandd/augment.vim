# Augment Vim & Neovim Plugin for Emacs lsp-mode

This is an attempt to adapt the lsp-server from
[Augment](https://augmentcode.com)'s Vim plugin to work in emacs with
[lsp-mode](https://emacs-lsp.github.io/lsp-mode/)

## Current status

What's working:

1. Augment log in and status

1. Chat, including multi-turn and referring to a region of code

1. Completions with company-mode (but see the commit "Rewrite
   completion responses from Augment so Emacs accepts them")

## Getting Started

1. Sign up for a free trial of Augment at
   [augmentcode.com](https://augmentcode.com).

1. Install [Node.js](https://nodejs.org/en/download/package-manager/all),
   version 22.0.0 or newer, which is a required dependency.

1. Install lsp-mode and markdown-mode in emacs

1. Clone this repository somewhere and customize the
   `lsp-augment-server-script` variable to point at the
   `dist/server.js` file from the repo, either via `M-x customize` and
   searching for "augment", or by hand:

        ```(custom-set-variables
         ;; custom-set-variables was added by Custom.
         ;; If you edit it by hand, you could mess it up, so be careful.
         ;; Your init file should contain only one such instance.
         ;; If there is more than one, they won't work right.
         '(lsp-augment-server-script "/path/to/augment.vim.git/dist/server.js"))
        ```

1. Set up lsp-mode to use lsp-augment, adjusting the load-path as
   necessary to include this repository:

        ```(require 'lsp-mode)
        (add-hook 'emacs-lisp-mode-hook #'lsp)

        (add-to-list 'load-path "/path/to/augment.vim.git/emacs/")
        (require 'lsp-augment)
        (add-to-list 'lsp-language-id-configuration '(emacs-lisp-mode . "augment"))
        ```

1. Start emacs and log into your Augment account via `M-x lsp-augment-signin`

## Basic Usage

Use `M-x lsp-augment-signin` to log in and `M-x lsp-augment-signout`
to log out. You can check the status including the progress of
workspace sync with `M-x lsp-augment-status`.

## Chat

Use `M-x lsp-augment-chat` to chat with Augment; you will be prompted
to enter your chat message. If the region is active then the selected
text will be passed to Augment as part of the chat. The chat history
is kept in a `*Augment Chat History*` buffer and will be used for
multi-turn conversations.

To clear the history and start a new conversion, use the function `M-x
lsp-augment-reset-chat`.

## FAQ

**Q: My workspace is taking a long time to sync. What should I do?**

A: It may take a while to sync if you have a very large codebase that has not
been synced before. It's also not uncommon to inadvertenly include a large
directory like `node_modules/`. You can use `M-x lsp-augment-signout` to see the
progress of the sync. If the sync is making progress but just slow, it may be
worth checking if you have a large directory that you don't need to sync. You
can add these directories to your `.augmentignore` file to exclude it from the
sync. If you're still having trouble, please file a github issue with a
description of the problem and include the output of `:Augment log`.

## Licensing and Distribution

This repository includes two main components:

1. **Vim Plugin:** This includes all files in the repository except `dist` folder. These files are licensed under the [MIT License](LICENSE.md#vim-plugin).
2. **Emacs Lisp Client:** This is licensed under the same [MIT License](LICENSE.md#vim-plugin).
1. **Server (`dist` folder):** This file is proprietary and licensed under a [Custom Proprietary License](LICENSE.md#server).

For details on usage restrictions, refer to the [LICENSE.md](LICENSE.md) file.

## Reporting Issues

We encourage users to report any bugs or issues directly to us. Please use the [Issues](https://github.com/augmentcode/augment.vim/issues) section of this repository to share your feedback.

For any other questions, feel free to reach out to [Augment Support](https://support.augmentcode.com/).
