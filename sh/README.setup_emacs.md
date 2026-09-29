# setup_emacs.sh

## Supported OS

- Fedora 44
- systemd

## About

This script sets up emacs covering the following:

- Installs system packages
- Creates config folders
- Sets up Common Lisp (SBCL needs to move actually)
- Configures your emacs (using either spacemacs or doom)
- Sets up Emacs server
- Sets up Emacs Client and Editor (standalone) `.desktop` shortcuts
- Creates a keyboard shortcut for KDE/Plasma `Ctrl+Meta+E` to launch Emacs Client

## Setting up

1. Choose `EMACS_FLAVOR` either:
  - `doom` (is supported better)
  - `spacemacs`
1. Set environment:
```sh
EMACS_FLAVOR="<your value>"
```
1. Create the symlink to the correct file:
```sh
ln -s ".env.setup_emcas.${EMACS_FLAVOR}.bash" ".env.setup_emacs.bash"
```
1. Copy the context example files:
```sh
for f in init config packages; do
  cp "${EMACS_FLAVOR}"/{example.,}"${f}.context.yaml"
done
```
1. Edit the files `"${EMACS_FLAVOR}/{init,config,packages}.context.yml` add the packages, initializations, etc.
1. Run the script:
```sh
./setup_emacs.sh
```

## Debugging

### Increase logging level

```sh
SCRIPT_DEBUG=1 ./setup_emacs.sh
```


### Control which steps are skipped

You can control which `setup_emacs.sh` steps run via:
```sh
"$(uname -s).env.setup_emacs.bash"
```

By removing commented steps with `*_SKIP=1`

