## Flavor:
EMACS_FLAVOR="spacemacs"
## Repository
EMACS_CFG_REPO="https://github.com/syl20bnr/spacemacs"
## Configuration directory
EMACS_CFG_DIR="${HOME}/.emacs.d"
## 3-tuples for template rendering
EMACS_CFG_FILES=()
# shellcheck disable=SC2034
EMACS_CFG_FILES["config"]="${HOME}/.spacemacs,${PWD}/${EMACS_FLAVOR}/.spacemacs.j2,${PWD}/${EMACS_FLAVOR}/.spacemacs.context.yaml"
