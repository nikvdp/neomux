# Unalias any conflicting names before defining functions
# This prevents zsh errors when an alias exists with the same name
unalias e s t vs vcd cdv vpwd vw vws 2>/dev/null || true

get_nvim_socket() {
    # Get nvim socket - from tmux if available (survives reconnect), else env var
    if [ -n "$TMUX" ]; then
        local socket
        socket=$(tmux show-environment -g NVIM 2>/dev/null | cut -d= -f2)
        if [ -n "$socket" ]; then
            echo "$socket"
            return
        fi
    fi
    # Fallback to env var
    echo "${NVIM:-$NVIM_LISTEN_ADDRESS}"
}

nvr_cmd() {
    # Wrapper for nvr that gets fresh socket from tmux if available
    export NVIM="$(get_nvim_socket)"
    export NVIM_LISTEN_ADDRESS="$NVIM"
    nvr "$@"
}

e() {
    # edit in current window
    nvr_cmd --remote "$@"
}

s() {
    # split
    nvr_cmd --remote -o "$@"
}

vs() {
    # vert split
    nvr_cmd --remote -O "$@"
}

t() {
    # tab
    nvr_cmd --remote-tab "$@"
}

vbcopy() {
    local register=${1:-@""}
    local inp
    inp="$(</dev/stdin)"
    nvr_cmd -c "let @$register=\"$(echo "$inp" | sed -E 's/(["\])/\\\1/g')\""
}

vbpaste() {
    local register="${1:-@\"}"
    nvr_cmd --remote-expr "@$register"
}

vcd() {
    # switch *neovim's* working dir to $1
    local dir="$(abspath "${1:-$PWD}")"
    nvr_cmd -c "chdir $dir"
}

cdv() {
    # cd to the parent neovim's current working dir
    cd "$(vpwd)"
}

vpwd() {
  # print vim's current working dir (-1,-1) tells vim to return the global working dir
    nvr_cmd --remote-expr "getcwd(-1,-1)"
}

vim-window-print() {
    # vim-window-print: send contents of a window out to stdout
    local win="$1"
    local oldwin="$(nvr_cmd --remote-expr 'tabpagewinnr(tabpagenr())')"
    nvr_cmd -cc "${win}wincmd w" --remote-expr 'join(getline(1,"$"), "\n")' -c "${oldwin}wincmd w"
    # nvr_cmd --remote-send a
}

# (vw from the command line) -- open a file in the window with the specified number
vimwindow() {
    # remote nvim open file $2 in window $1
    local win="$1"
    local file="$2"
    if [[ "$file" == "-" ]]; then
        # allow piping stdin if '-' passed as filename
        cat | nvr_cmd -cc "${win}wincmd w" --remote -
    else
        nvr_cmd -cc "${win}wincmd w" -c "e $(abspath "$file")"
    fi
}

# (vws from the command line) -- open a file in the window with the specified
# number in a split
vimwindowsplit() {
    # remote nvim open file $2 in window $1
    local win="$1"
    local file="$2"
    nvr_cmd -cc "${win}wincmd w" -c "split"
    vimwindow "$win" "$file"
}


abspath() {
    local in_path
    if [[ ! "$1" =~ ^/ ]]; then
        in_path="$PWD/$1"
    else
        in_path="$1"
    fi
    echo "$in_path" | (
        IFS=/
        read -a parr
        declare -a outp
        for i in "${parr[@]}"; do
            case "$i" in
            '' | .)
                continue
                ;;
            ..)
                len=${#outp[@]}
                if ((len == 0)); then
                    continue
                else
                    unset outp[$((len - 1))]
                fi
                ;;
            *)
                len=${#outp[@]}
                outp[$len]="$i"
                ;;
            esac
        done
        echo /"${outp[*]}"
    )
}
