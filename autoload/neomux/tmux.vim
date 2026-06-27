if !has('nvim')
    finish
endif

if exists('g:neomux_tmux_autoload_loaded') && g:neomux_tmux_autoload_loaded
    finish
endif
let g:neomux_tmux_autoload_loaded = 1

let s:this_file = fnamemodify(resolve(expand('<sfile>:p')), ':p')
let s:repo_root = fnamemodify(s:this_file, ':h:h:h')
let s:plugin_folder = s:repo_root . '/plugin'
let s:bin_folder = printf('%s/bin', s:plugin_folder)

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

function! s:TmuxSocketIsAlive(socket) abort
    " Return 1 when a tmux server responds on this socket
    if empty(a:socket) || empty(glob(a:socket))
        return 0
    endif

    let l:cmd = printf('tmux -S %s has-session 2>/dev/null', shellescape(a:socket))
    call system(l:cmd)
    return v:shell_error == 0
endfunction

function! s:TmuxCleanDeadSocketsOnStartup() abort
    " Remove stale neomux sockets that no longer have a live tmux server
    call s:TmuxEnsureCacheDir()

    let l:removed = 0
    for l:socket in globpath(g:neomux_tmux_cache_dir, '*.tmux-socket', 0, 1)
        if s:TmuxSocketIsAlive(l:socket)
            continue
        endif
        if delete(l:socket) == 0
            let l:removed += 1
        endif
    endfor

    if l:removed > 0
        echom printf('neomux: Removed %d stale tmux socket(s)', l:removed)
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

function! s:TmuxSourceCommands(socket, commands) abort
    " Execute multiple tmux commands in one source-file call
    if empty(a:commands)
        return 1
    endif

    let l:tmpfile = tempname()
    call writefile(a:commands, l:tmpfile)

    let l:cmd = printf('tmux -S %s source-file %s 2>/dev/null',
                \ shellescape(a:socket),
                \ shellescape(l:tmpfile))
    call system(l:cmd)
    let l:success = v:shell_error == 0

    call delete(l:tmpfile)
    return l:success
endfunction

function! s:TmuxUpdateEnvironment(socket) abort
    " Update tmux global environment with current neovim socket and PATH
    " This allows shells to find neovim and neomux tools after reconnect/restore
    "
    " IMPORTANT: tmux's server/client architecture means new shells inherit
    " environment from the tmux SERVER, not from the neovim terminal job.
    " We must explicitly set PATH in tmux's global environment to ensure
    " the neomux bin folder is available in all shells.
    let l:nvim_socket = s:TmuxGetNvimSocketPath()

    " Also update/create the RC file so shells can source it for helper functions
    let l:rc_file = printf('%s/%s.rc.sh', g:neomux_tmux_cache_dir, g:neomux_tmux_session)
    call s:WriteNeomuxRc(l:rc_file, l:nvim_socket)

    " Set tmux environment vars in one batch to reduce shell/process overhead
    let l:commands = [
                \ printf('set-environment -g PATH %s', shellescape($PATH)),
                \ printf('set-environment -g NVIM %s', shellescape(l:nvim_socket)),
                \ printf('set-environment -g NVIM_LISTEN_ADDRESS %s', shellescape(l:nvim_socket)),
                \ printf('set-environment -g EDITOR %s', shellescape($EDITOR)),
                \ printf('set-environment -g NEOMUX_RC %s', shellescape(l:rc_file)),
                \ ]
    call s:TmuxSourceCommands(a:socket, l:commands)

    return l:rc_file
endfunction

function! s:TmuxEnsureSessionVars() abort
    " Ensure global session variables are set up
    " Call this before any tmux operations

    call s:TmuxEnsureCacheDir()

    " Set up session name if not already set
    if !exists('g:neomux_tmux_session') || empty(g:neomux_tmux_session)
        let g:neomux_tmux_session = s:TmuxGenerateSessionName()
    endif

    " Derive socket path from session name
    let l:socket_file = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, g:neomux_tmux_session)
    let g:neomux_tmux_socket_file = l:socket_file

    " Ensure NVIM_LISTEN_ADDRESS is set for older tools
    if has("nvim-0.7.2")
        let $NVIM_LISTEN_ADDRESS = v:servername
    endif

    " Update tmux environment and get the RC file path
    let l:rc_file = s:TmuxUpdateEnvironment(l:socket_file)

    " Set NEOMUX_RC in our environment so it propagates to tmux
    let $NEOMUX_RC = l:rc_file
endfunction

function! s:WriteNeomuxRc(rc_file, nvim_socket) abort
    " Write the RC script that shells source on startup
    " This ensures PATH includes neomux bin folder and env vars are set
    let l:lines = [
        \ '# Neomux RC - source this in your shell for neomux integration',
        \ printf('export PATH=%s:"$PATH"', shellescape(s:bin_folder)),
        \ printf('export NVIM=%s', shellescape(a:nvim_socket)),
        \ printf('export NVIM_LISTEN_ADDRESS=%s', shellescape(a:nvim_socket)),
        \ printf('export EDITOR=%s', shellescape(s:bin_folder . '/nmux')),
        \ printf('export NEOMUX_RC=%s', shellescape(a:rc_file)),
        \ printf('source %s', shellescape(s:bin_folder . '/funcs.sh')),
        \ ]
    call writefile(l:lines, a:rc_file)
endfunction

function! s:TmuxSetSessionEnvironment(socket, session_name) abort
    " Set environment variables in a specific tmux session
    " This is called after creating a session to ensure PATH etc. are correct
    " even if the global environment wasn't properly inherited
    let l:commands = [
                \ printf('set-environment -t %s PATH %s', shellescape(a:session_name), shellescape($PATH)),
                \ printf('set-environment -t %s NVIM %s', shellescape(a:session_name), shellescape($NVIM)),
                \ printf('set-environment -t %s NVIM_LISTEN_ADDRESS %s', shellescape(a:session_name), shellescape($NVIM_LISTEN_ADDRESS)),
                \ printf('set-environment -t %s EDITOR %s', shellescape(a:session_name), shellescape($EDITOR)),
                \ ]
    if exists('$NEOMUX_RC')
        call add(l:commands, printf('set-environment -t %s NEOMUX_RC %s', shellescape(a:session_name), shellescape($NEOMUX_RC)))
    endif
    call s:TmuxSourceCommands(a:socket, l:commands)
