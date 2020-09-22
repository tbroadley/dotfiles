execute pathogen#infect()

set number relativenumber

autocmd BufWritePre * :%s/\s\+$//e

set expandtab
set shiftwidth=2
set softtabstop=2

let g:workman_normal_qwerty = 1

set rtp+=~/.fzf

noremap <C-N> :GFiles<CR>
