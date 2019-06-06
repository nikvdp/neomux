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

function! EnableWinJump(...)
    let l:key="<C-w>"
    if a:0 > 0
        let l:key = a:1
    endif
    " Jump directly to different windows
    " from this SO post: http://stackoverflow.com/questions/6403716/shortcut-for-moving-between-vim-windows
    let i = 1
    while i <= 9
        execute printf('nnoremap %s%s :%swincmd w<CR>', l:key, i, i)
        if has("nvim")
            execute printf('tnoremap %s%s <C-\><C-n>:%swincmd w<CR>', l:key, i, i)
        endif
        let i = i + 1
    endwhile
endfunction

" TODO: replicate window swap
nnoremap <silent> <leader>ww :call WindowSwap#EasyWindowSwap()<CR>

" Yank current buffer
map <Leader>by :let s:yanked_buffer=bufnr("%")<CR>:echo "Yanked buffer " . s:yanked_buffer<CR>
" Paste current buffer
map <Leader>bp :execute ":b" . s:yanked_buffer<CR>:echo "Pasted buffer " . s:yanked_buffer<CR>

" Direct window swap mappings (,ww is swap windows)
map <Leader>s1 :let s:buffer_a=bufnr("%")<CR><C-W>1:let s:buffer_b=bufnr("%")<CR>:execute ":b" . s:buffer_a<CR><C-w><C-w>:execute ":b" . s:buffer_b<CR><C-w><C-w>
map <Leader>s2 ,ww<C-W>2,ww
map <Leader>s3 ,ww<C-W>3,ww
map <Leader>s4 ,ww<C-W>4,ww
map <Leader>s5 ,ww<C-W>5,ww
map <Leader>s6 ,ww<C-W>6,ww
map <Leader>s7 ,ww<C-W>7,ww
map <Leader>s8 ,ww<C-W>8,ww
map <Leader>s9 ,ww<C-W>9,ww

call EnableWinJump()

" Pnemonic: size-fix. Resize terminal window back to proper size
map <Leader>sf <Esc><C-j><C-k><C-h><C-l>

" TODO: test airline works as expected
let win_num_status = '∥ W:[%{WindowNumber()}] ∥'
if exists("g:airline_theme")
    let g:airline_section_z = win_num_status . g:airline_section_z
else
    let &statusline = &statusline . win_num_status
endif
