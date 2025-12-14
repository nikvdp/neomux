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

    if a:force
        echom 'neomux: downloaded nvr-go ' . l:tag
    endif
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