endfunction

function! s:TmuxGetNextSessionNum(socket) abort
    " Get the next available session number for this socket
    " Sessions are named nmux_0, nmux_1, etc.
    let l:cmd = printf("tmux -S %s list-sessions -F '#{session_name}' 2>/dev/null", shellescape(a:socket))
    let l:output = system(l:cmd)

    let l:max_num = -1
    for l:line in split(l:output, "\n")
        " Match nmux_N pattern (but not nmux_N_NMUX_* grouped sessions)
        let l:match = matchstr(l:line, '^nmux_\zs\d\+$')
        if !empty(l:match)
            let l:num = str2nr(l:match)
            if l:num > l:max_num
                let l:max_num = l:num
            endif
        endif
    endfor

    return l:max_num + 1
endfunction

function! s:TmuxCreateSession(socket, session_name) abort
    " Create a new tmux session and attach to it
    " Returns the command to run in :term
    let l:shell = len($SHELL) > 0 ? $SHELL : '/bin/sh'

    " Build the tmux command
    let l:cmd = printf("tmux -S %s new-session -s %s %s",
                \ shellescape(a:socket),
                \ shellescape(a:session_name),
                \ shellescape(l:shell))

    return l:cmd
endfunction

function! neomux#tmux#Socket() abort
    " Public function to get the current tmux socket path
    if exists('g:neomux_tmux_socket_file')
        return g:neomux_tmux_socket_file
    endif
    return ''
endfunction

function! neomux#tmux#SessionName() abort
    " Public function to get the current session name
    if exists('g:neomux_tmux_session')
        return g:neomux_tmux_session
    endif
    return ''
endfunction

function! s:TmuxGetDisplayName(socket) abort
    " Get the display name from tmux environment, or empty string if not set
    let l:cmd = printf("tmux -S %s show-environment -g NEOMUX_DISPLAY_NAME 2>/dev/null",
                \ shellescape(a:socket))
    let l:output = trim(system(l:cmd))

    if v:shell_error || empty(l:output)
        return ''
    endif

    " Output is "NEOMUX_DISPLAY_NAME=<name>", extract the value
    let l:idx = stridx(l:output, '=')
    if l:idx < 0
        return ''
    endif

    return l:output[l:idx + 1:]
endfunction

