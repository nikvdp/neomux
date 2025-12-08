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

if !isdirectory(s:bin_folder)
    call mkdir(s:bin_folder, 'p')
endif

" Set PATH and EDITOR vars for sub by subshells/processes
" TODO: make this configurable
" add bin folder to the *end* of the path so that nvr or other tools
" installed by user will take precedence
let $PATH=printf("%s:%s", s:bin_folder, $PATH)
let $EDITOR=printf("%s/nmux", s:bin_folder)

" Set NVIM socket path for nvr and other tools
" Neovim 0.7.2+ uses $NVIM, older versions use $NVIM_LISTEN_ADDRESS
let $NVIM = v:servername
let $NVIM_LISTEN_ADDRESS = v:servername

let s:nvr_warn_messages = []

command! -nargs=0 NeomuxInstallNvr call s:InstallNvrBinary(1)

function! s:WarnOnce(msg) abort
    if index(s:nvr_warn_messages, a:msg) >= 0
        return
    endif
    call add(s:nvr_warn_messages, a:msg)
    echohl WarningMsg
    echom 'neomux: ' . a:msg
    echohl None
endfunction

function! s:DetectPlatform() abort
    if has('macunix')
        let l:os = 'darwin'
    elseif has('unix')
        let l:os = 'linux'
    else
        return {}
    endif

    let l:uname = tolower(trim(system('uname -m')))
    if v:shell_error
        return {}
    endif

    if l:uname ==# 'x86_64' || l:uname ==# 'amd64'
        let l:arch = 'amd64'
    elseif l:uname ==# 'arm64' || l:uname ==# 'aarch64'
        let l:arch = 'arm64'
    elseif l:uname =~# 'armv7'
        let l:arch = 'armv7'
    else
        return {}
    endif

    return {'asset_os': l:os, 'asset_arch': l:arch}
endfunction

function! s:ComposeAssetName(tag, platform) abort
    " Strip 'v' prefix from tag (e.g., v0.0.4 -> 0.0.4) to match goreleaser's {{ .Version }}
    let l:version = substitute(a:tag, '^v', '', '')
    return printf('nvr-go_%s_%s_%s.tar.gz', l:version, a:platform.asset_os, a:platform.asset_arch)
endfunction

function! s:LocalNvrPath() abort
    return s:bin_folder . '/nvr'
endfunction

function! s:SetExecutable(path) abort
    if exists('*setfperm')
        call setfperm(a:path, 'rwxr-xr-x')
    elseif has('unix')
        call system('chmod 755 ' . shellescape(a:path))
    endif
endfunction

