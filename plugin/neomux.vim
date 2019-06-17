if exists('g:neomux_loaded') && g:neomux_loaded
	finish
endif
let g:neomux_loaded = 1

command! Neomux call NeomuxTerm()

" Set default key bindings if no user defined maps present
if !exists('g:neomux_start_term_map') | let g:neomux_start_term_map = '<Leader>sh' | endif
if !exists('g:neomux_winjump_map_prefix') | let g:neomux_winjump_map_prefix = "<C-w>" | endif
if !exists('g:neomux_winswap_map_prefix') | let g:neomux_winswap_map_prefix =  "<Leader>s" | endif
if !exists('g:neomux_yank_buffer_map') | let g:neomux_yank_buffer_map = "<Leader>by" | endif
if !exists('g:neomux_paste_buffer_map') | let g:neomux_paste_buffer_map = '<Leader>bp' | endif
" Pnemonic: size-fix. Resize terminal window back to proper size
if !exists('g:neomux_term_sizefix_map') | let g:neomux_term_sizefix_map = '<Leader>sf'  | endif
if !exists('g:neomux_win_num_status') | let g:neomux_win_num_status = '∥ W:[%{WindowNumber()}] ∥' | endif
if !exists('g:neomux_exit_term_mode_map') | let g:neomux_exit_term_mode_map = '<C-s>' | endif


" Make getting out of terminal windows work the same way it does for every
" other window. If you really need to input <C-w> to a term window, use
" `:call NeomuxSendCtrlW()`
if !exists('g:neomux_dont_fix_term_ctrlw_map')
	tnoremap <C-w> <C-\><C-n><C-w>
endif

if !exists('g:neomux_no_exit_term_map')
	" exit term mode
	execute printf('tnoremap %s <C-\><C-n>', g:neomux_exit_term_mode_map)
	execute printf('inoremap %s <Esc>', g:neomux_exit_term_mode_map)
endif

" set neomux start term map
execute printf("noremap %s :Neomux<CR>", g:neomux_start_term_map)

let s:this_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let s:os = systemlist("uname -s")[0]
let s:arch = systemlist("uname -m")[0]

function! NeomuxTerm()
    let l:bin_folder = printf("%s/bin", s:this_folder)
    let l:platform_bin_folder = printf("%s/%s.%s.bin", s:this_folder, s:os, s:arch)

    " add bin folder to the *end* of the path so that nvr or other tools
    " installed by user will take precedence
    let $PATH=printf("%s:%s:%s", l:bin_folder, $PATH, l:platform_bin_folder)
    let $EDITOR=printf("%s/nmux", l:bin_folder)
    term!
endfunction

function! WindowNumber()
    let str=tabpagewinnr(tabpagenr())
    return str
endfunction

function! EnableWinJump(...)
    let l:key = a:0 > 0 ? a:1 : g:neomux_winjump_map_prefix
    " Jump directly to different windows
    " adapted from this SO post: http://stackoverflow.com/questions/6403716/shortcut-for-moving-between-vim-windows
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
    let l:src_win=winnr()
    let l:src_winbuf=bufnr("%")

    let l:dst_win=a:tgt
    execute l:dst_win . "wincmd w"
    let l:dst_buf=bufnr("%")

    execute "b!" . l:src_winbuf
    execute l:src_win . "wincmd w"
    execute "b!" . l:dst_buf
    execute l:dst_win . "wincmd w"
endfunction

for i in [1,2,3,4,5,6,7,8,9]
    execute printf('map %s%s :call WinSwap("%s")<CR>', g:neomux_winswap_map_prefix, i, i)
endfor


" Yank current buffer
execute printf('map %s :let t:yanked_buffer=bufnr("%%")<CR>:echo "Yanked buffer " . t:yanked_buffer<CR>', g:neomux_yank_buffer_map)
" Paste current buffer
execute printf('map %s :execute ":b" . t:yanked_buffer<CR>:echo "Pasted buffer " . t:yanked_buffer<CR>', g:neomux_paste_buffer_map)

function! NeomuxSendCtrlW()
    call chansend(b:terminal_job_id, "")
endfunction

function! NeomuxSend(keys)
    call chansend(b:terminal_job_id, a:keys)
endfunction

call EnableWinJump()

execute printf('map %s <Esc><C-j><C-k><C-h><C-l>', g:neomux_term_sizefix_map)

" TODO: test airline works as expected
if exists("g:airline_theme")
    let g:airline_section_z = g:neomux_win_num_status . g:airline_section_z
else
    let &statusline = &statusline . g:neomux_win_num_status
endif