function! s:TmuxSetDisplayName(socket, name) abort
    " Set the display name in tmux environment
    let l:cmd = printf("tmux -S %s set-environment -g NEOMUX_DISPLAY_NAME %s 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:name))
    call system(l:cmd)
    return !v:shell_error
endfunction

function! neomux#tmux#SessionDisplayName() abort
    " Get the display name for the current session (or internal name if no display name set)
    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        return ''
    endif

    let l:display = s:TmuxGetDisplayName(g:neomux_tmux_socket_file)
    if !empty(l:display)
        return l:display
    endif

    " Fall back to internal session name
    return exists('g:neomux_tmux_session') ? g:neomux_tmux_session : ''
endfunction

function! s:TmuxSetWindowName(socket, target, name) abort
    " Set the tmux window name for a target (session:window or just session for active window)
    " Also disables automatic-rename to prevent tmux from overwriting it
    let l:cmd = printf("tmux -S %s rename-window -t %s %s 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:target), shellescape(a:name))
    call system(l:cmd)
    if v:shell_error
        return 0
    endif
    " Disable automatic rename so tmux doesn't overwrite our name
    let l:cmd = printf("tmux -S %s set-window-option -t %s automatic-rename off 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:target))
    call system(l:cmd)
    return 1
endfunction

function! s:TmuxSetWindowNameWithRetry(socket, target, name, retries) abort
    " Try to set tmux window name, retrying if tmux isn't ready yet
    " This handles the race condition where neovim starts faster than tmux
    let l:success = s:TmuxSetWindowName(a:socket, a:target, a:name)
    if l:success
        " Done
    elseif a:retries > 0
        " Retry after a short delay (100ms)
        let l:Callback = {-> s:TmuxSetWindowNameWithRetry(a:socket, a:target, a:name, a:retries - 1)}
        call timer_start(100, {_ -> l:Callback()})
    else
        " All retries exhausted, warn user
        echohl WarningMsg
        echom 'neomux: Failed to set tmux window name after retries (tmux may not have started)'
        echohl None
    endif
    return l:success
endfunction

function! s:TmuxGetWindowName(socket, target) abort
    " Get the tmux window name for a target (session or session:window)
    let l:cmd = printf("tmux -S %s display-message -t %s -p '#{window_name}' 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:target))
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

function! s:GetSessionDisplayLabel() abort
    " Get a short label for the session to use in buffer names
    " Uses display name if set, otherwise extracts word from internal name
    if exists('g:neomux_tmux_socket_file') && !empty(g:neomux_tmux_socket_file)
        let l:display = s:TmuxGetDisplayName(g:neomux_tmux_socket_file)
        if !empty(l:display)
            return l:display
        endif
    endif

    " Fall back to extracting word from internal session name (e.g., 'neomux_Arum' -> 'Arum')
    if exists('g:neomux_tmux_session') && !empty(g:neomux_tmux_session)
        let l:parts = split(g:neomux_tmux_session, '_')
        if len(l:parts) >= 2
            return l:parts[-1]
        endif
        return g:neomux_tmux_session
    endif
    return ''
endfunction

function! s:SetNeomuxBufferName(bufnr, name) abort
    " Set the neovim buffer name for a neomux terminal
    " Format: neomux:<session_label>:<terminal_name>
    " Handles uniqueness by appending <N> suffix if needed
    " Returns a dict with 'base' (the original name) and 'full' (with prefix and possible suffix)
    let l:session_label = s:GetSessionDisplayLabel()
    if !empty(l:session_label)
        let l:display_name = l:session_label . ':' . a:name
    else
        let l:display_name = a:name
    endif

    let l:fullname = 'neomux:' . l:display_name
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

function! neomux#tmux#TerminalName(...) abort
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

function! neomux#tmux#IsTerminal(...) abort
    " Check if a buffer is a neomux tmux terminal
    " Optional argument: buffer number (defaults to current buffer)
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')
    let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
    return !empty(l:socket)
endfunction

function! neomux#tmux#ListSessions() abort
    " List all active neomux tmux sessions by checking socket files
    " Returns a list of internal session names, sorted by most recently modified first
    let l:sessions = []

    for l:socket in globpath(g:neomux_tmux_cache_dir, '*.tmux-socket', 0, 1)
        if !s:TmuxSocketIsAlive(l:socket)
            continue
        endif
        let l:session = substitute(fnamemodify(l:socket, ':t'), '\.tmux-socket$', '', '')
        if !empty(l:session) && index(l:sessions, l:session) < 0
            call add(l:sessions, l:session)
        endif
    endfor

    " Sort by socket file modification time (most recent first)
    " Build list of [session, mtime] pairs
    let l:with_mtime = []
    for l:sess in l:sessions
        let l:socket_path = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, l:sess)
        let l:mtime = getftime(l:socket_path)
        call add(l:with_mtime, [l:sess, l:mtime])
    endfor

    " Sort by mtime descending (most recent first)
    call sort(l:with_mtime, {a, b -> b[1] - a[1]})

    " Extract just the session names
    return map(l:with_mtime, {_, v -> v[0]})
endfunction

function! s:FormatSessionPickerLabel(internal_name) abort
    " Get a display label for a session picker: "display_name (internal)" or just "internal"
    let l:socket = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, a:internal_name)
    let l:display = s:TmuxGetDisplayName(l:socket)

    if !empty(l:display) && l:display !=# a:internal_name
        return printf('%s (%s)', l:display, a:internal_name)
    endif
    return a:internal_name
endfunction

function! s:ParseSessionFromLabel(label) abort
    " Extract internal session name from a display label
    " "display_name (internal)" -> "internal"
    " "internal" -> "internal"
    let l:match = matchstr(a:label, '(\zs[^)]\+\ze)$')
    if !empty(l:match)
        return l:match
    endif
    return a:label
endfunction

function! neomux#tmux#ListSessionsForPicker() abort
    " List sessions with display names for picker UI
    " Returns list of display labels that can be parsed with s:ParseSessionFromLabel()
    let l:internal_names = neomux#tmux#ListSessions()
    return map(l:internal_names, {_, v -> s:FormatSessionPickerLabel(v)})
endfunction

function! s:TmuxListMainSessions(socket_path) abort
    " List all main neomux sessions (nmux_N pattern, excluding _NMUX_ grouped ones)
    " Returns a list of dicts: [{'session': 'nmux_0', 'window_name': 'name'}, ...]
    let l:sep = '|||'
    let l:cmd = printf("tmux -S %s list-sessions -F '#{session_name}%s#{window_name}' 2>/dev/null",
                \ shellescape(a:socket_path), l:sep)
    let l:output = system(l:cmd)

    if v:shell_error
        return []
    endif

    let l:sessions = []
    for l:line in split(l:output, "\n")
        let l:parts = split(l:line, l:sep, 1)
        if len(l:parts) >= 1
            let l:sess_name = l:parts[0]
            " Only include nmux_N sessions, not grouped ones (_NMUX_)
            if l:sess_name =~# '^nmux_\d\+$'
                let l:win_name = len(l:parts) >= 2 ? join(l:parts[1:], l:sep) : ''
                call add(l:sessions, {'session': l:sess_name, 'window_name': l:win_name})
            endif
        endif
    endfor

    return l:sessions
endfunction

function! s:TmuxRandomUniqueId() abort
    " Generate a unique ID for reattached sessions
    " Use underscore, not dot (dot is tmux session:window separator)
    return printf('%d_%d', localtime(), rand() % 10000)
endfunction

function! s:TmuxStartTermAndConnect(socket_path, session, window_name) abort
    " Start a terminal and attach it to an existing tmux session
    " session is like 'nmux_0', 'nmux_1', etc.

    " Update session environment BEFORE attaching so the shell has correct PATH
    " This is critical when reconnecting from a new neovim instance
    call s:TmuxSetSessionEnvironment(a:socket_path, a:session)

    " Just attach directly to the session
    let l:attach_cmd = printf("tmux -S %s attach-session -t %s",
                \ shellescape(a:socket_path),
                \ shellescape(a:session))
    execute 'term ' . l:attach_cmd

    " Set up buffer-local variables for the reconnected terminal
    let b:neomux_tmux_socket = a:socket_path
    let b:neomux_tmux_session = a:session

    " Set buffer name from the provided window name
    if !empty(a:window_name)
        let l:name_result = s:SetNeomuxBufferName(bufnr('%'), a:window_name)
        let b:neomux_term_name = l:name_result.final
    endif
endfunction

function! neomux#tmux#Reconnect(session_name) abort
    " Reconnect to an existing neomux tmux session
    " session_name is the neomux session (e.g., 'nik_colpotomy'), not the tmux session

    " Clear existing session state
    if exists('g:neomux_tmux_socket_file')
        unlet g:neomux_tmux_socket_file
    endif
    if exists('g:neomux_tmux_session')
        unlet g:neomux_tmux_session
    endif

    " Set the new session name and derive socket path
    let g:neomux_tmux_session = a:session_name
    let l:socket = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, a:session_name)
    let g:neomux_tmux_socket_file = l:socket

    if !s:TmuxSocketIsAlive(l:socket)
        if !empty(glob(l:socket))
            call delete(l:socket)
        endif
        echom printf("neomux: tmux socket for '%s' is not active", a:session_name)
        return
    endif

    " Update tmux environment with new neovim socket so old shells can find us
    call s:TmuxUpdateEnvironment(l:socket)

    " List all main sessions (nmux_0, nmux_1, etc.)
    let l:sessions = s:TmuxListMainSessions(l:socket)

    if empty(l:sessions)
        echom printf("neomux: No terminals found in '%s'", a:session_name)
        return
    endif

    " Open a split for each tmux session, restoring names
    let l:first = 1
    for l:sess in l:sessions
        if !l:first
            execute 'split'
        endif
        let l:first = 0
        call s:TmuxStartTermAndConnect(l:socket, l:sess.session, l:sess.window_name)
    endfor

    " Start autosave timer after reconnect
    call s:StartAutosaveTimer()

    echom printf("neomux: Reconnected to '%s' (%d terminals)", a:session_name, len(l:sessions))
endfunction

function! s:ReconnectFromLabel(label) abort
    " Wrapper for fzf sink that parses the display label
    let l:internal = s:ParseSessionFromLabel(a:label)
    call neomux#tmux#Reconnect(l:internal)
endfunction

function! neomux#tmux#ReconnectPicker() abort
    " Open fzf picker to select a session to reconnect to
    let l:labels = neomux#tmux#ListSessionsForPicker()

    if empty(l:labels)
        echom 'neomux: No active tmux sessions found'
        return
    endif

    " Check if fzf is available
    if exists('*fzf#run')
        call fzf#run({'source': l:labels, 'sink': function('s:ReconnectFromLabel')})
    else
        " Fallback: show inputlist
        let l:choices = ['Select session to reconnect:']
        let l:idx = 1
        for l:label in l:labels
            call add(l:choices, printf('%d. %s', l:idx, l:label))
            let l:idx += 1
        endfor
        let l:choice = inputlist(l:choices)
        if l:choice > 0 && l:choice <= len(l:labels)
            call s:ReconnectFromLabel(l:labels[l:choice - 1])
        endif
    endif
endfunction

function! neomux#tmux#KillServer() abort
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

function! neomux#tmux#Clean() abort
    " Clean up any orphaned grouped sessions (legacy _NMUX_ pattern)
    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        echom 'neomux: No active tmux session'
        return
    endif

    let l:socket = g:neomux_tmux_socket_file
    let l:cmd = printf("tmux -S %s list-sessions -F '#{session_name}' 2>/dev/null", shellescape(l:socket))
    let l:output = system(l:cmd)

    let l:count = 0
    for l:sess in split(l:output, "\n")
        " Kill any session with _NMUX_ in the name (old grouped sessions)
        if l:sess =~# '_NMUX_'
            let l:kill_cmd = printf("tmux -S %s kill-session -t %s 2>/dev/null", shellescape(l:socket), shellescape(l:sess))
            call system(l:kill_cmd)
            let l:count += 1
        endif
    endfor

    echom printf('neomux: Cleaned %d orphaned session(s)', l:count)
endfunction

function! neomux#tmux#RenameTerminal(name) abort
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

    " Update neovim buffer name first (may add uniqueness suffix)
    let l:name_result = s:SetNeomuxBufferName(bufnr('%'), l:name)
    let l:final_name = l:name_result.final

    " Update tmux window name (source of truth) with final name
    let l:success = s:TmuxSetWindowName(b:neomux_tmux_socket, b:neomux_tmux_session, l:final_name)
    if !l:success
        echom 'neomux: Failed to set tmux window name'
        return
    endif

    " Update buffer-local variable with final name
    let b:neomux_term_name = l:final_name

    echom printf("neomux: Renamed terminal to '%s'", l:final_name)
endfunction

function! neomux#tmux#RenameTerminalPrompt() abort
    " Prompt user for a new terminal name
    if !exists('b:neomux_tmux_socket')
        echom 'neomux: Current buffer is not a neomux tmux terminal'
        return
    endif

    let l:current = exists('b:neomux_term_name') ? b:neomux_term_name : ''
    let l:name = input('New terminal name: ', l:current)
    if !empty(l:name)
        call neomux#tmux#RenameTerminal(l:name)
    endif
endfunction

function! neomux#tmux#RenameSession(name) abort
    " Rename the current neomux session (sets display name)
    " The internal name (used for socket files) remains unchanged
    " Also updates all neomux terminal buffer names to reflect the new session name

    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        echom 'neomux: No active neomux session'
        return
    endif

    let l:name = trim(a:name)
    if empty(l:name)
        echom 'neomux: Name cannot be empty'
        return
    endif

    let l:success = s:TmuxSetDisplayName(g:neomux_tmux_socket_file, l:name)
    if !l:success
        echom 'neomux: Failed to rename session'
        return
    endif

    " Update all neomux terminal buffer names to use new session label
    call s:RefreshAllTerminalBufferNames()

    echom printf("neomux: Session renamed to '%s'", l:name)
endfunction

function! s:RefreshAllTerminalBufferNames() abort
    " Refresh buffer names for all neomux terminals in current session
    " Called after session rename to update the session label in buffer names
    for l:bufnr in range(1, bufnr('$'))
        if !bufexists(l:bufnr)
            continue
        endif
        let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
        if empty(l:socket)
            continue
        endif
        " Only update terminals from this session
        if l:socket !=# g:neomux_tmux_socket_file
            continue
        endif
        let l:term_name = getbufvar(l:bufnr, 'neomux_term_name', '')
        if !empty(l:term_name)
            call s:SetNeomuxBufferName(l:bufnr, l:term_name)
        endif
    endfor
endfunction

function! neomux#tmux#RenameSessionPrompt() abort
    " Prompt user for a new session name
    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        echom 'neomux: No active neomux session'
        return
    endif

    let l:current = neomux#tmux#SessionDisplayName()
    let l:name = input('New session name: ', l:current)
    if !empty(l:name)
        call neomux#tmux#RenameSession(l:name)
    endif
endfunction

" ============================================================================
" Session Save/Restore Functions
" ============================================================================

function! s:TmuxSaveSessionState(socket, json) abort
    " Save session state to tmux environment variable
    let l:cmd = printf("tmux -S %s set-environment -g NEOMUX_SESSION_STATE %s 2>/dev/null",
                \ shellescape(a:socket), shellescape(a:json))
    call system(l:cmd)
    return !v:shell_error
endfunction

function! s:TmuxLoadSessionState(socket) abort
    " Load session state from tmux environment variable
    let l:cmd = printf("tmux -S %s show-environment -g NEOMUX_SESSION_STATE 2>/dev/null",
                \ shellescape(a:socket))
    let l:output = trim(system(l:cmd))

    if v:shell_error || empty(l:output)
        return ''
    endif

    " Output is "NEOMUX_SESSION_STATE=<json>", extract the value
    let l:idx = stridx(l:output, '=')
    if l:idx < 0
        return ''
    endif

    return l:output[l:idx + 1:]
endfunction

function! s:CaptureWindowState(winid) abort
    " Capture the state of a single window
    let l:bufnr = winbufnr(a:winid)
    let l:buftype = getbufvar(l:bufnr, '&buftype')
    let l:bufname = bufname(l:bufnr)

    let l:state = {}

    if l:buftype ==# 'terminal'
        " It's a terminal - check if it's a neomux terminal
        let l:tmux_session = getbufvar(l:bufnr, 'neomux_tmux_session', '')
        let l:term_name = getbufvar(l:bufnr, 'neomux_term_name', '')

        if !empty(l:tmux_session)
            let l:state.type = 'neomux_terminal'
            let l:state.tmux_session = l:tmux_session
            let l:state.name = l:term_name
        else
            " Regular terminal (not neomux) - we can't restore these
            let l:state.type = 'terminal'
            let l:state.name = l:bufname
        endif
    elseif empty(l:buftype) && !empty(l:bufname) && filereadable(l:bufname)
        " Regular file buffer
        let l:state.type = 'file'
        let l:state.path = fnamemodify(l:bufname, ':p')
        " Save cursor position
        let l:pos = getcurpos(a:winid)
        let l:state.cursor = [l:pos[1], l:pos[2]]
    else
        " Other buffer types (help, quickfix, empty, etc.)
        let l:state.type = 'other'
        let l:state.buftype = l:buftype
        let l:state.bufname = l:bufname
    endif

    return l:state
endfunction

function! s:SerializeLayoutTree(layout, states, active_winid, meta) abort
    " Convert raw winlayout() data into a stable dictionary tree
    let l:type = a:layout[0]

    if l:type ==# 'leaf'
        let l:winid = a:layout[1]
        call add(a:states, s:CaptureWindowState(l:winid))
        let l:index = len(a:states) - 1
        if l:winid == a:active_winid
            let a:meta.active = l:index
        endif
        return {'type': 'leaf', 'state_index': l:index}
    endif

    let l:children = []
    for l:child in a:layout[1]
        call add(l:children, s:SerializeLayoutTree(l:child, a:states, a:active_winid, a:meta))
    endfor

    return {'type': l:type, 'children': l:children}
endfunction

function! s:ConvertLegacyLayout(node, cursor) abort
    " Convert the legacy list-based layout into the new dictionary shape
    let l:type = a:node[0]

    if l:type ==# 'leaf'
        let l:index = a:cursor.next
        if a:cursor.limit > 0 && l:index >= a:cursor.limit
            let l:index = a:cursor.limit - 1
        endif
        let a:cursor.next += 1
        return {'type': 'leaf', 'state_index': max([0, l:index])}
    endif

    let l:children = []
    for l:child in a:node[1]
        call add(l:children, s:ConvertLegacyLayout(l:child, a:cursor))
    endfor

    return {'type': l:type, 'children': l:children}
endfunction

function! s:EnsureLayoutTree(layout, state_count) abort
    " Ensure layout data uses the dictionary schema, converting if needed
    if type(a:layout) == type({})
        if get(a:layout, 'type', '') ==# 'leaf' && !has_key(a:layout, 'state_index')
            let a:layout.state_index = 0
        endif
        return a:layout
    endif

    if type(a:layout) != type([])
        return {'type': 'leaf', 'state_index': 0}
    endif

    let l:cursor = {'next': 0, 'limit': a:state_count}
    return s:ConvertLegacyLayout(a:layout, l:cursor)
endfunction

function! s:CaptureTabState(tabnr) abort
    " Capture the state of a single tab, including window layout and tab name,
    " without switching visible tabs.
    let l:states = []
    let l:meta = {'active': 0}
    let l:active_winid = win_getid(tabpagewinnr(a:tabnr), a:tabnr)
    let l:layout = s:SerializeLayoutTree(winlayout(a:tabnr), l:states, l:active_winid, l:meta)

    " Capture tab name if set
    let l:tab_name = gettabvar(a:tabnr, 'tab_name', '')

    let l:result = {'layout': l:layout, 'states': l:states, 'active': l:meta.active}
    if !empty(l:tab_name)
        let l:result.tab_name = l:tab_name
    endif
    return l:result
endfunction

function! s:CaptureSessionState() abort
    " Capture the entire session state
    let l:state = {
        \ 'version': 2,
        \ 'neomux_session': exists('g:neomux_tmux_session') ? g:neomux_tmux_session : '',
        \ 'cwd': getcwd(),
        \ 'current_tab': tabpagenr(),
        \ 'tabs': []
        \ }

    " Capture each tab
    for l:tabnr in range(1, tabpagenr('$'))
        call add(l:state.tabs, s:CaptureTabState(l:tabnr))
    endfor

    " Capture hidden neomux terminals not present in window layout
    let l:seen = s:CollectNeomuxTermKeysFromState(l:state)
    let l:hidden = s:CaptureHiddenNeomuxTerminals(l:seen)
    if !empty(l:hidden)
        let l:state.hidden_neomux_terminals = l:hidden
    endif

    return l:state
endfunction

function! s:CreateSplitStructure(layout, leaves) abort
    " Recursively create the split structure to mirror the saved layout tree
    if empty(a:layout)
        return 0
    endif

    return s:BuildLayoutNode(a:layout, win_getid(), a:leaves)
endfunction

function! s:BuildLayoutNode(node, winid, leaves) abort
    let l:type = get(a:node, 'type', 'leaf')
    if l:type ==# 'leaf'
        call s:GoToWindowSilently(a:winid)
        call add(a:leaves, {'winid': a:winid, 'state_index': get(a:node, 'state_index', len(a:leaves))})
        return a:winid
    endif

    let l:children = get(a:node, 'children', [])
    if empty(l:children)
        return s:BuildLayoutNode({'type': 'leaf', 'state_index': get(a:node, 'state_index', len(a:leaves))}, a:winid, a:leaves)
    endif

    let l:placeholders = s:EnsureChildWindows(a:winid, l:type, len(l:children))
    for l:idx in range(0, len(l:children) - 1)
        call s:BuildLayoutNode(l:children[l:idx], l:placeholders[l:idx], a:leaves)
    endfor

    call s:GoToWindowSilently(l:placeholders[0])
    return l:placeholders[0]
endfunction

function! s:EnsureChildWindows(anchor_winid, layout_type, count) abort
    " Split anchor_winid into count placeholder windows laid out like layout_type
    if a:count <= 1
        return [a:anchor_winid]
    endif

    let l:windows = [a:anchor_winid]
    let l:current = a:anchor_winid
    let l:cmd = a:layout_type ==# 'row' ? 'rightbelow vsplit' : 'belowright split'

    for l:i in range(2, a:count)
        call s:GoToWindowSilently(l:current)
        execute l:cmd
        let l:current = win_getid()
        call add(l:windows, l:current)
    endfor

    " Ensure the list is exactly count long
    return l:windows
endfunction

function! s:RestoreTabLayout(tabstate) abort
    " Restore a tab's layout using the saved split tree and window states
    if !has_key(a:tabstate, 'layout')
        return
    endif

    let l:states = get(a:tabstate, 'states', [])
    let l:layout = s:EnsureLayoutTree(a:tabstate.layout, len(l:states))
    let l:leaves = []
    call s:CreateSplitStructure(l:layout, l:leaves)

    for l:leaf in l:leaves
        let l:index = get(l:leaf, 'state_index', -1)
        if l:index >= 0 && l:index < len(l:states)
            call s:GoToWindowSilently(l:leaf.winid)
            call s:RestoreWindowContent(l:states[l:index])
        else
            call s:GoToWindowSilently(l:leaf.winid)
            enew
        endif
    endfor

    " Restore tab name if present
    if has_key(a:tabstate, 'tab_name') && !empty(a:tabstate.tab_name)
        let t:tab_name = a:tabstate.tab_name
    endif

    let l:target = get(a:tabstate, 'active', 0)
    for l:leaf in l:leaves
        if get(l:leaf, 'state_index', -1) == l:target
            call s:GoToWindowSilently(l:leaf.winid)
            return
        endif
    endfor

    if !empty(l:leaves)
        call s:GoToWindowSilently(l:leaves[0].winid)
    endif
endfunction

function! s:RestoreWindowContent(state) abort
    " Restore the content of a window based on saved state

    if a:state.type ==# 'file'
        " Open the file
        if filereadable(a:state.path)
            execute 'edit ' . fnameescape(a:state.path)
            " Restore cursor position
            if has_key(a:state, 'cursor')
                call cursor(a:state.cursor[0], a:state.cursor[1])
            endif
        endif
    elseif a:state.type ==# 'neomux_terminal'
        " Reconnect to the tmux session
        if !empty(a:state.tmux_session)
            call s:TmuxStartTermAndConnect(g:neomux_tmux_socket_file, a:state.tmux_session, a:state.name)
            call s:MarkNeomuxTerminalRestored(a:state.tmux_session, a:state.name)
        endif
    elseif a:state.type ==# 'terminal'
        " Regular terminal - just create an empty one (can't restore state)
        terminal
    else
        " Other buffer types - create empty buffer
        enew
    endif
endfunction

function! s:RestoreSessionState(state) abort
    " Restore the entire session state

    " Set up neomux session variables
    if !empty(a:state.neomux_session)
        let g:neomux_tmux_session = a:state.neomux_session
        let g:neomux_tmux_socket_file = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, a:state.neomux_session)

        " Update tmux environment with new neovim socket so restored shells can find us
        call s:TmuxUpdateEnvironment(g:neomux_tmux_socket_file)
    endif

    " Change to saved working directory
    if !empty(a:state.cwd) && isdirectory(a:state.cwd)
        execute 'cd ' . fnameescape(a:state.cwd)
    endif

    " Close all existing windows/tabs first
    silent! tabonly
    silent! only

    " Track which neomux terminals are restored from visible layout
    call s:ResetRestoredNeomuxTerminals()

    if !has_key(a:state, 'tabs') || empty(a:state.tabs)
        return
    endif

    " Restore each tab
    let l:first_tab = 1
    for l:tabstate in a:state.tabs
        if !l:first_tab
            tabnew
        endif
        let l:first_tab = 0

        " Restore the layout for this tab using two-pass approach
        call s:RestoreTabLayout(l:tabstate)
    endfor

    " Switch to the originally active tab
    if has_key(a:state, 'current_tab') && a:state.current_tab > 0
        execute 'noautocmd tabnext ' . a:state.current_tab
    endif

    " Restore hidden neomux terminals in the background
    call s:RestoreHiddenNeomuxTerminals(get(a:state, 'hidden_neomux_terminals', []))