function! s:InstallNvrBinary(force) abort
    if executable('nvr')
        return
    endif

    let l:target = s:LocalNvrPath()
    if filereadable(l:target)
        call s:SetExecutable(l:target)
        return
    endif

    if !exists('*json_decode')
        call s:WarnOnce('json_decode() is required to parse GitHub release metadata. Update Vim/Neovim or install nvr manually.')
        return
    endif

    if !executable('curl') || !executable('tar')
        call s:WarnOnce('curl and tar are required to download the bundled nvr-go binary. Install them or nvr manually.')
        return
    endif

    let l:platform = s:DetectPlatform()
    if empty(l:platform)
        call s:WarnOnce('Unsupported platform for automatic nvr-go download. Please install nvr manually.')
        return
    endif

    let l:api_url = 'https://api.github.com/repos/nikvdp/nvr-go/releases/latest'
    let l:response = system('curl -fsSL ' . shellescape(l:api_url))
    if v:shell_error
        call s:WarnOnce('Unable to reach GitHub to download nvr-go. Install nvr manually or try :NeomuxInstallNvr later.')
        return
    endif

    try
        let l:data = json_decode(l:response)
    catch
        call s:WarnOnce('Unexpected response while checking nvr-go releases. Install nvr manually.')
        return
    endtry

    let l:tag = get(l:data, 'tag_name', '')
    if empty(l:tag)
        call s:WarnOnce('Latest nvr-go release tag not found. Install nvr manually.')
        return
    endif

    let l:asset = s:ComposeAssetName(l:tag, l:platform)
    let l:url = printf('https://github.com/nikvdp/nvr-go/releases/download/%s/%s', l:tag, l:asset)
    echom 'neomux: downloading nvr-go ' . l:tag . '...'
    redraw
    let l:tmpdir = s:this_folder . '/.nvr-go'
    if !isdirectory(l:tmpdir)
        call mkdir(l:tmpdir, 'p')
    endif
    let l:archive = l:tmpdir . '/' . l:asset
    let l:download_cmd = printf('curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 -o %s %s', shellescape(l:archive), shellescape(l:url))
    call system(l:download_cmd)
    if v:shell_error
        call delete(l:archive)
        call s:WarnOnce('Failed to download nvr-go archive. Install nvr manually or try :NeomuxInstallNvr later.')
        return
    endif

    let l:extract_dir = l:tmpdir . '/extract'
    call mkdir(l:extract_dir, 'p')
    let l:extract_cmd = printf('tar -xzf %s -C %s', shellescape(l:archive), shellescape(l:extract_dir))
    call system(l:extract_cmd)
    call delete(l:archive)
    if v:shell_error
        call delete(l:extract_dir, 'rf')
        call s:WarnOnce('Failed to extract nvr-go archive. Install nvr manually or try :NeomuxInstallNvr later.')
        return
    endif

    let l:candidates = glob(l:extract_dir . '/nvr', 0, 1)
    if empty(l:candidates)
        let l:candidates = glob(l:extract_dir . '/**/nvr', 0, 1)
    endif
    if empty(l:candidates)
        call delete(l:extract_dir, 'rf')
        call s:WarnOnce('nvr binary not found in archive. Install nvr manually.')
        return
    endif

    if filereadable(l:target)
        call delete(l:target)
    endif
    if rename(l:candidates[0], l:target) != 0
        call delete(l:extract_dir, 'rf')
        call s:WarnOnce('Unable to move nvr binary into place. Install nvr manually.')
        return
    endif
    call delete(l:extract_dir, 'rf')
    call delete(l:tmpdir, 'rf')
    call s:SetExecutable(l:target)

    echom 'neomux: nvr-go ' . l:tag . ' installed successfully'
endfunction

function! s:EnsureNvrBinary() abort
    if executable('nvr')
        return
    endif
    call s:InstallNvrBinary(0)
endfunction

