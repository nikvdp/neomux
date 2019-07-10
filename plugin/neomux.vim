if exists('g:neomux_loaded') && g:neomux_loaded
    finish
endif
let g:neomux_loaded = 1

" set script-wide vars
let s:this_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let s:os = systemlist("uname -s")[0]
let s:arch = systemlist("uname -m")[0]

function! s:NeomuxMain()
    " Set default key bindings if no user defined maps present
    if !exists('g:neomux_start_term_map') | let g:neomux_start_term_map = '<Leader>sh' | endif
    if !exists('g:neomux_start_term_split_map') | let g:neomux_start_term_split_map = '<C-w>t' | endif
    if !exists('g:neomux_start_term_vsplit_map') | let g:neomux_start_term_vsplit_map = '<C-w>T' | endif
    if !exists('g:neomux_winjump_map_prefix') | let g:neomux_winjump_map_prefix = "<C-w>" | endif
    if !exists('g:neomux_winswap_map_prefix') | let g:neomux_winswap_map_prefix =  "<Leader>s" | endif
    if !exists('g:neomux_yank_buffer_map') | let g:neomux_yank_buffer_map = "<Leader>by" | endif
    if !exists('g:neomux_paste_buffer_map') | let g:neomux_paste_buffer_map = '<Leader>bp' | endif
    " Pnemonic: size-fix. Resize terminal window back to proper size
    if !exists('g:neomux_term_sizefix_map') | let g:neomux_term_sizefix_map = '<Leader>sf'  | endif
    if !exists('g:neomux_win_num_status') | let g:neomux_win_num_status = '∥ W:[%{WindowNumber()}] ∥' | endif
    if !exists('g:neomux_exit_term_mode_map') | let g:neomux_exit_term_mode_map = '<C-s>' | endif
    if !exists('g:neomux_default_shell') | let g:neomux_default_shell = "" | endif
    if !exists('g:neomux_dont_fix_term_ctrlw_map') | let g:neomux_dont_fix_term_ctrlw_map = 0 | endif
    if !exists('g:neomux_no_term_autoinsert') | let g:neomux_no_term_autoinsert = 0 | endif

    command! Neomux call NeomuxTerm()

    " Put window number labels in statusline
    " TODO: test airline works as expected
    if exists("g:airline_theme") 
        if ! exists('g:airline_section_z')
            let g:airline_section_z = g:neomux_win_num_status
        else
            let g:airline_section_z = g:airline_section_z . g:neomux_win_num_status
        endif
    else
		if &statusline !~ g:neomux_win_num_status
			let &statusline = &statusline . g:neomux_win_num_status
		endif
    endif

    " Make getting out of terminal windows work the same way it does for every
    " other window. If you need to send a <C-w> keystroke to the term window,
    " use `:call NeomuxSendCtrlW()`
    if g:neomux_dont_fix_term_ctrlw_map == 0
        tnoremap <C-w> <C-\><C-n><C-w>
    endif

    " Automatically start insert mode when entering a terminal buffer
    " from: https://github.com/neovim/neovim/issues/8816#issuecomment-410502364
    if g:neomux_no_term_autoinsert == 0
        au BufEnter * if &buftype == 'terminal' | :startinsert | endif
        autocmd TermOpen term://* startinsert
    endif

    " leave term buffer around after process ends, from:
    " https://vi.stackexchange.com/questions/17816/solved-ish-neovim-dont-close-terminal-buffer-after-process-exit
    autocmd TermClose *  call feedkeys("\<C-\>\<C-n>")

    " exit term mode with g:neomux_exit_term_mode_map (<C-s> by default)
    if !exists('g:neomux_no_exit_term_map')
        execute printf('tnoremap %s <C-\><C-n>', g:neomux_exit_term_mode_map)
        execute printf('inoremap %s <Esc>', g:neomux_exit_term_mode_map)
    endif

    " set neomux start term map
    execute printf("noremap %s :Neomux<CR>", g:neomux_start_term_map)

    " set winswap mappings
    for i in [1,2,3,4,5,6,7,8,9]
        execute printf('map %s%s :call WinSwap("%s")<CR>', g:neomux_winswap_map_prefix, i, i)
    endfor

    call EnableWinJump()

    execute printf('noremap %s :split<CR>:call NeomuxTerm()<CR>', g:neomux_start_term_split_map)
    execute printf('noremap %s :vsplit<CR>:call NeomuxTerm()<CR>', g:neomux_start_term_vsplit_map)
    execute printf('tnoremap %s <C-\><C-n>:split<CR>:call NeomuxTerm()<CR>', g:neomux_start_term_split_map)
    execute printf('tnoremap %s <C-\><C-n>:vsplit<CR>:call NeomuxTerm()<CR>', g:neomux_start_term_vsplit_map)

    " Yank current buffer
    execute printf('map %s :call NeomuxYankBuffer()<CR>', g:neomux_yank_buffer_map)
    " Paste current buffer
    execute printf('map %s :call NeomuxPasteBuffer()<CR>', g:neomux_paste_buffer_map)

    " term size-fix map
    execute printf('noremap %s <C-\><C-n><Esc>:call NeomuxResizeWindow()<CR>', g:neomux_term_sizefix_map)
