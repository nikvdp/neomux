#!/usr/bin/env bash
SCRIPT_LOCATION="$( cd "$( dirname "$0" )" && pwd )"

nvr_script="$(python -c 'import nvr; print(nvr.nvr.__file__)')"

workdir="$(mktemp -d)"

echo "Workdir: $workdir"
pushd "$workdir" &> /dev/null 

pyi-makespec --onefile $nvr_script &&
    pyinstaller *.spec

set -x
os="$(uname -s)"
arch="$(uname -m)"

mkdir -p "$SCRIPT_LOCATION/../${os}.${arch}.bin"
mv dist/* "$SCRIPT_LOCATION/../${os}.${arch}.bin"

rm -rf "$workdir"