function! s:NeomuxMain()
    call s:EnsureNvrBinary()
    " Set default key bindings if no user defined maps present
    " TODO: use a dict of vars and defaults and iterate through it, below is
    "       getting unwieldy. maybe use lua?
    if !exists('g:neomux_start_term_map') | let g:neomux_start_term_map = '<Leader>sh' | endif
    if !exists('g:neomux_start_term_split_map') | let g:neomux_start_term_split_map = '<C-w>t' | endif
    if !exists('g:neomux_start_term_vsplit_map') | let g:neomux_start_term_vsplit_map = '<C-w>T' | endif
    if !exists('g:neomux_hitenter_fix') | let g:neomux_hitenter_fix = 0 | endif
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

    " Tmux integration settings (disabled by default)
    if !exists('g:neomux_enable_tmux') | let g:neomux_enable_tmux = 0 | endif
    if !exists('g:neomux_tmux_cache_dir') | let g:neomux_tmux_cache_dir = $HOME . '/.cache/neomux' | endif
    if !exists('g:neomux_tmux_session_name') | let g:neomux_tmux_session_name = '' | endif
    if !exists('g:neomux_tmux_kill_map') | let g:neomux_tmux_kill_map = '<Leader>nk' | endif
    if !exists('g:neomux_tmux_quit_map') | let g:neomux_tmux_quit_map = '<Leader>nq' | endif
    if !exists('g:neomux_tmux_reconnect_map') | let g:neomux_tmux_reconnect_map = '<Leader>nr' | endif
    
    " Terminal naming settings (only relevant when tmux is enabled)
    if !exists('g:neomux_terminal_name_prefix') | let g:neomux_terminal_name_prefix = 'neomux://' | endif
    if !exists('g:neomux_rename_term_map') | let g:neomux_rename_term_map = '<Leader>nn' | endif

    command! Neomux call NeomuxTerm()
    
    " Tmux integration commands (always available, but only useful when tmux enabled)
    command! NeomuxTmuxKill call NeomuxTmuxKillServer()
    command! NeomuxTmuxReconnect call NeomuxTmuxReconnectPicker()
    command! NeomuxTmuxClean call NeomuxTmuxClean()
    command! -nargs=1 NeomuxTmuxReconnectTo call NeomuxTmuxReconnect(<q-args>)
    command! -nargs=1 NeomuxRename call NeomuxRename(<q-args>)
    command! -nargs=0 NeomuxRenamePrompt call NeomuxRenamePrompt()

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

    " If g:neomux_hitenter_fix is set, use an extra <CR> to skip
    " confirmation of term-start commands
    if g:neomux_hitenter_fix == 0
      let l:neomux_hitenter_fix_str = ''
    else
      let l:neomux_hitenter_fix_str = '<CR>'
    endif

    " set neomux start term map
    execute printf("noremap %s :Neomux<CR>%s", g:neomux_start_term_map, l:neomux_hitenter_fix_str)

    " set winswap mappings
    for i in [1,2,3,4,5,6,7,8,9]
        execute printf('map %s%s :call WinSwap("%s")<CR>', g:neomux_winswap_map_prefix, i, i)
    endfor

    if exists('g:neomux_enable_set_win_to_cur_pos')
        call EnableWinJump()
    endif

    execute printf('noremap %s :split<CR>:call NeomuxTerm()<CR>%s', g:neomux_start_term_split_map, l:neomux_hitenter_fix_str)
    execute printf('noremap %s :vsplit<CR>:call NeomuxTerm()<CR>%s', g:neomux_start_term_vsplit_map, l:neomux_hitenter_fix_str)
    execute printf('tnoremap %s <C-\><C-n>:split<CR>:call NeomuxTerm()<CR>%s', g:neomux_start_term_split_map, l:neomux_hitenter_fix_str)
    execute printf('tnoremap %s <C-\><C-n>:vsplit<CR>:call NeomuxTerm()<CR>%s', g:neomux_start_term_vsplit_map, l:neomux_hitenter_fix_str)

    " Yank current buffer
    execute printf('map %s :call NeomuxYankBuffer()<CR>', g:neomux_yank_buffer_map)
    " Paste current buffer
    execute printf('map %s :call NeomuxPasteBuffer()<CR>', g:neomux_paste_buffer_map)

    " term size-fix map
    execute printf('noremap %s <C-\><C-n><Esc>:call NeomuxResizeWindow()<CR>', g:neomux_term_sizefix_map)
    
    " Tmux integration keymaps (only set when tmux is enabled)
    if g:neomux_enable_tmux
        execute printf('noremap %s :call NeomuxTmuxKillServer()<CR>', g:neomux_tmux_kill_map)
        execute printf('noremap %s :call NeomuxTmuxKillServer()<CR>:qa<CR>', g:neomux_tmux_quit_map)
        execute printf('noremap %s :call NeomuxTmuxReconnectPicker()<CR>', g:neomux_tmux_reconnect_map)
        execute printf('noremap %s :call NeomuxRenamePrompt()<CR>', g:neomux_rename_term_map)
    endif
endfunction

