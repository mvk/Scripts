#!/usr/bin/env bash

# Copyright (c) 2016 Max Kovgan <maxk@devopsent.biz>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy 
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

MY_VIMRC="${HOME}/.vimrc"
MY_VIMDIR="${HOME}/.vim"
SCHEMA="git"
GIT_SRV="github.com"
VIM_PLUGINS_TO_INSTALL=(
    "scrooloose/syntastic"
    "scrooloose/nerdtree"
    "majutsushi/tagbar"
    "chase/vim-ansible-yaml"
    "mitsuhiko/vim-jinja"
    "elzr/vim-json"
    "plasticboy/vim-markdown"
    "PProvost/vim-ps1"
    "sukima/xmledit"
)

setup_git_url() {
    local \
        repository \
        server \
        schema \
        separator \
        username
    repository="${1?"cannot continue without git repository name in the format TEAM/REPOSITORY"}"
    schema="${2:-"${SCHEMA}"}"
    server="${3:-"${GIT_SRV}"}"
    username="${4:-"git"}"
    separator="/"
    suffix="/"
    result="${schema}://"
    if [[ "${schema}" = "git" ]]; then
        result+="${username}@"
        separator=":"
        suffix=".git"
    fi
    result+="${server}${separator}${repository}${suffix}"
    echo "${result}"
    return 0
}

install_pathogen() {
    echo "stage: Install pathogen"
    mkdir -p "${MY_VIMDIR}"/{bundle,autoload}
    curl -LSso "${MY_VIMDIR}/autoload/pathogen.vim" "https://tpo.pe/pathogen.vim"
}

install_plugins() {
    local \
        schema \
        plugins \
        plugin
    schema="${1:-"${SCHEMA}"}"
    plugins=(${@:2})
    if [[ "${#plugins[@]}" -lt 1 ]]; then
        plugins+=(${VIM_PLUGINS_TO_INSTALL[@]})
    fi
    echo "stage: Install plugins"
    cd "${MY_VIMDIR}/bundle"
    for plugin in "${plugins[@]}"; do
        plugin_dir="${plugin##*/}"
        if [[ -d "${plugin_dir}" ]]; then
            echo "plugin ${plugin} already installed. Updating it"
            cd "${plugin_dir}"
            git fetch origin; git pull --ff-only origin master
            cd ../
            continue
        fi
        url="$( setup_git_url "${plugin}" "${schema}" )"
        echo "getting ${plugin} from ${url}"
        git clone "${url}"
    done
}

install_vimrc() {
    echo "stage: install ${MY_VIMRC}"
    if [[ -r "${MY_VIMRC}" ]]; then
        TS="$( date +%s )"
        echo "existing ${MY_VIMRC} found => Backing it up as ${MY_VIMRC}.${TS}"
        mv "${MY_VIMRC}" "${MY_VIMRC}.${TS}"
    fi
    cat > "${MY_VIMRC}" << _EOF
" contents of minimal .vimrc
execute pathogen#infect()
syntax on
filetype plugin indent on
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
set listchars=tab:→\\ ,trail:·
set modeline

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
map <silent> <F3> :NERDTreeToggle<CR>
map <silent> <F4> :set invnumber<CR>
map <silent> <F6> :SyntasticToggleMode<CR>
map <silent> <F8> :set list!<CR>
if has("gui_running")
  if has("gui_gtk2")
    set guifont=Inconsolata\\ Medium\\ 16
  elseif has("gui_gtk3")
    set guifont=Inconsolata\\ Medium\\ 16
  elseif has("gui_photon")
    set guifont=Inconsolate\\ Medium:s16
  elseif has("gui_kde")
    set guifont=Courier\\ New/11/-1/5/50/0/0/0/1/0
  elseif has("x11")
    set guifont=-*-courier-medium-r-normal-*-*-180-*-*-m-*-*
  else
    set guifont=Inconsolata_Medium:h16:cDEFAULT
  endif
endif

" Indent Python in the Google way.
setlocal indentexpr=GetGooglePythonIndent(v:lnum)
let s:maxoff = 50 " maximum number of lines to look backwards.
function GetGooglePythonIndent(lnum)
  " Indent inside parens.
  " Align with the open paren unless it is at the end of the line.
  " E.g.
  "   open_paren_not_at_EOL(100,
  "                         (200,
  "                          300),
  "                         400)
  "   open_paren_at_EOL(
  "       100, 200, 300, 400)
  call cursor(a:lnum, 1)
  let [par_line, par_col] = searchpairpos('(\\|{\\|\\[', '', ')\\|}\\|\\]', 'bW',
        \\ "line('.') < " . (a:lnum - s:maxoff) . " ? dummy :"
        \\ . " synIDattr(synID(line('.'), col('.'), 1), 'name')"
        \\ . " =~ '\\\\(Comment\\\\|String\\\\)\$'")
  if par_line > 0
    call cursor(par_line, 1)
    if par_col != col("\$") - 1
      return par_col
    endif
  endif
  " Delegate the rest to the original function.
  return GetPythonIndent(a:lnum)
endfunction

let pyindent_nested_paren="&sw*2"
let pyindent_open_paren="&sw*2"

let g:syntastic_python_pylint_rcfile='~/pylintrc' 

set tabstop=4 shiftwidth=4 expandtab
_EOF

}

main() {
    local \
        schema
    schema="${1}"
    pushd "${PWD}"
    install_pathogen
    install_plugins "${schema}" "${VIM_PLUGINS_TO_INSTALL[@]}"
    install_vimrc
    popd
}


main "${@}"
exit $?
