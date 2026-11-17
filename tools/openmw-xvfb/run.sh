#!/bin/bash
# run.sh KATALOG CFG_DIR [argumenty OpenMW…] – OpenMW na bieżącym DISPLAY (np. Xvfb :77), konfiguracja i dane
# użytkownika procesu w CFG_DIR (XDG_CONFIG_HOME/XDG_DATA_HOME), bez profilu użytkownika.
set -euo pipefail
DIR="$1"; CFG="$2"; shift 2
OMW="$DIR/openmw-0.51.0-Linux-64Bit"
export XDG_CONFIG_HOME="$CFG" XDG_DATA_HOME="$CFG/data" XDG_RUNTIME_DIR="$CFG/run"
mkdir -p "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
cd "$OMW"
export OSG_LIBRARY_PATH="$OMW/lib"
GL="$DIR/glibc/usr/lib/x86_64-linux-gnu"
exec ./ld-omw --library-path "$GL:$DIR/stdcxx/usr/lib/x86_64-linux-gnu:$OMW/lib:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu" \
  ./openmw.x86_64 "$@"