function! NeomuxSetWinToCurrentPos(tgt_win)
    let l:cur_pos = { "buf": bufnr("%"), "line": line("."), "col": col(".") }
    stopinsert
    execute printf("%swincmd w", a:tgt_win) 
    execute printf(":b!%s", l:cur_pos.buf)

    execute l:cur_pos.line
    normal 0 
    execute printf("normal %sl", l:cur_pos.col - 1)
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
    " Start a neomux terminal
    " If g:neomux_enable_tmux is set, wraps the shell in a persistent tmux session
    
    if a:0 > 0
        let l:term_cmd = a:1
    endif

    " If tmux mode is enabled and no explicit command given, use tmux wrapper
    let l:is_tmux_term = 0
    if g:neomux_enable_tmux && !exists("l:term_cmd")
        " Check if tmux is available
        if !executable('tmux')
            call s:WarnOnce('tmux not found in PATH. Install tmux or disable g:neomux_enable_tmux.')
            " Fall through to normal terminal
        else
            let l:term_cmd = s:TmuxGenerateWrapper()
            let l:is_tmux_term = 1
        endif
    endif

    if exists("l:term_cmd")
        execute printf("term! %s", l:term_cmd)
    else
        if len(g:neomux_default_shell) > 0
            execute printf("term! %s", g:neomux_default_shell)
        elseif len($SHELL) > 0
            execute "term! " . $SHELL
        else
            term!
        endif
    endif
    
    " Set up buffer-local variables and naming for tmux terminals
    if l:is_tmux_term
        let b:neomux_tmux_socket = g:neomux_tmux_socket_file
        let b:neomux_tmux_session = '0'  " First session in the tmux server
        
        " Generate default name and set neovim buffer name (handles uniqueness)
        let l:default_name = s:GenerateDefaultTerminalName()
        let l:name_result = s:SetNeomuxBufferName(bufnr('%'), l:default_name)
        
        " Store the final name (may have uniqueness suffix)
        let b:neomux_term_name = l:name_result.final
        
        " Set tmux window name with retry (tmux may not be ready immediately)
        " Use the final name so tmux and neovim stay in sync
        " Retry up to 10 times (1 second total) to handle slow tmux startup
        call s:TmuxSetWindowNameWithRetry(b:neomux_tmux_socket, b:neomux_tmux_session, l:name_result.final, 10)
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

" ============================================================================
" Tmux Integration Functions
" ============================================================================

function! s:TmuxRandomWord() abort
    " Get a random word from the system dictionary for session naming
    let l:dict_path = '/usr/share/dict/words'
    if !filereadable(l:dict_path)
        " Fallback to random number if no dictionary
        return string(localtime()) . '_' . string(rand() % 10000)
    endif
    let l:cmd = printf("sed '%dq;d' %s | sed 's/[^A-Za-z]//g'",
                \ (rand() % 50000) + 1, l:dict_path)
    let l:word = trim(system(l:cmd))
    if empty(l:word)
        return string(localtime())
    endif
    return l:word
endfunction

function! s:TmuxGetRootDir() abort
    " Get the git root directory, or current working directory
    let l:git_root = trim(system('git rev-parse --show-toplevel 2>/dev/null'))
    if v:shell_error || empty(l:git_root)
        return getcwd()
    endif
    return l:git_root
endfunction

function! s:TmuxGetNvimSocketPath() abort
    " Get the neovim socket path for RPC communication
    " Neovim >= 0.7.2 uses $NVIM, older versions use $NVIM_LISTEN_ADDRESS
    if has("nvim-0.7.2")
        return v:servername
    else
        return $NVIM_LISTEN_ADDRESS
    endif
endfunction

function! s:TmuxEnsureCacheDir() abort
    " Ensure the cache directory exists
    if !isdirectory(g:neomux_tmux_cache_dir)
        call mkdir(g:neomux_tmux_cache_dir, 'p')
    endif
endfunction

function! s:TmuxGenerateSessionName() abort
    " Generate or return the session name
    if !empty(g:neomux_tmux_session_name)
        return g:neomux_tmux_session_name
    endif
    
    if exists('g:neomux_tmux_session') && !empty(g:neomux_tmux_session)
        return g:neomux_tmux_session
    endif
    
    " Generate: <basename_of_root_dir>_<random_word>
    let l:root_dir = s:TmuxGetRootDir()
    let l:base_name = fnamemodify(l:root_dir, ':t')
    let l:random_word = s:TmuxRandomWord()
    return printf('%s_%s', l:base_name, l:random_word)
