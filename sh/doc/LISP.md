# Install SBCL

## requirements:

1. supported os
2. installed `minijinja-cli`

## supports:

1. Linux
  - Fedora/RedHat

## running:
```shell 
./setup_sbcl.sh
``` 

### structure:

What the script does:

1. installs system packages
2. pulls/clones spacemacs
3. downloads+installs quicklisp
4. customizes ~/.spacemacs

## development/changes

### updating

The `~/.spacemacs` file is generated from the template `.spacemacs.j2`, its context is `.spacemacs.context.yaml`
Naturally, if you want to customize `~/.spacemacs`, you should edit `.spacemacs.context.yaml` and occasionally the template

### logging/debugging

You can run the script using: `SCRIPT_DEBUG=1 ./setup_sbcl.sh`

This will increase verbosity and print all `log.debug` messages

