#!/usr/bin/env bash

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

# formerly vbcopy
vc() {
    local register=${1:-@""}
    local inp
    inp="$(</dev/stdin)"
    nvr -c "let @$register=\"$(echo "$inp" | sed -E 's/(["\])/\\\1/g')\""
}

# formerly vbpaste
vp () {
    local register="${1:-@\"}"
    nvr --remote-expr "@$register"
}


vcd () {
    # switch *neovim's* working dir to $1
    local dir="$(_abspath "${1:-$PWD}")"
    nvr -c "chdir $dir"
}

vpwd() {
    # print vim's current working dir
    nvr --remote-expr "getcwd()"
}

vwp() {
    # vim-window-print: send contents of a window out to stdout
    local win="$1"
    local oldwin="$(nvr --remote-expr 'tabpagewinnr(tabpagenr())')"
    nvr -cc "${win}wincmd w" --remote-expr 'join(getline(1,"$"), "\n")' -c "${oldwin}wincmd w"
    # nvr --remote-send a
}

# formerly vim-window
vw() {
    # remote nvim open file $2 in window $1
    local win="$1"
    local file="$2"
    if [[ "$file" == "-" ]]; then
        # allow piping stdin if '-' passed as filename
        cat | nvr -cc "${win}wincmd w" --remote -
    else
        nvr -cc "${win}wincmd w" -c "e $(_abspath "$file")"
    fi
}

_abspath() {
    local in_path
    if [[ ! "$1" =~ ^/ ]]; then
        in_path="$PWD/$1"
    else
        in_path="$1"
    fi
    echo "$in_path"|(
        IFS=/
        read -a parr
        declare -a outp
        for i in "${parr[@]}"; do
            case "$i" in
            ''|.)
                continue
                ;;
            ..)
                len=${#outp[@]}
                if ((len == 0))
                then
                    continue
                else
                    unset outp[$((len-1))] 
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

nmux() {
    nvr -cc vsplit --remote-wait "$@"
}

if [ -L "$0" ]; then
    "$(basename $0)" "$@"
fi

exit 127