endfunction

function! s:TmuxGenerateWrapper() abort
    " Generate the tmux wrapper script and return its path
    " This creates persistent tmux sessions that can survive neovim restarts
    
    call s:TmuxEnsureCacheDir()
    
    " Set up session name if not already set
    if !exists('g:neomux_tmux_session') || empty(g:neomux_tmux_session)
        let g:neomux_tmux_session = s:TmuxGenerateSessionName()
    endif
    
    " Get neovim socket for compatibility with both old and new neovim
    let l:nvim_socket = s:TmuxGetNvimSocketPath()
    
    " Ensure NVIM_LISTEN_ADDRESS is set for older tools
    if has("nvim-0.7.2")
        let $NVIM_LISTEN_ADDRESS = v:servername
    endif
    
    " Derive paths from session name
    let l:socket_file = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, g:neomux_tmux_session)
    " Extract nvim identifier from socket path (e.g., /tmp/nvimABC123/0 -> nvimABC123)
    let l:socket_parts = split(l:nvim_socket, '/')
    let l:nvim_ident = len(l:socket_parts) >= 2 ? l:socket_parts[-2] : l:socket_parts[-1]
    let l:wrapper_file = printf('%s/%s_%s.sh', g:neomux_tmux_cache_dir, g:neomux_tmux_session, l:nvim_ident)
    let l:session_file = printf('%s/nmux_%s.session', g:neomux_tmux_cache_dir, g:neomux_tmux_session)
    
    " Store paths in global variables for access by other functions
    let g:neomux_tmux_socket_file = l:socket_file
    let g:neomux_tmux_sess_file = l:session_file
    
    " Write session state file (sourceable vimscript for reconnection)
    call writefile([
                \ printf("let g:neomux_tmux_socket_file = '%s'", l:socket_file),
                \ printf("let g:neomux_tmux_session = '%s'", g:neomux_tmux_session),
                \ printf("let g:neomux_tmux_sess_file = '%s'", l:session_file)
                \ ], l:session_file)
    
    " Update tmux environment if server is already running
    call system(printf("tmux -S %s set-environment -g NVIM %s 2>/dev/null", shellescape(l:socket_file), shellescape(l:nvim_socket)))
    call system(printf("tmux -S %s set-environment -g NVIM_LISTEN_ADDRESS %s 2>/dev/null", shellescape(l:socket_file), shellescape(l:nvim_socket)))
    call system(printf("tmux -S %s set-environment -g NEOMUX_RC %s 2>/dev/null", shellescape(l:socket_file), shellescape(l:wrapper_file)))
    
    " Set environment variable for shell access
    let $NEOMUX_RC = l:wrapper_file
    
    " Determine shell to use
    let l:shell = len($SHELL) > 0 ? $SHELL : '/bin/sh'
    
    " Write the wrapper script
    call writefile([
                \ '#!/bin/bash',
                \ printf('export NVIM_LISTEN_ADDRESS="%s"', l:nvim_socket),
                \ printf('export NVIM="%s"', l:nvim_socket),
                \ printf('export NEOMUX_RC="%s"', l:wrapper_file),
                \ printf("tmux -S '%s' new-session '%s'", l:socket_file, l:shell)
                \ ], l:wrapper_file)
    
    call s:SetExecutable(l:wrapper_file)
    
    return l:wrapper_file
endfunction

function! NeomuxTmuxSocket() abort
    " Public function to get the current tmux socket path
    if exists('g:neomux_tmux_socket_file')
        return g:neomux_tmux_socket_file
    endif
    return ''
endfunction

function! NeomuxTmuxSessionName() abort
    " Public function to get the current session name
    if exists('g:neomux_tmux_session')
        return g:neomux_tmux_session
    endif
    return ''
endfunction

