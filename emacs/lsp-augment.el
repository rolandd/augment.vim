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
	(let ((auth-code (read-from-minibuffer (format "Please complete authentication in your browser...
%s

After authenticating, you will receive a code.
Paste the code in the prompt below.

Enter the authentication code: " (gethash "url" signin-response)))))
	  (lsp-send-request (lsp-make-request "augment/token" (list :code auth-code))))))))

(defun lsp-augment-signout ()
  "Log out of the Augment service."
  (interactive)
  (let
      ((signout-response
	(lsp-send-request (lsp-make-request "augment/logout" nil))))
    (message "Signed out of Augment.")))

(defun lsp-augment--chat-append-text (text)
  "Append text to the Augment chat buffer."
  (let ((buf (get-buffer-create "*Augment Chat History*"))
	(inhibit-read-only t))
    (with-current-buffer buf
      (special-mode)
      (goto-char (point-max))
      (insert text)
      (pop-to-buffer buf))))

(defun lsp-augment--chat-append-message (message)
  "Append a user chat message to the Augment chat buffer."
  (lsp-augment--chat-append-text (format "================================================================================

	*You*

%s

--------------------------------------------------------------------------------

	*Augment*

" message)))

(defun lsp-augment-chat (message)
  "Send a chat request to Augment."
  (interactive "MMessage: ")
  (let ((chat-message (append (list :textDocumentPosition (lsp--text-document-position-params)
				   :message message)
			     (if (region-active-p)
				 (list :selectedText
				       (buffer-substring-no-properties (region-beginning) (region-end)))))))
    (lsp-augment--chat-append-message message)
    (lsp-request-async "augment/chat"
		       chat-message
		       (lambda (response) nil)
		       :error-handler (lambda (response) (message "augment/chat returned an error")))))

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

(lsp-defun lsp-augment--chat-chunk-handler (_workspace params)
  "Handler for `augment/chatChunk` notification."
  (lsp-augment--chat-append-text (gethash "text" params)))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection #'lsp-augment--server-command)
  :activation-fn (lsp-activate-on "augment")
  :server-id 'augment-lsp-server
  :initialization-options #'lsp-augment--server-initialization-options
  :notification-handlers (lsp-ht
			  ("augment/chatChunk" #'lsp-augment--chat-chunk-handler))))

(provide 'lsp-augment)
;;; lsp-augment.el ends here
