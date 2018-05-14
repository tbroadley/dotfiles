execute pathogen#infect()

set number relativenumber

autocmd BufWritePre * :%s/\s\+$//e
