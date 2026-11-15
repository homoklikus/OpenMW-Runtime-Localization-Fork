# Zmiany

## 0.3 — 2026-11-15 (sesja 3): osobny launcher

* **Nowy launcher Qt 6 (PySide6)** `launcher/`: ekran główny 1024×683 wg grafiki referencyjnej (menu boczne,
  baner, stan instalacji z podglądem, aktywny profil, szybkie akcje, ozdobny „Graj”, ostatnie działania,
  pasek stanu), paleta kolorów z próbek referencji, własne godło i proceduralne grafiki zamiast logo
  i ilustracji Bethesdy, opcjonalny lokalny motyw `~/.config/openmwgodot/theme/`, kreator pierwszego uruchomienia, strony Konwersja / Mody / Ustawienia, zarządzanie
  profilami, uruchamianie gry i Construction Set w osobnych procesach, ciemny motyw i własne godło,
  skrót w menu KDE (`tools/install_launcher.sh`).
* **Usunięty launcher-scena Godota** (sesja 2) – wymaganie: launcher nie może inicjalizować silnika;
  jego logika (wykrywanie, postęp) przeniesiona do `mwcore` i launchera Qt. Scena startowa projektu
  Godota to znów `main.tscn`.
* **`mwcore`** – wspólna warstwa danych: katalogi XDG/przenośne, atomowy JSON, konfiguracja i schemat
  ustawień, profile, instalacja i walidacja Morrowinda, mody (bezpieczne archiwa ZIP/7z, warstwy,
  kolejność, zależności, konflikty), plan i stan konwersji, polecenia i blokady procesów.
* **Konwerter**: anulowanie SIGTERM/SIGINT z zachowaniem ukończonych zasobów (kod 130), blokada katalogu
  (`convert.lock`), odtwarzanie uszkodzonej bazy cache, `verify` / `clean`, nakładka profilu na wspólną
  bazę (`--base-out`), zdarzenia `stage` dla każdego etapu, `asset_error`, `warning`, `cancelled`,
  lekki moduł nagłówka ESM (`mwconv/esm/header.py`, bez numpy).
* **Runtime**: wiele katalogów danych (`--base`), ustawienia z pliku (`--settings`: okno, rozdzielczość,
  V-Sync, limit FPS, skala 3D, cienie, zasięg, odległość widzenia, woda, mgła, czułość i odwrócenie myszy),
  kod wyjścia 2 przy braku danych, tryb `--autotest-frames` dla testów integracyjnych.
* **CS 2.0**: wtyczka czyta argumenty z launchera (`--data`, `--project`, `--base`) i od razu wczytuje świat.

## 0.2 — 2026-11-15 (sesja 2)

Trudne przypadki NIF i diagnostyka (`scan`, `inspect`), kontrolery/morfy/cząsteczki/.kf, woda, drzwi,
pora dnia i pogoda, strumieniowe ESM, wypiekanie `.scn`, CS 2.0 (teren, rekordy, konflikty), zgodność z Godot 4.7.

## 0.1 — 2026-11-15 (sesja 1)

Konwerter NIF/ESM/BSA/LAND → GLB + model świata, runtime Godot, prototyp CS 2.0.
