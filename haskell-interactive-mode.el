;;; haskell-interactive-mode.el -- The interactive Haskell mode.

;; Copyright (C) 2011-2012 Chris Done

;; Author: Chris Done <chrisdone@gmail.com>

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;;; Todo:

;;; Code:

(defvar haskell-interactive-prompt "λ> "
  "The prompt to use.")

(defvar haskell-interactive-greetings
  (list "Hello, Haskell!"
        "The lambdas must flow."
        "Hours of hacking await!"
        "The next big Haskell project is about to start!"
        "Your wish is my IO ().")
  "Greetings for when the Haskell process starts up.")

;;;###autoload
(defun haskell-interactive-mode (session)
  "Interactive mode for Haskell."
  (interactive)
  (kill-all-local-variables)
  (haskell-session-assign session)
  (use-local-map haskell-interactive-mode-map)
  (set (make-local-variable 'haskell-interactive-mode) t)
  (setq major-mode 'haskell-interactive-mode)
  (setq mode-name "Interactive-Haskell")
  (run-mode-hooks 'haskell-interactive-mode-hook)
  (set (make-local-variable 'haskell-interactive-mode-history)
       (list))
  (set (make-local-variable 'haskell-interactive-mode-history-index)
       0)
  (haskell-interactive-mode-prompt session))

(defface haskell-interactive-face-prompt
  '((t :inherit 'font-lock-function-name-face))
  "Face for the prompt."
  :group 'haskell)

(defface haskell-interactive-face-result
  '((t :inherit 'font-lock-string-face))
  "Face for the result."
  :group 'haskell)

(defvar haskell-interactive-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'haskell-interactive-mode-return)
    (define-key map (kbd "C-j") 'haskell-interactive-mode-newline-indent)
    (define-key map (kbd "C-a") 'haskell-interactive-mode-beginning)
    (define-key map (kbd "C-c C-k") 'haskell-interactive-mode-clear)
    (define-key map (kbd "C-c C-c") 'haskell-process-interrupt)
    (define-key map (kbd "M-p")
      '(lambda () (interactive) (haskell-interactive-mode-history-toggle 1)))
    (define-key map (kbd "M-n")
      '(lambda () (interactive) (haskell-interactive-mode-history-toggle -1)))
    map)
  "Interactive Haskell mode map.")

(defun haskell-interactive-mode-return ()
  "Handle the return key."
  (interactive)
  (let ((expr (haskell-interactive-mode-input))
        (session (haskell-session))
        (process (haskell-process)))
    (when (not (string= "" (replace-regexp-in-string " " "" expr)))
      (haskell-interactive-mode-history-add expr)
    (haskell-process-queue-command
     process
     (haskell-command-make
      (list session process expr)
      (lambda (state)
        (haskell-process-send-string (cadr state)
                                     (caddr state)))
      (lambda (state))
      (lambda (state response)
        (haskell-interactive-mode-eval-result response)
        (haskell-interactive-mode-prompt (car state))))))))

(defun haskell-interactive-mode-beginning ()
  "Go to the start of the line."
  (interactive)
  (if (search-backward-regexp haskell-interactive-prompt (line-beginning-position) t 1)
      (search-forward-regexp haskell-interactive-prompt (line-end-position) t 1)
    (move-beginning-of-line nil)))

(defun haskell-interactive-mode-clear ()
  "Newline and indent at the prompt."
  (interactive)
  (with-current-buffer (haskell-session-interactive-buffer (haskell-session))
    (let ((inhibit-read-only t))
      (set-text-properties (point-min) (point-max) nil))
    (delete-region (point-min) (point-max))
    (mapcar 'delete-overlay (overlays-in (point-min) (point-max)))
    (haskell-interactive-mode-prompt (haskell-session))))

(defun haskell-interactive-mode-input ()
  "Get the interactive mode input."
  (substring
   (buffer-substring-no-properties
    (save-excursion
      (goto-char (max (point-max)))
      (search-backward-regexp haskell-interactive-prompt))
    (line-end-position))
   (length haskell-interactive-prompt)))

(defun haskell-interactive-mode-prompt (session)
  "Show a prompt at the end of the buffer."
  (with-current-buffer (haskell-session-interactive-buffer session)
    (goto-char (point-max))
    (when (> (point-max) (point-min))
      (insert "\n"))
    (insert (propertize haskell-interactive-prompt
                        'face 'haskell-interactive-face-prompt
                        'read-only t
                        'rear-nonsticky t
                        'prompt t))))

(defun haskell-interactive-mode-eval-result (text)
  "Insert the result of an eval as a pretty printed Showable, if
  parseable, or otherwise just as-is."
  (with-current-buffer (haskell-session-interactive-buffer (haskell-session))
    (goto-char (point-max))
    (insert "\n")
    (insert (propertize text
                        'face 'haskell-interactive-face-result
                        'read-only t
                        'rear-nonsticky t
                        'prompt t
                        'result t))))

;;;###autoload
(defun haskell-interactive-mode-echo (session message)
  "Echo a read only piece of text before the prompt."
  (with-current-buffer (haskell-session-interactive-buffer session)
    (save-excursion
      (haskell-interactive-mode-goto-end-point)
      (insert (propertize (concat (if (= (point-min) (point)) "" "\n")
                                  message
                                  (if (= (point-min) (point)) "\n" ""))
                          'read-only t
                          'rear-nonsticky t)))))

(defun haskell-interactive-mode-goto-end-point ()
  "Go to the 'end' of the buffer (before the prompt.)"
  (goto-char (point-max))
  (search-backward-regexp haskell-interactive-prompt (point-min) t 1)
  (if (> (point) (point-min))
      (backward-char)))

(defun haskell-interactive-mode-history-add (input)
  "Add item to the history."
  (setq haskell-interactive-mode-history
        (cons ""
              (cons input
                    (remove-if (lambda (i) (or (string= i input) (string= i "")))
                               haskell-interactive-mode-history))))
  (setq haskell-interactive-mode-history-index
        0))

(defun haskell-interactive-mode-history-toggle (n)
  "Toggle the history n items up or down."
  (unless (null haskell-interactive-mode-history)
    (setq haskell-interactive-mode-history-index
          (mod (+ haskell-interactive-mode-history-index n)
               (length haskell-interactive-mode-history)))
    (haskell-interactive-mode-set-prompt
     (nth haskell-interactive-mode-history-index
          haskell-interactive-mode-history))))

(defun haskell-interactive-mode-set-prompt (p)
  "Set (and overwrite) the current prompt."
  (with-current-buffer (haskell-session-interactive-buffer (haskell-session))
    (goto-char (point-max))
    (goto-char (line-beginning-position))
    (search-forward-regexp haskell-interactive-prompt)
    (delete-region (point) (line-end-position))
    (insert p)))

(defun haskell-interactive-buffer ()
  "Get the interactive buffer of the session."
  (haskell-session-interactive-buffer (haskell-session)))
