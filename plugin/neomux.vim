if ! has("nvim")
    finish
endif
if exists('g:neomux_loaded') && g:neomux_loaded
    finish
endif


let g:neomux_loaded = 1

" set script-wide vars
let s:this_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let s:os = systemlist("uname -s")[0]
let s:arch = systemlist("uname -m")[0]
let s:bin_folder = printf("%s/bin", s:this_folder)
let s:platform_bin_folder = printf("%s/%s.%s.bin", s:this_folder, s:os, s:arch)

" Set PATH and EDITOR vars for sub by subshells/processes
" TODO: make this configurable
" add bin folder to the *end* of the path so that nvr or other tools
" installed by user will take precedence
let $PATH=printf("%s:%s:%s", s:bin_folder, $PATH, s:platform_bin_folder)
let $EDITOR=printf("%s/nmux", s:bin_folder)

function! s:NeomuxMain()
    " Set default key bindings if no user defined maps present
    " TODO: use a dict of vars and defaults and iterate through it, below is
    "       getting unwieldy. maybe use lua?
    if !exists('g:neomux_start_term_map') | let g:neomux_start_term_map = '<Leader>sh' | endif
    if !exists('g:neomux_start_term_split_map') | let g:neomux_start_term_split_map = '<C-w>t' | endif
    if !exists('g:neomux_start_term_vsplit_map') | let g:neomux_start_term_vsplit_map = '<C-w>T' | endif
    if !exists('g:neomux_winjump_map_prefix') | let g:neomux_winjump_map_prefix = "<C-w>" | endif
    " neomux_enable_set_win_to_cur_pos is experimental, only enable if requested 
    if exists('g:neomux_enable_set_win_to_cur_pos')
        if !exists('g:neomux_set_win_to_cur_pos_prefix')
            let g:neomux_set_win_to_cur_pos_prefix = "<Leader>vp"
        endif
        call NeomuxEnableSetWinToCurPosMaps()
    endif
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

    call NeomuxAddWinNumLabels()

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

    if exists('g:neomux_enable_set_win_to_cur_pos')
        call EnableWinJump()
    endif

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

function! NeomuxSetWinToCurrentPos(tgt_win)
    let l:cur_pos = { "buf": bufnr("%"), "line": line("."), "col": col(".") }
    stopinsert
    execute printf("%swincmd w", a:tgt_win) 
    execute printf(":b!%s", l:cur_pos.buf)

    execute l:cur_pos.line
    normal 0 
    execute printf("normal %sl", l:cur_pos.col - 1)
    stopinsert
endfunction

function! NeomuxYankBuffer(...)
    let l:register = a:0 > 0 ? a:1 : "default"

    if ! exists('s:yanked_buffers')
        let s:yanked_buffers = {}
    endif

    stopinsert
    let s:yanked_buffers[l:register] = { "buf": bufnr("%"), "line": line("."), "col": col(".") }
    echo printf("Yanked buffer #%s to register '%s'.", s:yanked_buffers[l:register].buf, l:register)
endfunction

function! NeomuxPasteBuffer(...)
    let l:register = a:0 > 0 ? a:1 : "default"
    stopinsert
    execute printf(":b!%s", s:yanked_buffers[l:register].buf)
    execute s:yanked_buffers[l:register].line
    normal 0 
    execute printf("normal %sl", s:yanked_buffers[l:register].col - 1)
    echo printf("Pasted buffer #%s from register '%s'", s:yanked_buffers[l:register].buf, l:register)
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

function! NeomuxEnableSetWinToCurPosMaps(...)
    " Mappings to set ANOTHER window to the current win's buffer and cursor
    " position
    let l:key = a:0 > 0 ? a:1 : g:neomux_set_win_to_cur_pos_prefix
    for i in [1,2,3,4,5,6,7,8,9]
        execute printf('nnoremap %s%s <cmd>call NeomuxSetWinToCurrentPos(%s)<CR>', l:key, l:i, l:i)
        if has("nvim")
            execute printf('tnoremap %s%s <C-\><C-n><cmd>call NeomuxSetWinToCurrentPos(%s)<CR>', l:key, l:i, l:i)
        endif
        let l:i = l:i + 1
    endfor
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
    call NeomuxSendKeys("")
endfunction

function! NeomuxSend(keys)
    " compatibility shim, will be removed in future versions.
    " This temporary shim is provided in case 3rd party code is still calling `NeomuxSend()`
    echom "`NeomuxSend()` is deprecated! Please use `NeomuxSendKeys()` instead."
    call NeomuxSendKeys(a:keys)
endfunction

function! NeomuxSendKeys(keys)
    call chansend(b:terminal_job_id, a:keys)
endfunction

function! NeomuxAddWinNumLabels()
    " Put window number labels in statusline

    if &runtimepath =~ 'airline' && exists('*airline#parts#define') 
        " There appears to be a bug in airline's terminal extension that causes the
        " window numbers to disappear from terminal windows when the windows lose
        " focus. I've opened an issue with airline here:
        "   https://github.com/vim-airline/vim-airline/issues/2249
        " In the meantime, workaround by disabling airline's terminal extension 
        let g:airline#extensions#term#enabled = 0

        function! NeomuxAirlineHelper(...)
            let w:airline_section_z = g:airline_section_z . " " . g:neomux_win_num_status
            " let g:airline_variable_referenced_in_statusline = 'foo'
        endfunction
        call airline#add_statusline_func('NeomuxAirlineHelper')

    elseif &runtimepath =~ 'lualine'
        " TODO: consider automatically updating lualine to include neomux
        " window 
    else
        if &statusline !~ g:neomux_win_num_status
            let &statusline = &statusline . g:neomux_win_num_status
        endif
    endif

endfunction


call s:NeomuxMain()