endfunction

function! neomux#tmux#SaveSession() abort
    " Save the current session state to tmux

    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        echom 'neomux: No active neomux session. Start a terminal first.'
        return
    endif

    let l:state = s:CaptureSessionState()
    let l:json = json_encode(l:state)

    let l:success = s:TmuxSaveSessionState(g:neomux_tmux_socket_file, l:json)
    if l:success
        doautocmd User NeomuxSessionSaved
        let l:display = neomux#tmux#SessionDisplayName()
        echom printf("neomux: Session '%s' saved. Restore with :NeomuxRestoreSession %s", l:display, g:neomux_tmux_session)
    else
        echom 'neomux: Failed to save session to tmux'
    endif
endfunction

function! neomux#tmux#RestoreSession(...) abort
    " Restore a saved session state from tmux
    " Optional argument: session name (defaults to picker if multiple)

    let l:session_name = ''

    if a:0 > 0
        " Session name provided as argument (could be display label or internal name)
        let l:session_name = s:ParseSessionFromLabel(a:1)
    else
        " Pick from available sessions
        let l:labels = neomux#tmux#ListSessionsForPicker()
        if empty(l:labels)
            echom 'neomux: No active tmux sessions found'
            return
        endif

        " If only one session, use it
        if len(l:labels) == 1
            let l:session_name = s:ParseSessionFromLabel(l:labels[0])
        else
            " Multiple sessions - use fzf or inputlist
            if exists('*fzf#run')
                call fzf#run({'source': l:labels, 'sink': function('s:RestoreSessionByLabel')})
                return
            else
                let l:choices = ['Select session to restore:']
                let l:idx = 1
                for l:label in l:labels
                    call add(l:choices, printf('%d. %s', l:idx, l:label))
                    let l:idx += 1
                endfor
                let l:choice = inputlist(l:choices)
                if l:choice > 0 && l:choice <= len(l:labels)
                    let l:session_name = s:ParseSessionFromLabel(l:labels[l:choice - 1])
                else
                    return
                endif
            endif
        endif
    endif

    " Build socket path from session name
    let l:socket = printf('%s/%s.tmux-socket', g:neomux_tmux_cache_dir, l:session_name)

    if !s:TmuxSocketIsAlive(l:socket)
        if !empty(glob(l:socket))
            call delete(l:socket)
        endif
        echom printf("neomux: tmux socket for '%s' is not active", l:session_name)
        return
    endif

    doautocmd User NeomuxSessionRestoreStart

    " Load state from tmux
    let l:json = s:TmuxLoadSessionState(l:socket)
    if empty(l:json)
        " No saved state - fall back to just reconnecting terminals
        echom 'neomux: No saved layout, reconnecting terminals only'
        call neomux#tmux#Reconnect(l:session_name)
        return
    endif

    let l:state = json_decode(l:json)
    call s:RestoreSessionState(l:state)

    " Start autosave timer after restore
    call s:StartAutosaveTimer()

    let l:display = neomux#tmux#SessionDisplayName()
    echom printf('neomux: Session restored from tmux (%s)', l:display)
    doautocmd User NeomuxSessionRestored
