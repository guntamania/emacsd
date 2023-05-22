;; <leaf-install-code>
(eval-and-compile
  (customize-set-variable
   'package-archives '(("org" . "https://orgmode.org/elpa/")
                       ("melpa" . "https://melpa.org/packages/")
                       ("gnu" . "https://elpa.gnu.org/packages/")))
  (package-initialize)
  (unless (package-installed-p 'leaf)
    (package-refresh-contents)
    (package-install 'leaf))

  (leaf leaf-keywords
    :ensure t
    :init
    ;; optional packages if you want to use :hydra, :el-get, :blackout,,,
    (leaf hydra :ensure t)
    (leaf el-get :ensure t)
    (leaf blackout :ensure t)

    :config
    ;; initialize leaf-keywords.el
    (leaf-keywords-init)))
;; </leaf-install-code>

(global-linum-mode 1)

(global-set-key "\C-h" 'delete-backward-char)
(define-key global-map "\C-o" 'other-window)

(fset 'yes-or-no-p 'y-or-n-p)

(transient-mark-mode t) ; 選択部分のハイライト
(global-font-lock-mode t)

(custom-set-variables '(line-number-mode t) '(column-number-mode t) ) ;行数表示
;; タイトルバーにファイル名を表示する
(setq frame-title-format (format "%%f - emacs" (system-name)))
(display-time)  ; 時間を表示

;; Stop Auto Backup
(setq make-backup-files nil)
(setq auto-save-default nil)

(global-auto-revert-mode)

(setq indent-line-function 'indent-relative-maybe) ; 前と同じ行の幅にインデント
(setq completion-ignore-case t) ; file名の補完で大文字小文字を区別しない
(setq inhibit-startup-message t) ;スタートアップ非表示
(setq initial-scratch-message "") ;スクラッチのメッセージ非表示

(leaf leaf
  :config
  (leaf leaf-convert :ensure t)
  (leaf leaf-tree
    :ensure t
    :custom ((imenu-list-size . 30)
             (imenu-list-position . 'left))))

(leaf zenburn-theme
  :ensure t
  :config (load-theme 'zenburn t)
  )

(leaf paren
  :doc "highlight matching paren"
  :tag "builtin"
  :custom ((show-paren-delay . 0.1))
  :global-minor-mode show-paren-mode)


(leaf vertico
  :ensure t
  :global-minor-mode (vertico-mode)
  ;; :custom ((vertico-count 20)
  ;;          (vertico-resize t))
  ;; ;; :config
  ;; ;; Optionally enable cycling for `vertico-next' and `vertico-previous'.
  ;; ;; (setq vertico-cycle t)
  ;; (leaf savehist
  ;;   :global-minor-mode (savehist-mode)
  ;;  )
 )
  

;; Persist history over Emacs restarts. Vertico sorts by history position.


(provide 'init)

