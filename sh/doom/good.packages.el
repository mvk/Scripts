;;; $DOOMDIR/packages.el -*- lexical-binding: t; no-byte-compile: t -*-

;; To install a package:
;;
;;   1. Declare them here in a 'package!' statement,
;;   2. Run 'doom sync' in the shell,
;;   3. Restart Emacs.
;;
;; Use 'C-h f package\!' to look up documentation for the 'package!' macro.


;; Standard MELPA/ELPA/emacsmirror packages:
;; tidal cycles
(package! tidal)

;; Nu-shell mode
(package! nushell-mode)

;; Mermaid diagrams support
(package! mermaid-mode)

;; Org-Mode Mermaid support
(package! ob-mermaid)


;; Packages define with a recipe:


(package! pkg
  :recipe (:host github
           :repo "repo1"
           :branch "br1"
           :nonrecursive t
           :files ("folder/file.el"
                   "src/lisp/*.el")
           :build (:compile
                   :not native-compile
                   :autoloads t
                   (:custom (("make" "all")
                             ("make" "info"))))))


;; Disbale packages included with Doom:

;; If you`d like to disable a package included with Doom, you can do so here
;; with the ':disable' property:
;; (package! builtin-package :disable t)

;; Pinned packages:

;; Use ':pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")



;; Unpinned packages (usually outdated Doom packages):

;; Doom`s packages are pinned to a specific commit and updated from release to
;; release. The 'unpin!' macro allows you to unpin single packages...
;; (unpin! pinned-package)
;; ...or multiple packages
;; (unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;; (unpin! t)