endfunction

function! s:RestoreSessionByLabel(label) abort
    " Helper for fzf callback - parses label and restores
    let l:internal = s:ParseSessionFromLabel(a:label)
    call neomux#tmux#RestoreSession(l:internal)
endfunction

function! s:RestoreSessionByName(session_name) abort
    " Helper for fzf callback
    call neomux#tmux#RestoreSession(a:session_name)
endfunction

" ============================================================================
" Autosave Functions
" ============================================================================

function! s:GoToWindowSilently(winid) abort
    if a:winid <= 0
        return
    endif
    execute 'noautocmd call win_gotoid(' . a:winid . ')'
endfunction

function! s:NeomuxTerminalKey(tmux_session, name) abort
    return a:tmux_session . '|' . a:name
endfunction

function! s:CollectNeomuxTermKeysFromState(state) abort
    let l:keys = {}
    if !has_key(a:state, 'tabs')
        return l:keys
    endif
    for l:tab in a:state.tabs
        let l:states = get(l:tab, 'states', [])
        for l:entry in l:states
            if get(l:entry, 'type', '') ==# 'neomux_terminal'
                let l:session = get(l:entry, 'tmux_session', '')
                let l:name = get(l:entry, 'name', '')
                if !empty(l:session) && !empty(l:name)
                    let l:keys[s:NeomuxTerminalKey(l:session, l:name)] = 1
                endif
            endif
        endfor
    endfor
    return l:keys
