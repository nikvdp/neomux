e() {
    # split
    nvr --remote "$@"
}

s() {
    # split
    nvr --remote -o "$@"
}

vs() {
    # vert split
    nvr --remote -O "$@"
}

t() {
    # tab
    nvr --remote-tab "$@"
}

vbcopy() {
    local register=${1:-@""}
    local inp
    inp="$(</dev/stdin)"
    nvr -c "let @$register=\"$(echo "$inp" | sed -E 's/(["\])/\\\1/g')\""
}

vbpaste() {
    local register="${1:-@\"}"
    nvr --remote-expr "@$register"
}

vcd() {
    # switch *neovim's* working dir to $1
    local dir="$(abspath "${1:-$PWD}")"
    nvr -c "chdir $dir"
}

cdv() {
    # cd to the parent neovim's current working dir
    cd "$(vpwd)"
}

vpwd() {
    # print vim's current working dir
    nvr --remote-expr "getcwd()"
}

vim-window-print() {
    # vim-window-print: send contents of a window out to stdout
    local win="$1"
    local oldwin="$(nvr --remote-expr 'tabpagewinnr(tabpagenr())')"
    nvr -cc "${win}wincmd w" --remote-expr 'join(getline(1,"$"), "\n")' -c "${oldwin}wincmd w"
    # nvr --remote-send a
}

# (vw from the command line) -- open a file in the window with the specified number
vimwindow() {
    # remote nvim open file $2 in window $1
    local win="$1"
    local file="$2"
    if [[ "$file" == "-" ]]; then
        # allow piping stdin if '-' passed as filename
        cat | nvr -cc "${win}wincmd w" --remote -
    else
        nvr -cc "${win}wincmd w" -c "e $(abspath "$file")"
    fi
}

# (vws from the command line) -- open a file in the window with the specified
# number in a split
vimwindowsplit() {
    # remote nvim open file $2 in window $1
    local win="$1"
    local file="$2"
    nvr -cc "${win}wincmd w" -c "split"
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
