;;; lsp-augment.el --- lsp-mode client for Augment   -*- lexical-binding: t; -*-

;;; Copyright (C) 2025 Roland Dreier

;;; Author: Roland Dreier <roland.dreier@gmail.com>

;;; Commentary:

;;; LSP client for the Augment (https://www.augmentcode.com/) node server
;;; Based on the vim client from https://github.com/augmentcode/augment.vim

;;; Code:

(require 'lsp-mode)

(defun lsp-augment-signin ()
  "Log into the Augment service."
  (interactive)
  (let
      ((signin-response
	(lsp-send-request (lsp-make-request "augment/login" nil))))
    (if (gethash "loggedIn" signin-response)
	(message "Already logged into Augment")
      (progn
	(browse-url (gethash "url" signin-response))
	(let ((auth-code (read-from-minibuffer (format "Please complete authentication in your browser...\n%s\n\nAfter authenticating, you will receive a code.\nPaste the code in the prompt below.\n\nEnter the authentication code: " (gethash "url" signin-response)))))
	  (lsp-send-request (lsp-make-request "augment/token" (list :code auth-code)))))))
)

(defun lsp-augment-signout ()
  "Log out of the Augment service."
  (interactive)
  (let
      ((signout-response
	(lsp-send-request (lsp-make-request "augment/logout" nil))))
    (message "Signed out of Augment."))
)

(defcustom lsp-augment-server-script "server.js"
  "Path to server script to run with node."
  :group 'lsp-augment
  :risky t
  :type 'file)

(defun lsp-augment--server-command ()
  "Return the executable and command line arguments."
  (list "node" lsp-augment-server-script "--stdio"))

(defun lsp-augment--server-initialization-options ()
  "Set initialization options to provide versioned user agent."
  (list :editor "emacs"
	:vimVersion emacs-version
	:pluginVersion "emacs 0.1.0"))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection #'lsp-augment--server-command)
  :activation-fn (lsp-activate-on "augment")
  :server-id 'augment-lsp-server
  :initialization-options #'lsp-augment--server-initialization-options))

(provide 'lsp-augment)
;;; lsp-augment.el ends here
