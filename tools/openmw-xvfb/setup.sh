#!/bin/bash
# Pobiera oficjalne OpenMW 0.51.0 (Linux) oraz glibc 2.39 i libstdc++ 14 z Ubuntu 24.04 do katalogu podręcznego.
set -euo pipefail
DIR="${1:-$HOME/.cache/openmwgodot/openmw-xvfb}"
mkdir -p "$DIR" && cd "$DIR"
OMW=openmw-0.51.0-Linux-64Bit
if [ ! -x "$OMW/openmw.x86_64" ]; then
  curl -fsSL -o omw.tgz "https://github.com/OpenMW/openmw/releases/download/openmw-0.51.0/$OMW.tar.gz"
  tar xzf omw.tgz && rm -f omw.tgz
fi
deb() {  # $1 = katalog puli, $2 = wzorzec pakietu, $3 = katalog docelowy
  [ -d "$3" ] && return 0
  local f; f=$(curl -fsSL "http://archive.ubuntu.com/ubuntu/pool/main/$1/" | grep -oE "$2" | sort -uV | tail -1)
  curl -fsSL -o pkg.deb "http://archive.ubuntu.com/ubuntu/pool/main/$1/$f"
  mkdir -p "$3" && dpkg-deb -x pkg.deb "$3" && rm -f pkg.deb
}
deb g/glibc/ 'libc6_2\.39[^"]*amd64\.deb' glibc
deb g/gcc-14/ 'libstdc\+\+6_14\.2[^"]*amd64\.deb' stdcxx
cp -f glibc/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "$OMW/ld-omw"
sed -i "s#^resources=./resources#resources=$DIR/$OMW/resources#; s#^data=./resources/vfs-mw#data=$DIR/$OMW/resources/vfs-mw#" "$OMW/openmw.cfg"
echo "Gotowe: $DIR"
