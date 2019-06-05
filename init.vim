""" TODO delete
colorscheme shine

" set leader key to ',' intead of '\'
let g:mapleader=","
""" TODO /delete

noremap <Leader>sh :call OpenTermWithTermString()<CR>

function! OpenTermWithTermString()
    let l:name = GenNikTermName()
    let l:cmd = GenNikTermNameCmd(l:name)

    execute l:cmd
    execute ":file " . l:name
    execute "set nonumber"
endfunction

function! GenNikTermName()
    let l:name = substitute(expand("%:h:t"), "[._/]", "", "g")
    if len(l:name) < 1
        " If we didn't get a name from the expand cmd above, try to grab one
        " from dirname of current cwd
        let l:name = substitute(substitute(getcwd(), ".*/", "", "g"), "[._/]", "", "g")
    endif
    return "SHELL-" . l:name . "-" . strftime('%s')
endfunction

function! GenNikTermNameCmd(...)
    " Generates a command that can be passed to `:execute` to start a new term

    
    let l:this_folder = fnamemodify(resolve(expand('<sfile>:p')), ':h')
 
    let l:shell_type
    if matchstr($CUR_SHELL, 'zsh$') == "zsh"
        let l:shell_type = "zsh"
    elseif matchstr($CUR_SHELL, 'bash$') == "bash"
        let l:shell_type = "bash"
    endif

    let l:lines = [
                \    printf('export NVIM_LISTEN_ADDRESS="%s"', $NVIM_LISTEN_ADDRESS),
                \    printf('export PATH="%s"', $PATH),
                \    printf("cd '%s'", getcwd()),
                \    'alias vp=echo "vim paste"',
                \    'alias vw=echo "vim window"',
                \    'if [[ "$CUR_SHELL" == "zsh" ]]; then',
                \    '    source ~/.zshrc',
                \    'elif [[ "$CUR_SHELL" == "bash" ]]; then',
                \    '    source ~/.bashrc',
                \    'fi',
                \ ]

    let l:date = strftime("%Y.%m.%d-%H.%M.%S")
    let l:init_script_dir = printf('/tmp/%s-nvim/nvim-%s', $USER, l:date)
    let l:init_script_file = printf("%s/%s", l:init_script_dir, ".zshrc")

    call mkdir(l:init_script_dir, "p")
    call writefile(l:lines, l:init_script_file)

    if $CUR_SHELL == ""
        let $CUR_SHELL = "zsh"
    endif
    if matchstr($CUR_SHELL, 'zsh$') == "zsh"
        let l:str = printf("term tmux new-session -s \"%s\" -- bash -c 'export ZDOTDIR=%s; zsh -i'", l:tmux_sess_name, l:init_script_dir)
    " elseif matchstr($CUR_SHELL, 'bash$') == "bash"
    else
        let l:str = printf("term tmux new-session -s '%s' -- bash --init-file '%s'", l:tmux_sess_name, l:init_script_file)
    endif
    return l:str
endfunction
