;;; term-toggle.el --- Toggle to and from the *terminal* buffer

;; Filename: term-toggle.el
;; Description: Toggle a dedicated terminal
;; Author: Joseph <jixiuf@gmail.com>, Yatao <yatao.li@live.com>, Arthur <arthur.miller@live.com>
;; Created: 2011-03-02
;; Changed: 2021-09.04
;; Version: 0.9
;; URL: https://github.com/v-yadli/emacs-term-toggle
;; Keywords:  term toggle shell
;; Compatibility: (Test on GNU Emacs 24.3.1, 27.*, 28.0.50).
;;
;;{{{ License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.
;;}}}

;;; Commentary:
;; Derived from Joseph <jixiuf@gmail.com> (URL:
;; http://www.emacswiki.org/term-toggle.el), this plugin brings up a
;; quake-style console with commands term-toggle{,-cd}
;; The major difference with Joseph's version is that maximized
;; console feature is removed (in the original version sometimes it
;; gets stuck in maximized state, possibly because the window
;; configuration is corrupted). Also, this plugin determines whether
;; to split a new window for the console, or replace the buffer of
;; current selected window if height is not enough for a
;; split. Another feature is that this plugin will detect the status
;; of the terminal. When there's no process running in *terminal*
;; buffer, it will fire up another one.

;; Installation:
;;
;; o Download this file from git. Run M-x package-install-file on this file.
;;
;; Alternatively:
;;
;; o Place this file in a directory in your 'load-path.
;; o Put the following in your .emacs file:
;;   (autoload 'term-toggle "term-toggle"
;;    "Toggles between the *terminal* buffer and whatever buffer you are editing."
;;    t)
;;   (autoload 'term-toggle-cd "term-toggle"
;;    "Pops up a shell-buffer and insert a \"cd <file-dir>\" command." t)
;;   (global-set-key [M-f1] 'term-toggle)
;;   (global-set-key [C-f1] 'term-toggle-cd)
;; o Restart your Emacs.  To use term-toggle just hit M-f1 or C-f1
;;
;;; Changes:
;; 2021-09-04 A. Miller added support to exit term without quering for exit-confirm.
;; 2019-01-23 A. Miller: added eshell toggle

;;; Commands:
;;
;; Below are complete command list:
;;
;;  `term-toggle-cd'
;;    Calls `term-toggle' with a prefix argument.  Se command `term-toggle'
;;  `term-toggle'
;;    Toggles between the *eshell* buffer and whatever buffer you are editing.
;;  `term-toggle-eshell-cd'
;;    Calls `term-toggle-eshell' with a prefix argument.  Se command `term-toggle-eshell'
;;  `term-toggle-eshell'
;;    Toggles between the *eshell* buffer and whatever buffer you are editing.
;;

;;; Customizable Options:
(defgroup term-toggle nil
  "Quake style console toggle in current working directory.
Support toggle for term and eshell."
  :prefix "term-toggle-"
  :group 'applications)

(defcustom term-toggle-no-confirm-exit nil
  "Don't ask to confirm exit if there is a running bash process in terminal."
  :type 'boolean
  :group 'term-toggle)

(defcustom term-toggle-kill-buffer-on-term-exit nil
  "Kill buffer when shell process has exited."
  :type 'boolean
  :group 'term-toggle)

(defcustom term-toggle-goto-eob t
  "*If non-nil `term-toggle' will move point to the end of the shell-buffer
whenever the `term-toggle' switched to the shell-buffer.

When `term-toggle-cd' is called the point is allways moved to the end of the
shell-buffer"
  :type 'boolean
  :group 'term-toggle)

(defcustom term-toggle-minimum-split-height 10
  "The minimum height of a splittable window"
  :type 'fixnum
  :group 'term-toggle)

(defcustom term-toggle-default-height 15
  "The default height of a splitted window."
  :type 'fixnum
  :group 'term-toggle)

(defcustom term-toggle-auto-cd t
  "*If non-nil `term-toggle-cd' will send the \"cd\" command to the shell.
If nil `term-toggle-cd' will only insert the \"cd\" command in the
shell-buffer.  Leaving it to the user to press RET to send the command to
the shell."
  :type 'boolean
  :group 'term-toggle)

;;; Internal functions and declarations
(require 'term)
(require 'eshell)
(require 'esh-mode)

(defvar tt--replaced-buffer nil
  "Indicator for the term toggle behavior. When set to t, the term
  buffer will appear in the selected window instead of split it.")

(defvar tt--no-query-defined t
  "Indicator for the term toggle that user has set no-query-on-exit flag.
Internal don't use.")

(defvar tt--no-kill-on-exit-defined t
  "Indicator for the term toggle that user has set kill-buffer-on-exit flag.")

(defun tt--no-confirm-exit ()
  (let ((process (get-buffer-process (current-buffer))))
    (when (processp process) (set-process-query-on-exit-flag process nil))))

(defun tt--kill-buffer-on-term-exit ()
  (let ((buff (current-buffer))
        (proc (get-buffer-process (current-buffer))))
    (lexical-let ((buffer buff))
      (set-process-sentinel proc (lambda (__p event)
                                      (if (string= event "finished\n")
                                          (kill-buffer buffer)))))))

(defun term-toggle-setup-exit ()
  (if term-toggle-no-confirm-exit
      (when tt--no-query-defined
        (add-hook 'term-exec-hook 'tt--no-confirm-exit)
        (setq tt--no-query-defined nil))
    (unless tt--no-query-defined
      (remove-hook 'term-exec-hook 'tt--no-confirm-exit)
      (setq tt--no-query-defined t)))
  (if term-toggle-kill-buffer-on-term-exit
      (when tt--no-kill-on-exit-defined
        (add-hook 'term-exec-hook 'tt--kill-buffer-on-term-exit)
        (setq tt--no-kill-on-exit-defined nil))
    (unless tt--no-kill-on-exit-defined
      (remove-hook 'term-exec-hook 'tt--kill-buffer-on-term-exit)
      (setq tt--no-kill-on-exit-defined nil))))

(defun tt--get-buffer (shell)
  "If there is a buffer return buffer, otherwise string that can be used as a
buffer name."
  (when (eq shell 'term)
    (setq shell "terminal"))
  (let* ((name (format "*%s*" shell))
         (buffer (get-buffer name)))
  (if buffer buffer name)))

(defun tt--autocd (shell cd-command)
  (if (and cd-command term-toggle-auto-cd)
      (cond ((or (eq shell 'shell) (eq shell 'term) (eq shell 'ansi-term))
             (term-send-raw-string (concat cd-command "\n")))
            ((or (eq shell 'eshell) (eq shell 'ielm))
             (comint-send-input (concat cd-command "\n"))))))

(defun tt--fire-up-shell (shell)
  "Fires up a shell."
  (condition-case the-error
      (cond ((or (eq shell 'shell) (eq shell 'term) (eq shell 'ansi-term))
             (let ((cmd (getenv "SHELL")))
               (funcall shell cmd)))
            ((or (eq shell 'eshell) (eq shell 'ielm))
             (funcall shell)))
    (error (switch-to-buffer (tt--get-buffer shell)))))

(defun tt--buffer-goto-shell (shell make-cd)
  "Switches other window to the *terminal* buffer.  If no *terminal*
buffer exists start a new shell and switch to it in a window (see
`term-toggle-buffer-switch-to-window' for the algorithm).  If argument
MAKE-CD is non-nil, insert a \"cd DIR\" command into the shell, where
DIR is the directory of the current buffer."
  (let ((shell-buffer (tt--get-buffer shell))
	(cd-command (concat "cd " default-directory)))
    (unless (or (eq shell 'eshell) (eq shell 'ielm))
         (term-toggle-setup-exit))
    (tt--buffer-switch-to-window)
    (if shell-buffer
        (progn
          (switch-to-buffer shell-buffer)
          (unless (and (eq shell 'ielm) (eq shell 'eshell))
            (unless (term-check-proc shell-buffer)
              (kill-buffer shell-buffer)
              (tt--fire-up-shell shell))
            (if (or cd-command term-toggle-goto-eob)
                (term-send-del))))
      (tt--fire-up-shell shell))
    (set-window-dedicated-p (selected-window) t)
    (tt--autocd shell cd-command)))

(defun tt--buffer-switch-to-window ()
  "Switches to a window. If the current window has a splittable size
\\(in height\\), split it and switch to the bottom part.  Otherwise, use
this window and mark the `tt--replaced-buffer' flag and keep
the same window selected"
  (let ((this-window (selected-window)))
    (if (>=
         (window-total-height this-window)
         term-toggle-minimum-split-height)
	(progn
          (setq tt--replaced-buffer nil)
	  (split-window-vertically)
          (other-window 1)
          (setq this-window (selected-window))
          (let ((delta (- (window-height this-window) term-toggle-default-height)))
            (if (> delta 0)
                (shrink-window delta))))
      (setq tt--replaced-buffer t))))

(defun term-toggle (shell make-cd)
  "Toggles between the *terminal* buffer and whatever buffer you are
editing.  With a prefix ARG also insert a \"cd DIR\" command into the
shell, where DIR is the directory of the current buffer.
When called in the *terminal* buffer, the terminal window is
closed. The original buffer will be restored if it's a replace instead
of a split.  Options: `term-toggle-goto-eob'"
  ;; If the terminal window exists, kill it
  ;; Otherwise, bring it on.
  (let ((shell-window (get-buffer-window (tt--get-buffer shell) t)))
    (if shell-window
        (if tt--replaced-buffer
            (progn
              (set-window-dedicated-p shell-window nil)
              (bury-buffer))
          (delete-window shell-window))
      (tt--buffer-goto-shell shell make-cd))))

;;; Commands

;;;###autoload
(defun term-toggle-term ()
  "Calls `term-toggle' with a prefix argument.  Se command `term-toggle'"
  (interactive)
  (term-toggle 'term t))

;;;###autoload
(defun term-toggle-shell ()
  "Calls `term-toggle' with a prefix argument.  Se command `term-toggle'"
  (interactive)
  (term-toggle 'shell t))

;;;###autoload
(defun term-toggle-ansi ()
  "Calls `term-toggle' with a prefix argument.  Se command `term-toggle'"
  (interactive)
  (term-toggle 'ansi-term t))

;;;###autoload
(defun term-toggle-eshell ()
  "Calls `term-toggle' with a prefix argument.  Se command `term-toggle'"
  (interactive)
  (term-toggle 'eshell t))

;;;###autoload
(defun term-toggle-ielm ()
  "Calls `term-toggle' with a prefix argument.  Se command `term-toggle'"
  (interactive)
  (term-toggle 'ielm t))

(provide 'term-toggle)

;;; term-toggle.el ends here
