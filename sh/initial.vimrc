" contents of minimal .vimrc
scriptencoding utf-8
set encoding=utf-8
packloadall
syntax on
filetype plugin indent on
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
set listchars=tab:→\ ,trail:·
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
    let &guiFont = "Inconsolata Medium 16"
  elseif has("gui_gtk3")
    let &guiFont = "Inconsolata Medium 16"
  elseif has("gui_photon")
    let &guiFont = "Inconsolate Medium:s16"
  elseif has("gui_kde")
    let &guiFont = "Courier New/11/-1/5/50/0/0/0/1/0"
  elseif has("x11")
    let &guiFont = "-*-courier-medium-r-normal-*-*-180-*-*-m-*-*"
  else
    let &guiFont = "Inconsolata_Medium:h16:cDEFAULT"
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
  let [par_line, par_col] = searchpairpos('(\|{\|\[', '', ')\|}\|\]', 'bW',
        \ "line('.') < " . (a:lnum - s:maxoff) . " ? dummy :"
        \ . " synIDattr(synID(line('.'), col('.'), 1), 'name')"
        \ . " =~ '\\(Comment\\|String\\)\$'")
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

set tabstop=4 shiftwidth=4 softtabstop=4 expandtab
