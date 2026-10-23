#!/usr/bin/env bash

# shellcheck source=tools/installers/download_with_retry.sh
. ./tools/installers/download_with_retry.sh

if [ ! -e tools/kaldi ]; then
    git clone https://github.com/kaldi-asr/kaldi --depth 1 tools/kaldi
fi

# Workaround to avoid issue introduces in v0.11.0
# PATH=$(pwd)/test_utils/bats-core/bin:$(pwd)/shellcheck-stable:$PATH
PATH=$(pwd)/test_utils/bats-core/bin:$(pwd)/shellcheck-v0.10.0:$PATH
if ! [ -x "$(command -v bats)" ]; then
    echo "=== install bats ==="
    git clone https://github.com/bats-core/bats-core.git "$(pwd)"/test_utils/bats-core
    git clone https://github.com/bats-core/bats-support.git "$(pwd)"/test_utils/bats-support
    git clone https://github.com/bats-core/bats-assert.git "$(pwd)"/test_utils/bats-assert
fi
if ! [ -x "$(command -v shellcheck)" ]; then
    echo "=== install shellcheck ==="
    # wget https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz
    # tar -xvf shellcheck-stable.linux.x86_64.tar.xz

    # Workaround to avoid issue introduces in v0.11.0
    download_with_retry \
        https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz \
        shellcheck-v0.10.0.linux.x86_64.tar.xz
    tar -xvf shellcheck-v0.10.0.linux.x86_64.tar.xz
fi
. tools/activate_python.sh
. tools/extra_path.sh

set -euo pipefail

echo "=== run shellcheck ==="
rm -fv tools/Miniconda*.sh  # exclude from schellcheck
rm -fv tools/Miniforge*.sh  # exclude from schellcheck
# Each shellcheck process is single-threaded: check files in parallel, $(nproc) at a time.
# Same files, flags and working directory as the former `find -execdir` calls;
# each file's output is printed as one "=> path" block, so the log stays readable.
_sc() {  # $1: dir to cd into, $2: path to check from there, $3: path to print
    local out
    out=$(cd "$1" && shellcheck -Calways -x -e SC2001 -e SC1091 -e SC2086 "$2") || true
    # one printf per file, so parallel writers don't split a header from its findings
    if [ -n "${out}" ]; then printf '=> %s\n%s\n' "$3" "${out}"; else printf '=> %s\n' "$3"; fi
}
export -f _sc
nj=$(nproc 2>/dev/null || echo 2)
# shellcheck disable=SC2016
find utils ci doc egs2/TEMPLATE/*/scripts egs2/TEMPLATE/*/setup.sh tools/*.sh -name "*.sh" -print0 \
    | xargs -0 -n 1 -P "${nj}" bash -c '_sc "$(dirname "$1")" "./$(basename "$1")" "$1"' _ | tee check_shellcheck
# shellcheck disable=SC2016
find egs2/*/*/local/data.sh -print0 \
    | xargs -0 -n 1 -P "${nj}" bash -c '_sc "$(dirname "$(dirname "$1")")" "local/./data.sh" "$1"' _ | tee -a check_shellcheck
# shellcheck disable=SC2016
find egs2 \( -name "run.sh" -o -name asr.sh -o -name tts.sh -o -name enh.sh \) -print0 \
    | xargs -0 -n 1 -P "${nj}" bash -c '_sc "$(dirname "$1")" "./$(basename "$1")" "$1"' _ | tee -a check_shellcheck

if grep -q "SC[0-9]\{4\}" check_shellcheck; then
    echo "[ERROR] shellcheck failed"
    exit 1
fi

echo "=== run bats ==="
bats test_utils/espnet2_scripts/test_*.bats
