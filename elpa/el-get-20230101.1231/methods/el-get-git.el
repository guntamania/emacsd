;;; el-get --- Manage the external elisp bits and pieces you depend upon
;;
;; Copyright (C) 2010-2011 Dimitri Fontaine
;;
;; Author: Dimitri Fontaine <dim@tapoueh.org>
;; URL: http://www.emacswiki.org/emacs/el-get
;; GIT: https://github.com/dimitri/el-get
;; Licence: WTFPL, grab your copy here: http://sam.zoy.org/wtfpl/
;;
;; This file is NOT part of GNU Emacs.
;;
;; Install
;;     Please see the README.md file from the same distribution

(require 'cl-lib)
(require 'el-get-core)
(require 'el-get-recipes)
(require 'url-http)

(defcustom el-get-git-clone-hook nil
  "Hook run after git clone."
  :group 'el-get
  :type 'hook)

(defcustom el-get-git-shallow-clone nil
  "If t, then run git-clone with `--depth 1'."
  :group 'el-get
  :type 'boolean)

(defcustom el-get-git-known-smart-domains '("www.github.com" "www.bitbucket.org" "repo.or.cz" "git.sr.ht")
  "List of domains which are known to support shallow clone, el-get will not make
explicit checks for these"
  :group 'el-get
  :type 'list)

;; The following variables are declared here to silence the byte
;; compiler "reference to variable" warning. The package "url-http"
;; provides these variables.
(defvar url-http-content-type)
(defvar url-http-response-status)

(defun el-get-git-executable ()
  "Return git executable to use, or signal an error when not
found."
  (let ((git-executable (if (and (boundp 'magit-git-executable)
                                 (file-executable-p magit-git-executable))
                            magit-git-executable
                          (executable-find "git"))))
    (unless (and git-executable (file-executable-p git-executable))
      (error
       (concat "el-get-git-clone requires `magit-git-executable' to be set, "
               "or the binary `git' to be found in your PATH")))
    git-executable))

(defun el-get-git-url-from-known-smart-domains-p (url)
  "Check if URL belongs to known smart domains, it basically looks up the url's
domain in `el-get-git-known-smart-domains'

This is needed because some domains like bitbucket support shallow clone even
though they do not indicate this in their response headers see
`el-get-git-is-host-smart-http-p'"
  (let* ((host (el-get-url-host url))
         ;; Prepend www to domain, if it consists only of two components
         (prefix (when (= (length (split-string host "\\.")) 2)
                   "www.")))
    (member (concat prefix host) el-get-git-known-smart-domains)))

(defun el-get-git-is-host-smart-http-p (giturl)
  "Detect if the host supports shallow clones using http(s). GITURL is url to
the git repository, this function is intended to be used only with http(s)
urls. The function uses the approach described here
[http://stackoverflow.com/questions/9270488/]

Basically it makes a HEAD request and checks the Content-Type for 'smart' MIME
type. This approach does not work for some domains like `bitbucket', which do
not return 'smart' headers despite supporting shallow clones.

Other domains like `github' return 405 for HEAD and only respond to GET. In this
case, if HEAD doesn't respond with 200 or 304, GET is tried as well."
  (let ((url-request-method "HEAD")
        (req-url (format "%s%s/info/refs\?service\=git-upload-pack"
                         giturl
                         ;; The url may not end with ".git" in which case we
                         ;; need to add append ".git" to the url
                         (if (string-match "\\.git\\'" giturl)
                             ""
                           ".git")))
        (smart-content-type "application/x-git-upload-pack-advertisement")
        ;; according to https://www.git-scm.com/docs/http-protocol,
        ;; 200 and 304 are valid
        (valid-response-status-p
         (lambda (status) (or (= status 200) (= status 304))))
        (retry-with-get-p nil)
        (smart-p nil))

    (with-current-buffer (url-retrieve-synchronously req-url)
      (let ((valid-status-p
             (funcall valid-response-status-p url-http-response-status)))
        (setq retry-with-get-p (not valid-status-p))
        (setq smart-p (string= url-http-content-type smart-content-type))))

    (when retry-with-get-p
      (setq url-request-method "GET")
      (with-current-buffer (url-retrieve-synchronously req-url)
        (let ((valid-status-p
               (funcall valid-response-status-p url-http-response-status)))
          (unless valid-status-p
            (error "Unable to detect if %s is a smart HTTP host" giturl))
          (setq smart-p
                (and valid-status-p
                     (string= url-http-content-type smart-content-type))))))

    smart-p))

(defun el-get-git-shallow-clone-supported-p (url)
  "Check if shallow clone is supported for given URL"
  ;; All other protocols git, ssh and file support shallow clones
  (or (not (string-prefix-p "http" url))
      ;; Check if url belongs to one of known smart domains
      (el-get-git-url-from-known-smart-domains-p url)
      ;; If all else fails make an explicit call to check if shallow clone is
      ;; supported
      (el-get-git-is-host-smart-http-p url)))

(defun el-get-git-clone (package url post-install-fun)
  "Clone the given package following the URL."
  (let* ((git-executable (el-get-executable-find "git"))
         (pdir   (el-get-package-directory package))
         (pname  (el-get-as-string package))
         (name   (format "*git clone %s*" package))
         (source (el-get-package-def package))
         (branch (plist-get source :branch))
         (submodule-prop (plist-get source :submodule))
         ;; nosubmodule is true only if :submodules  is explicitly set to nil.
         (explicit-nosubmodule (and (plist-member source :submodule)
                                    (not submodule-prop)))
         (checkout (or (plist-get source :checkout)
                       (plist-get source :checksum)))
         (shallow (when (el-get-git-shallow-clone-supported-p url)
                    (el-get-plist-get-with-default source :shallow
                      el-get-git-shallow-clone)))
         (clone-args (append '("--no-pager" "clone")
                             (when shallow '("--depth" "1"))
                             (cond
                              ;; With :checkout, the "git checkout"
                              ;; command is a separate step, so don't
                              ;; do it during cloning.
                              (checkout '("--no-checkout"))
                              ;; With a specified branch, check that branch out
                              (branch (list "-b" branch))
                              ;; Otherwise, just checkout the default branch
                              (t nil))
                             (list url pname)))
         (ok     (format "Package %s installed." package))
         (ko     (format "Could not install package %s." package)))
    (el-get-insecure-check package url)

    (el-get-start-process-list
     package
     (list
      `(:command-name ,name
                      :buffer-name ,name
                      :default-directory ,el-get-dir
                      :program ,git-executable
                      :args ,clone-args
                      :message ,ok
                      :error ,ko)
      (when checkout
        (list :command-name (format "*git checkout %s*" checkout)
              :buffer-name name
              :default-directory pdir
              :program git-executable
              :args (list "--no-pager" "checkout" checkout)
              :message (format "git checkout %s ok" checkout)
              :error (format "Could not checkout %s for package %s" checkout package)))
      (unless explicit-nosubmodule
        (list :command-name "*git submodule update*"
              :buffer-name name
              :default-directory pdir
              :program git-executable
              :args (list "--no-pager" "submodule" "update" "--init" "--recursive")
              :message "git submodule update ok"
              :error "Could not update git submodules")))
     post-install-fun)))

(defun el-get-git-pull (package url post-update-fun)
  "git pull the package."
  (let* ((git-executable (el-get-executable-find "git"))
         (pdir (el-get-package-directory package))
         (name (format "*git pull %s*" package))
         (source (el-get-package-def package))
         (submodule-prop (plist-get source :submodule))
         ;; nosubmodule is true only if :submodules  is explicitly set to nil.
         (explicit-nosubmodule (and (plist-member source :submodule)
                                    (not submodule-prop)))
         (checkout (or (plist-get source :checkout)
                       (plist-get source :checksum)))
         ;; When dealing with a specific checkout, we cannot use
         ;; "pull", but must instead use "fetch" and then "checkout".
         (pull-args (list "--no-pager" (if checkout "fetch" "pull")))
         (ok   (format "Pulled package %s." package))
         (ko   (format "Could not update package %s." package)))
    (el-get-insecure-check package url)

    (el-get-start-process-list
     package
     `((:command-name ,name
                      :buffer-name ,name
                      :default-directory ,pdir
                      :program ,git-executable
                      :args ,pull-args
                      :message ,ok
                      :error ,ko)
       ,(when checkout
          (list :command-name (format "*git checkout %s*" checkout)
                :buffer-name name
                :default-directory pdir
                :program git-executable
                :args (list "--no-pager" "checkout" checkout)
                :message (format "git checkout %s ok" checkout)
                :error (format "Could not checkout %s for package %s" checkout package)))
       ,(unless explicit-nosubmodule
          `(:command-name "*git submodule update*"
                          :buffer-name ,name
                          :default-directory ,pdir
                          :program ,git-executable
                          :args ("--no-pager" "submodule" "update" "--init" "--recursive")
                          :message "git submodule update ok"
                          :error "Could not update git submodules")))
     post-update-fun)))

(defun el-get-git-compute-checksum (package)
  "Return the hash of the checked-out revision of PACKAGE."
  (let ((default-directory (el-get-package-directory package)))
    ;; We cannot simply check the recipe for `:type git' because it
    ;; could also be github, emacsmirror, or any other unknown git-ish
    ;; type. Instead, we check for the existence of a ".git" directory
    ;; in the package directory. A better approach might be to call
    ;; "git status" and check that it returns success.
    (cl-assert (file-directory-p ".git") nil
               "Package %s is not a git package" package)
    (with-temp-buffer
      (call-process (el-get-executable-find "git") nil '(t t) nil
                    "log" "--pretty=format:%H" "-n1")
      (buffer-string))))

(el-get-register-method :git
  :install #'el-get-git-clone
  :update #'el-get-git-pull
  :remove #'el-get-rmdir
  :install-hook 'el-get-git-clone-hook
  :compute-checksum #'el-get-git-compute-checksum)

(provide 'el-get-git)