endfunction

function! s:CaptureHiddenNeomuxTerminals(seen) abort
    let l:hidden = []
    for l:bufnr in range(1, bufnr('$'))
        if !bufexists(l:bufnr)
            continue
        endif
        let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
        let l:session = getbufvar(l:bufnr, 'neomux_tmux_session', '')
        if empty(l:socket) || empty(l:session)
            continue
        endif
        let l:name = getbufvar(l:bufnr, 'neomux_term_name', '')
        if empty(l:name)
            let l:name = neomux#tmux#TerminalName(l:bufnr)
        endif
        if empty(l:name)
            continue
        endif
        let l:key = s:NeomuxTerminalKey(l:session, l:name)
        if has_key(a:seen, l:key)
            continue
        endif
        call add(l:hidden, {'tmux_session': l:session, 'name': l:name})
        let a:seen[l:key] = 1
    endfor
    return l:hidden
endfunction

let s:restored_neomux_terminals = {}

function! s:ResetRestoredNeomuxTerminals() abort
    let s:restored_neomux_terminals = {}
endfunction

function! s:MarkNeomuxTerminalRestored(tmux_session, name) abort
    if empty(a:tmux_session) || empty(a:name)
        return
    endif
    let s:restored_neomux_terminals[s:NeomuxTerminalKey(a:tmux_session, a:name)] = 1
