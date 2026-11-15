#!/bin/sh
# Instalacja launchera dla bieżącego użytkownika (bez uprawnień administratora): skrót w menu KDE/GNOME,
# polecenie `openmwgodot` w ~/.local/bin i ikona. Kod zostaje w repozytorium (aktualizacja = git pull).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HOME/.local/bin"; APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
mkdir -p "$BIN" "$APPS" "$ICONS"
ln -sf "$ROOT/launcher/openmwgodot-launcher" "$BIN/openmwgodot"
sed "s|@EXEC@|$ROOT/launcher/openmwgodot-launcher|" "$ROOT/launcher/openmwgodot.desktop.in" > "$APPS/openmwgodot.desktop"
cp "$ROOT/launcher/resources/openmwgodot.png" "$ICONS/openmwgodot.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" || true
echo "Zainstalowano: polecenie 'openmwgodot' i skrót OpenMWGodot w menu aplikacji."