endfunction

function! NeomuxYankBuffer(...)
    let l:register = a:0 > 0 ? a:1 : "default"

    if ! exists('s:yanked_buffers')
        let s:yanked_buffers = {}
    endif

    stopinsert
    let s:yanked_buffers[l:register] = bufnr("%")
    echo printf("Yanked buffer #%s to register '%s'.", s:yanked_buffers[l:register], l:register)
endfunction

function! NeomuxPasteBuffer(...)
    let l:register = a:0 > 0 ? a:1 : "default"
    stopinsert
    execute printf(":b!%s", s:yanked_buffers[l:register])
    echo printf("Pasted buffer #%s from register '%s'", s:yanked_buffers[l:register], l:register)
endfunction

function! NeomuxResizeWindow()
    10 wincmd <
    10 wincmd -
    10 wincmd +
    10 wincmd >
endfunction

function! NeomuxTerm(...)
    if a:0 > 0
        let l:term_cmd = a:1
    endif

    let l:bin_folder = printf("%s/bin", s:this_folder)
    let l:platform_bin_folder = printf("%s/%s.%s.bin", s:this_folder, s:os, s:arch)

    " add bin folder to the *end* of the path so that nvr or other tools
    " installed by user will take precedence
    let $PATH=printf("%s:%s:%s", l:bin_folder, $PATH, l:platform_bin_folder)
    let $EDITOR=printf("%s/nmux", l:bin_folder)

    if exists("l:term_cmd")
        execute printf("term! %s", l:term_cmd)
    else
        if len(g:neomux_default_shell) > 0
            execute printf("term! %s", g:neomux_default_shell)
		elseif len($SHELL) > 0
            term! $SHELL
		else
            term!
        endif
    endif
endfunction

function! WindowNumber()
    return tabpagewinnr(tabpagenr())
endfunction

function! EnableWinJump(...)
    " Mappings to jump directly to windows by window number
    " adapted from this SO post: http://stackoverflow.com/questions/6403716/shortcut-for-moving-between-vim-windows
    let l:key = a:0 > 0 ? a:1 : g:neomux_winjump_map_prefix
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
    " hidden needs to be on to prevent buffers from geting deleted while it's
    " temporarily offscreen
    let l:orig_hidden = &hidden
    set hidden

    let l:dst_win=a:tgt
    let l:src_win=winnr()

    noautocmd silent! call NeomuxYankBuffer("swap_src")

    noautocmd execute l:dst_win . "wincmd w"
    noautocmd silent! call NeomuxYankBuffer("swap_dst")
    noautocmd silent! call NeomuxPasteBuffer("swap_src")
    noautocmd call NeomuxResizeWindow()

    noautocmd execute l:src_win . "wincmd w"
    noautocmd silent! call NeomuxPasteBuffer("swap_dst")
    noautocmd execute l:dst_win . "wincmd w"
    noautocmd call NeomuxResizeWindow()

    let &hidden = l:orig_hidden
endfunction

function! NeomuxSendCtrlW()
    call chansend(b:terminal_job_id, "")
endfunction

function! NeomuxSend(keys)
    call chansend(b:terminal_job_id, a:keys)
endfunction


call s:NeomuxMain()

