;;; lsp-augment.el --- lsp-mode client for Augment   -*- lexical-binding: t; -*-

;;; Copyright (C) 2025 Roland Dreier
;;; MIT License - See LICENSE.md for full terms

;;; Author: Roland Dreier <roland.dreier@gmail.com>

;;; Commentary:

;;; LSP client for the Augment (https://www.augmentcode.com/) node server
;;; Based on the vim client from https://github.com/augmentcode/augment.vim

;;; Code:

(require 'lsp-mode)
(require 'markdown-mode)

(defgroup lsp-augment nil
  "LSP support for Augment."
  :group 'lsp-mode
  :link '(url-link "https://www.augmentcode.com"))

(defcustom lsp-augment-server-script "server.js"
  "Path to server script to run with node."
  :group 'lsp-augment
  :risky t
  :type 'file)

(defun lsp-augment-signin ()
  "Log into the Augment service."
  (interactive)
  (condition-case err
      (let ((signin-response (lsp-request "augment/login" nil)))
	(if (lsp-get signin-response :loggedIn)
	    (message "Already logged into Augment")
	  (progn
	    (browse-url (lsp-get signin-response :url))
	    (let ((auth-code (read-from-minibuffer (format "Please complete authentication in your browser...
%s

After authenticating, you will receive a code.
Paste the code in the prompt below.

Enter the authentication code: " (lsp-get signin-response :url)))))
	      (lsp-request "augment/token" (list :code auth-code))
	      (message "Successfully logged into Augment.")))))
    (error (message "Failed to sign in: %s" (error-message-string err)))))

(defun lsp-augment-signout ()
  "Log out of the Augment service."
  (interactive)
  (condition-case err
      (let ((signout-response (lsp-request "augment/logout" nil)))
	(message "Signed out of Augment."))
    (error (message "Failed to sign out: %s" (error-message-string err)))))

(defun lsp-augment--chat-append-text (text)
  "Append text to the Augment chat buffer."
  (let ((buf-name "*Augment Chat History*"))
    (with-current-buffer (get-buffer-create buf-name)
      (unless (derived-mode-p 'markdown-view-mode)
	(markdown-view-mode))
      (save-excursion
	(let ((inhibit-read-only t))
	  (goto-char (point-max))
	  (insert text)))
      (display-buffer buf-name
		      '((display-buffer-reuse-window
			 display-buffer-pop-up-window)
			(reusable-frames . visible))))))

(defun lsp-augment--chat-append-message (message)
  "Append a user chat message to the Augment chat buffer."
  (lsp-augment--chat-append-text (format "================================================================================

	*You*

%s

--------------------------------------------------------------------------------

	*Augment*

" message)))

(lsp-defun lsp-augment--chat-chunk-handler (_workspace params)
  "Handler for `augment/chatChunk` notification."
  (lsp-augment--chat-append-text (lsp-get params :text)))

(defun lsp-augment--chat-response-handler (message response)
  "Update chat history when a response is received."
  (let ((text (lsp-get response :text))
	(request-id (lsp-get response :requestId))
	(buf (get-buffer "*Augment Chat History*")))
    (when (and buf text request-id)
      (with-current-buffer buf
	(unless (local-variable-p 'lsp-augment--chat-history)
	  (set (make-local-variable 'lsp-augment--chat-history) []))
	(setq lsp-augment--chat-history
	      (vconcat lsp-augment--chat-history
		       `[(:request_message ,message
					   :response_text ,text
					   :request_id ,request-id)]))))))

(defun lsp-augment-chat (message)
  "Send a chat request to Augment."
  (interactive "MMessage: ")
  (condition-case err
      (let* ((chat-buf (get-buffer "*Augment Chat History*"))
	     (chat-history (and chat-buf
				(buffer-local-value 'lsp-augment--chat-history chat-buf)))
	     (chat-message (append (list :textDocumentPosition (lsp--text-document-position-params)
					:message message)
				  (when (region-active-p)
				    (list :selectedText
					  (buffer-substring-no-properties (region-beginning) (region-end))))
				  (when chat-history
				    (list :history chat-history)))))
	(lsp-log "chat request: %s" (json-encode chat-message))
	(lsp-augment--chat-append-message message)
	(lsp-request-async "augment/chat"
			   chat-message
			   (lambda (response)
			     (lsp-augment--chat-response-handler message response))
			   :error-handler (lambda (err)
					    (message "Chat error: %s" (error-message-string err)))))
    (error (message "Failed to send chat message: %s" (error-message-string err)))))

(defun lsp-augment-reset-chat ()
  "Clear the Augment chat history buffer and reset chat history."
  (interactive)
  (let ((buf-name "*Augment Chat History*"))
    (when (get-buffer buf-name)
      (with-current-buffer buf-name
	(let ((inhibit-read-only t))
	  (erase-buffer))
	(setq-local lsp-augment--chat-history nil)))))

(defun lsp-augment-status ()
  "Get the current status of the Augment service.
Returns a plist with status information from the server."
  (interactive)
  (condition-case err
      (let ((status-response
	     (lsp-request "augment/status" nil)))
	(when (called-interactively-p 'interactive)
	  (let ((login-status (if (lsp-get status-response :loggedIn)
				  "Signed in."
				"Not signed in."))
		(sync-status (when-let ((sync-percent (lsp-get status-response :syncPercentage)))
			       (format " (workspace %s%% synced)" sync-percent))))
	    (message "Augment%s: %s"
		     (or sync-status "")
		     login-status)))
	status-response)
    (error (message "Failed to get status: %s" (error-message-string err))
	   nil)))

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
  :multi-root t
  :add-on? t
  :completion-in-comments? t
  :initialization-options #'lsp-augment--server-initialization-options
  :notification-handlers (lsp-ht
			  ("augment/chatChunk" #'lsp-augment--chat-chunk-handler))))

(defun lsp-augment--completion-modify-response (resp)
  "Modify the completion response RESP before processing."
  (let ((items (if (lsp-completion-list? resp)
		   (lsp:completion-list-items resp)
		 resp)))
    ;; Filter out empty completions
    (setq items
	  (cl-remove-if
	   (lambda (item)
	     (let ((insert-text (lsp:completion-item-insert-text? item)))
	       (and insert-text (string-empty-p insert-text))))
	   items))

    ;; Convert insertText items to textEdit
    (dolist (item items)
      (when-let* ((insert-text (lsp:completion-item-insert-text? item)))
	  (lsp:set-completion-item-label item insert-text)

	  (unless (lsp:completion-item-text-edit? item)
	    (let* ((position (lsp-make-position :line (lsp--cur-line)
						:character (- (point) (line-beginning-position))))
		   (range (lsp-make-range :start position :end position))
		   (text-edit (lsp-make-text-edit :range range :new-text insert-text)))
	      (lsp:set-completion-item-text-edit? item text-edit)
	      (lsp:set-completion-item-insert-text? item nil))))))
    resp)

(defun lsp-augment--completion-advice (orig-fun method params &rest args)
  "Advice around lsp-request-while-no-input' to fix completion response for emacs."
  (if (string= method "textDocument/completion")
      (let ((response (apply orig-fun method params args)))
	(lsp-augment--completion-modify-response response))
    (apply orig-fun method params args)))

(advice-add 'lsp-request-while-no-input :around #'lsp-augment--completion-advice)

(provide 'lsp-augment)
;;; lsp-augment.el ends here
