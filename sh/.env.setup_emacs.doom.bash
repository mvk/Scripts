## Flavor:
EMACS_FLAVOR="doom"
## Repository
EMACS_CFG_REPO="https://github.com/doomemacs/core"
## Configuration directory
EMACS_CFG_DIR="${HOME}/.config/emacs"
## 3-tuples for template rendering
EMACS_CFG_FILES=()
# shellcheck disable=SC2034
EMACS_CFG_FILES["init"]="${HOME}/config/doom/init.el,${PWD}/doom/init.el.j2,${PWD}/doom/init.context.yaml"
EMACS_CFG_FILES["config"]="${HOME}/config/doom/config.el,${PWD}/doom/config.el.j2,${PWD}/doom/config.context.yaml"
EMACS_CFG_FILES["packages"]="${HOME}/config/doom/packages.el,${PWD}/doom/packages.el.j2,${PWD}/doom/packages.context.yaml"