endfunction

function! s:RestoreHiddenNeomuxTerminals(terminals) abort
    if empty(a:terminals)
        return
    endif
    let l:return_tab = tabpagenr()
    let l:orig_hidden = &hidden
    set hidden
    tabnew
    let l:temp_tab = tabpagenr()
    for l:term in a:terminals
        let l:session = get(l:term, 'tmux_session', '')
        let l:name = get(l:term, 'name', '')
        if empty(l:session) || empty(l:name)
            continue
        endif
        let l:key = s:NeomuxTerminalKey(l:session, l:name)
        if has_key(s:restored_neomux_terminals, l:key)
            continue
        endif
        call s:TmuxStartTermAndConnect(g:neomux_tmux_socket_file, l:session, l:name)
        call s:MarkNeomuxTerminalRestored(l:session, l:name)
    endfor
    execute 'noautocmd tabnext ' . l:return_tab
    execute 'noautocmd tabclose ' . l:temp_tab
    let &hidden = l:orig_hidden
endfunction

let s:autosave_timer_id = -1
let s:autosave_autocmds_enabled = 0

function! s:AutosaveCallback(timer_id) abort
    " Debounce callback for autosaving session state
    let s:autosave_timer_id = -1

    " Only save if we have an active tmux session
    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        return
    endif

    " Silently save without echoing messages
    let l:state = s:CaptureSessionState()
    let l:json = json_encode(l:state)
    call s:TmuxSaveSessionState(g:neomux_tmux_socket_file, l:json)
endfunction

function! s:ScheduleAutosave() abort
    " Queue an autosave after a short debounce window
    if g:neomux_tmux_autosave_interval <= 0
        return
    endif

    if !exists('g:neomux_tmux_socket_file') || empty(g:neomux_tmux_socket_file)
        return
    endif

    if s:autosave_timer_id >= 0
        call timer_stop(s:autosave_timer_id)
    endif

    let l:delay_ms = g:neomux_tmux_autosave_interval * 1000
    let s:autosave_timer_id = timer_start(l:delay_ms, function('s:AutosaveCallback'))
endfunction

