#!/bin/bash
# probe: completion-candidates — stock shape of completion candidates.
# Run: make probe sh=completion-candidates
# Renders a sample list with stock display-completion-list and prints the
# buffer text and every completion--string property run: how the
# candidate name maps to what get-buffer would see. No UI, no config.
# Elisp payload pattern: heredoc to a temp file, stock batch Emacs -l.
set -u
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<'EOF'
(let ((out (get-buffer-create "*probe-out*")))
  (let ((standard-output out))
    (display-completion-list (list "*scratch*" "*Messages*" "foo.org")))
  (with-current-buffer out
    (message "--- buffer text ---")
    (message "%s" (buffer-string))
    (let ((pos (point-min)) (last nil) (n 0))
      (while (< pos (point-max))
        (let ((val (get-text-property pos 'completion--string)))
          (when (and val (not (equal val last)))
            (message "prop-run at %d: %S   get-buffer: %S" pos val (get-buffer val))
            (setq last val n (1+ n)))
          (setq pos (1+ pos))))
      (message "distinct strings: %d" n))))
EOF
emacs --batch -Q -l "$tmp"
