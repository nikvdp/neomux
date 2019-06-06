""" TODO delete
colorscheme shine

" set leader key to ',' intead of '\'
let g:mapleader=","
""" TODO /delete

noremap <Leader>sh :call OpenTerm()<CR>

let s:this_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let s:os = systemlist("uname --kernel-name")[0]
let s:arch = systemlist("uname --machine")[0]

function! OpenTerm()
    let l:bin_folder = printf("%s/bin", s:this_folder)
    let l:platform_bin_folder = printf("%s/%s.%s.bin", s:this_folder, s:os, s:arch)

    " add bin folder to the *end* of the path so that nvr or other tools
    " installed by user will take precedence
    let $PATH=printf("%s:%s:%s", l:bin_folder, $PATH, l:platform_bin_folder)
    term
endfunction

function! WindowNumber()
    let str=tabpagewinnr(tabpagenr())
    return str
endfunction


" TODO: test airline works as expected
let win_num_status = '∥ W:[%{WindowNumber()}] ∥'
if exists("g:airline_theme")
    let g:airline_section_z = win_num_status . g:airline_section_z
else
    let &statusline = &statusline . win_num_status
endif