function! s:StartAutosaveTimer() abort
    " Enable event-driven autosave triggers if configured

    if g:neomux_tmux_autosave_interval <= 0
        return
    endif

    if !s:autosave_autocmds_enabled
        augroup neomux_autosave
            autocmd!
            autocmd WinEnter,BufEnter,TabEnter * call <SID>ScheduleAutosave()
        augroup END
        let s:autosave_autocmds_enabled = 1
    endif

    call s:ScheduleAutosave()
endfunction

function! s:StopAutosaveTimer() abort
    " Stop any scheduled autosave
    if s:autosave_timer_id >= 0
        call timer_stop(s:autosave_timer_id)
        let s:autosave_timer_id = -1
    endif
endfunction

function! neomux#tmux#AutosaveStatus() abort
    " Return the current autosave status for debugging/statusline
    if g:neomux_tmux_autosave_interval <= 0
        return 'autosave: off'
    endif
    if s:autosave_autocmds_enabled
        return printf('autosave: event+%ds', g:neomux_tmux_autosave_interval)
    else
        return 'autosave: off'
    endif
endfunction

" ============================================================================
" Buffer Picker Functions
" ============================================================================

function! s:GetNeomuxTerminalBuffers() abort
    " Get a list of all neomux terminal buffers
    " Returns list of dicts: [{'bufnr': N, 'name': 'terminal name', 'label': 'display label'}, ...]
    let l:terminals = []

    for l:bufnr in range(1, bufnr('$'))
        if !bufexists(l:bufnr)
            continue
        endif

        " Check if it's a neomux terminal (has tmux socket buffer var)
        let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
        if empty(l:socket)
            continue
        endif

        " Get terminal name
        let l:term_name = getbufvar(l:bufnr, 'neomux_term_name', '')
        if empty(l:term_name)
            " Fall back to buffer name
            let l:term_name = bufname(l:bufnr)
        endif

        " Create display label: "name (bufnr)"
        let l:label = printf('%s (%d)', l:term_name, l:bufnr)

        call add(l:terminals, {
            \ 'bufnr': l:bufnr,
            \ 'name': l:term_name,
            \ 'label': l:label
            \ })
    endfor

    return l:terminals
endfunction

function! s:SwitchToBufferFromLabel(label) abort
    " Parse buffer number from label and switch to it
    " Label format: "name (bufnr)"
    let l:match = matchstr(a:label, '(\zs\d\+\ze)$')
    if empty(l:match)
        echom 'neomux: Could not parse buffer number from selection'
        return
    endif

    let l:bufnr = str2nr(l:match)
    if !bufexists(l:bufnr)
        echom printf('neomux: Buffer %d no longer exists', l:bufnr)
        return
    endif

    execute 'buffer ' . l:bufnr
endfunction

function! neomux#tmux#BufferPicker() abort
    " Open fzf picker to select a neomux terminal buffer
    " Switches the current window to the selected buffer
    let l:terminals = s:GetNeomuxTerminalBuffers()

    if empty(l:terminals)
        echom 'neomux: No neomux terminals found'
        return
    endif

    " Extract labels for picker
    let l:labels = map(copy(l:terminals), {_, v -> v.label})

    " Check if fzf is available
    if exists('*fzf#run')
        call fzf#run({'source': l:labels, 'sink': function('s:SwitchToBufferFromLabel')})
    else
        " Fallback: show inputlist
        let l:choices = ['Select terminal:']
        let l:idx = 1
        for l:label in l:labels
            call add(l:choices, printf('%d. %s', l:idx, l:label))
            let l:idx += 1
        endfor
        let l:choice = inputlist(l:choices)
        if l:choice > 0 && l:choice <= len(l:labels)
            call s:SwitchToBufferFromLabel(l:labels[l:choice - 1])
        endif
    endif
endfunction

" ============================================================================
" External Connect Command Functions
" ============================================================================

function! neomux#tmux#GetConnectCommand(...) abort
    " Get the tmux command to connect to a neomux terminal from outside
    " Optional argument: buffer number (defaults to current buffer)
    " Returns: the tmux command string, or empty string if not a neomux terminal
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')

    let l:socket = getbufvar(l:bufnr, 'neomux_tmux_socket', '')
    let l:session = getbufvar(l:bufnr, 'neomux_tmux_session', '')

    if empty(l:socket) || empty(l:session)
        return ''
    endif

    return printf('tmux -S %s attach-session -t %s',
                \ shellescape(l:socket),
                \ shellescape(l:session))
endfunction

function! neomux#tmux#CopyConnectCommand(...) abort
    " Copy the tmux connect command to clipboard
    " Optional argument: buffer number (defaults to current buffer)
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')
    let l:cmd = neomux#tmux#GetConnectCommand(l:bufnr)

    if empty(l:cmd)
        echom 'neomux: Buffer is not a neomux tmux terminal'
        return
    endif

    let @+ = l:cmd
    let @" = l:cmd
    echom 'Copied: ' . l:cmd
endfunction


" ============================================================================
" Entrypoints Used By plugin/neomux.vim
" ============================================================================

function! neomux#tmux#CleanDeadSocketsOnStartup() abort
    return s:TmuxCleanDeadSocketsOnStartup()
endfunction

function! neomux#tmux#EnsureSessionVars() abort
    return s:TmuxEnsureSessionVars()
endfunction

function! neomux#tmux#GetNextSessionNum(socket) abort
    return s:TmuxGetNextSessionNum(a:socket)
endfunction

function! neomux#tmux#CreateSession(socket, session_name) abort
    return s:TmuxCreateSession(a:socket, a:session_name)
endfunction

function! neomux#tmux#SetSessionEnvironment(socket, session_name) abort
    return s:TmuxSetSessionEnvironment(a:socket, a:session_name)
endfunction

function! neomux#tmux#GenerateDefaultTerminalName() abort
    return s:GenerateDefaultTerminalName()
endfunction

function! neomux#tmux#SetNeomuxBufferName(bufnr, name) abort
    return s:SetNeomuxBufferName(a:bufnr, a:name)
endfunction

function! neomux#tmux#SetWindowNameWithRetry(socket, target, name, retries) abort
    return s:TmuxSetWindowNameWithRetry(a:socket, a:target, a:name, a:retries)
endfunction

function! neomux#tmux#StartAutosaveTimer() abort
    return s:StartAutosaveTimer()
endfunction