function! s:TmuxSetWindowName(socket, tmux_session, name) abort
    " Set the tmux window name for a session
    " Also disables automatic-rename to prevent tmux from overwriting it
    let l:cmd = printf("tmux -S %s rename-window -t %s %s 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:tmux_session), shellescape(a:name))
    call system(l:cmd)
    if v:shell_error
        return 0
    endif
    " Disable automatic rename so tmux doesn't overwrite our name
    let l:cmd = printf("tmux -S %s set-window-option -t %s automatic-rename off 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:tmux_session))
    call system(l:cmd)
    return 1
endfunction

function! s:TmuxSetWindowNameWithRetry(socket, tmux_session, name, retries) abort
    " Try to set tmux window name, retrying if tmux isn't ready yet
    " This handles the race condition where neovim starts faster than tmux
    let l:success = s:TmuxSetWindowName(a:socket, a:tmux_session, a:name)
    if !l:success && a:retries > 0
        " Retry after a short delay (100ms)
        let l:Callback = {-> s:TmuxSetWindowNameWithRetry(a:socket, a:tmux_session, a:name, a:retries - 1)}
        call timer_start(100, {_ -> l:Callback()})
    endif
    return l:success
endfunction

function! s:TmuxGetWindowName(socket, tmux_session) abort
    " Get the tmux window name for a session
    let l:cmd = printf("tmux -S %s display-message -t %s -p '#{window_name}' 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:tmux_session))
    let l:name = trim(system(l:cmd))
    if v:shell_error
        return ''
    endif
    return l:name
endfunction

function! s:GenerateDefaultTerminalName() abort
    " Generate a default name for a new terminal based on current directory
    let l:dir_name = fnamemodify(getcwd(), ':t')
    if empty(l:dir_name)
        let l:dir_name = 'shell'
    endif
    return l:dir_name
endfunction

function! s:SetNeomuxBufferName(bufnr, name) abort
    " Set the neovim buffer name for a neomux terminal
    " Handles uniqueness by appending <N> suffix if needed
    " Returns a dict with 'base' (the original name) and 'full' (with prefix and possible suffix)
    let l:fullname = g:neomux_terminal_name_prefix . a:name
    let l:final_name = a:name
    
    " Check for existing buffer with same name
    let l:existing = bufnr(l:fullname)
    if l:existing != -1 && l:existing != a:bufnr
        " Find unique suffix
        let l:idx = 2
        while bufnr(l:fullname . '<' . l:idx . '>') != -1
            let l:idx += 1
        endwhile
        let l:fullname = l:fullname . '<' . l:idx . '>'
        let l:final_name = a:name . '<' . l:idx . '>'
    endif
    
    call nvim_buf_set_name(a:bufnr, l:fullname)
    return {'base': a:name, 'full': l:fullname, 'final': l:final_name}
endfunction

function! NeomuxTerminalName(...) abort
    " Get the terminal name for a neomux buffer
    " Optional argument: buffer number (defaults to current buffer)
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')
    
    " Check if it's a neomux terminal
    let l:name = getbufvar(l:bufnr, 'neomux_term_name', '')
    if !empty(l:name)
        return l:name
    endif
    
    " Try to get from tmux if buffer-local var not set
    let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
    let l:session = getbufvar(l:bufnr, 'neomux_tmux_session', '')
    if !empty(l:socket) && !empty(l:session)
        return s:TmuxGetWindowName(l:socket, l:session)
    endif
    
    return ''
endfunction

function! NeomuxIsTerminal(...) abort
    " Check if a buffer is a neomux tmux terminal
    " Optional argument: buffer number (defaults to current buffer)
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')
    let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
    return !empty(l:socket)
endfunction

function! NeomuxTmuxListSessions() abort
    " List all active neomux tmux sessions by finding open sockets
    " Returns a list of session names
    let l:sessions = []
    
    " Use lsof to find tmux processes with neomux sockets
    let l:lsof_cmd = printf("lsof -w -P -n -c tmux 2>/dev/null | grep '%s' | grep tmux-socket", g:neomux_tmux_cache_dir)
    let l:output = system(l:lsof_cmd)
    
    " Extract session names from socket paths
    for l:line in split(l:output, "\n")
        " Match the session name from path like: /path/to/cache/<session>.tmux-socket
        let l:match = matchstr(l:line, g:neomux_tmux_cache_dir . '/\zs[^/]\+\ze\.tmux-socket')
        if !empty(l:match) && index(l:sessions, l:match) < 0
            call add(l:sessions, l:match)
        endif
    endfor
    
    return l:sessions
endfunction

function! s:TmuxListWindowsForSession(socket_path) abort
    " List tmux windows/sessions for a given socket
    " Returns a dict of {session_name: window_name}
    let l:cmd = printf("tmux -S %s list-sessions -F '#{session_name}|#{window_name}' 2>/dev/null", shellescape(a:socket_path))
    let l:output = system(l:cmd)
    
    if v:shell_error
        return {}
    endif
    
    let l:windows = {}
    for l:line in split(l:output, "\n")
        let l:parts = split(l:line, '|')
        if len(l:parts) >= 2
            let l:windows[l:parts[0]] = l:parts[1]
        elseif len(l:parts) == 1
            let l:windows[l:parts[0]] = ''
        endif
    endfor
    
    return l:windows
endfunction

function! s:TmuxRandomUniqueId() abort
    " Generate a unique ID for reattached sessions
    return printf('%d.%d', localtime(), rand() % 10000)
endfunction

function! s:TmuxStartTermAndConnect(tmux_session, socket_path, ...) abort
    " Start a terminal and connect it to an existing tmux session
    " Creates a new tmux session linked to the target session
    " Optional argument: window_name (if known from tmux query)
    let l:window_name = a:0 > 0 ? a:1 : ''
    
    let l:new_session = a:tmux_session . '_NMUXREATTACH_' . s:TmuxRandomUniqueId()
    let l:cmd = printf("tmux -S %s new-session -t %s -s %s", shellescape(a:socket_path), shellescape(a:tmux_session), shellescape(l:new_session))
    execute 'term ' . l:cmd
    
    " Set up buffer-local variables for the reconnected terminal
    let b:neomux_tmux_socket = a:socket_path
    let b:neomux_tmux_session = a:tmux_session
    
    " Restore terminal name from tmux (or use provided name)
    if empty(l:window_name)
        let l:window_name = s:TmuxGetWindowName(a:socket_path, a:tmux_session)
    endif
    
    if !empty(l:window_name)
        let l:name_result = s:SetNeomuxBufferName(bufnr('%'), l:window_name)
        let b:neomux_term_name = l:name_result.final
    endif
endfunction

function! NeomuxTmuxReconnect(session_name) abort
    " Reconnect to an existing neomux tmux session
    " This resets the current session state and opens terminals for each window
    
    " Clear existing session state
    if exists('g:neomux_tmux_sess_file')
        unlet g:neomux_tmux_sess_file
    endif
    if exists('g:neomux_tmux_socket_file')
        unlet g:neomux_tmux_socket_file
    endif
    if exists('g:neomux_tmux_session')
        unlet g:neomux_tmux_session
    endif
    if exists('g:neomux_default_shell')
        unlet g:neomux_default_shell
    endif
    
    " Set the new session
    let g:neomux_tmux_session = a:session_name
    
    " Regenerate wrapper (this also sets socket_file etc.)
    let l:wrapper = s:TmuxGenerateWrapper()
    
    " Get socket path and list windows
    let l:socket = g:neomux_tmux_socket_file
    let l:windows = s:TmuxListWindowsForSession(l:socket)
    
    " Open a split for each tmux session/window, restoring names
    for [l:sess, l:win_name] in items(l:windows)
        execute 'split'
        call s:TmuxStartTermAndConnect(l:sess, l:socket, l:win_name)
    endfor
    
    " Provide instructions for updating old shells
    let l:reload_cmd = 'eval $(tmux show-env -g NEOMUX_RC) && source $NEOMUX_RC'
    echom printf("Reconnected to '%s'. Run in old shells to update: %s", a:session_name, l:reload_cmd)
    let @n = l:reload_cmd
endfunction

function! NeomuxTmuxReconnectPicker() abort
    " Open fzf picker to select a session to reconnect to
    let l:sessions = NeomuxTmuxListSessions()
    
    if empty(l:sessions)
        echom 'neomux: No active tmux sessions found'
        return
    endif
    
    " Check if fzf is available
    if exists('*fzf#run')
        call fzf#run({'source': l:sessions, 'sink': function('NeomuxTmuxReconnect')})
    else
        " Fallback: show inputlist
        let l:choices = ['Select session to reconnect:']
        let l:idx = 1
        for l:sess in l:sessions
            call add(l:choices, printf('%d. %s', l:idx, l:sess))
            let l:idx += 1
        endfor
        let l:choice = inputlist(l:choices)
        if l:choice > 0 && l:choice <= len(l:sessions)
            call NeomuxTmuxReconnect(l:sessions[l:choice - 1])
        endif
    endif
endfunction

function! NeomuxTmuxKillServer() abort
    " Kill the tmux server for the current session
    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        echom 'neomux: No active tmux session'
        return
    endif
    
    let l:cmd = printf("tmux -S %s kill-server 2>/dev/null", shellescape(g:neomux_tmux_socket_file))
    call system(l:cmd)
    if v:shell_error
        echom 'neomux: tmux server was not running or already killed'
    else
        echom 'neomux: Killed tmux server'
    endif
endfunction

function! NeomuxTmuxClean() abort
    " Clean up reattached session markers (sessions with NMUXREATTACH in name)
    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        echom 'neomux: No active tmux session'
        return
    endif
    
    let l:socket = g:neomux_tmux_socket_file
    let l:cmd = printf("tmux -S %s ls 2>/dev/null | grep NMUXREATTACH | sed 's/:.*//'", shellescape(l:socket))
    let l:output = system(l:cmd)
    
    let l:count = 0
    for l:sess in split(l:output, "\n")
        if !empty(l:sess)
            let l:kill_cmd = printf("tmux -S %s kill-session -t %s 2>/dev/null", shellescape(l:socket), shellescape(l:sess))
            call system(l:kill_cmd)
            let l:count += 1
        endif
    endfor
    
    echom printf('neomux: Cleaned %d reattached session(s)', l:count)
endfunction

function! NeomuxRename(name) abort
    " Rename the current neomux terminal
    " Updates both tmux window name and neovim buffer name
    
    " Check if this is a neomux tmux terminal
    if !exists('b:neomux_tmux_socket') || !exists('b:neomux_tmux_session')
        echom 'neomux: Current buffer is not a neomux tmux terminal'
        return
    endif
    
    let l:name = trim(a:name)
    if empty(l:name)
        echom 'neomux: Name cannot be empty'
        return
    endif
    
    " Update tmux window name (source of truth)
    let l:success = s:TmuxSetWindowName(b:neomux_tmux_socket, b:neomux_tmux_session, l:name)
    if !l:success
        echom 'neomux: Failed to set tmux window name'
        return
    endif
    
    " Update buffer-local variable
    let b:neomux_term_name = l:name
    
    " Update neovim buffer name
    let l:fullname = s:SetNeomuxBufferName(bufnr('%'), l:name)
    
    echom printf("neomux: Renamed terminal to '%s'", l:name)
endfunction

function! NeomuxRenamePrompt() abort
    " Prompt user for a new terminal name
    if !exists('b:neomux_tmux_socket')
        echom 'neomux: Current buffer is not a neomux tmux terminal'
        return
    endif
    
    let l:current = exists('b:neomux_term_name') ? b:neomux_term_name : ''
    let l:name = input('New terminal name: ', l:current)
    if !empty(l:name)
        call NeomuxRename(l:name)
    endif
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
