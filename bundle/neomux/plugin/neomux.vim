
noremap <Leader>sh :call OpenTerm()<CR>

let s:this_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let s:os = systemlist("uname -s")[0]
let s:arch = systemlist("uname -m")[0]

function! OpenTerm()
    let l:bin_folder = printf("%s/bin", s:this_folder)
    let l:platform_bin_folder = printf("%s/%s.%s.bin", s:this_folder, s:os, s:arch)

    " add bin folder to the *end* of the path so that nvr or other tools
    " installed by user will take precedence
    let $PATH=printf("%s:%s:%s", l:bin_folder, $PATH, l:platform_bin_folder)
    let $EDITOR=printf("%s/nmux", l:bin_folder)
    term
endfunction

function! WindowNumber()
    let str=tabpagewinnr(tabpagenr())
    return str
endfunction

let s:winjump_key = "<C-w>"
function! EnableWinJump(...)
    let l:key = a:0 > 0 ? a:1 : s:winjump_key
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

function! WinSwap(tgt)
    let src_win=winnr()
    let src_winbuf=bufnr("%")

    let dst_win=a:tgt
    execute dst_win . "wincmd w"
    let dst_buf=bufnr("%")

    execute "b!" . src_winbuf
    execute l:src_win . "wincmd w"
    execute "b!" . dst_buf
    execute l:dst_win . "wincmd w"
endfunction

let winswap_map_prefix = "<Leader>s"
for i in [1,2,3,4,5,6,7,8,9]
    execute printf('map %s%s :call WinSwap("%s")<CR>', winswap_map_prefix, i, i)
endfor

" Yank current buffer
map <Leader>by :let t:yanked_buffer=bufnr("%")<CR>:echo "Yanked buffer " . t:yanked_buffer<CR>
" Paste current buffer
map <Leader>bp :execute ":b" . t:yanked_buffer<CR>:echo "Pasted buffer " . t:yanked_buffer<CR>


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
