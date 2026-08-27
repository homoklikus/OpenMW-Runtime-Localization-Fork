# Budowanie w systemie Linux

[English](BUILD_LINUX.md) | **Polski**

Ten dokument opisuje przetestowaną ścieżkę budowania
**OpenMW — Runtime Localization Fork** w systemie Linux.

Fork bazuje na OpenMW 0.51.0 i nie dodaje żadnych nowych zależności zewnętrznych
poza tymi, które są wymagane przez oryginalne OpenMW.

## Przetestowane środowisko

Zmiany związane z lokalizacją w czasie działania zostały zbudowane
i przetestowane w środowisku:

```text
Debian 13 (x86_64)
CMake
Ninja
toolchain GCC
baza źródłowa OpenMW 0.51.0
```

Nazwy pakietów zależności OpenMW różnią się między dystrybucjami i mogą zmieniać
się z czasem. Przed konfiguracją tego forka zainstaluj standardowe zależności
deweloperskie wymagane przez OpenMW 0.51.0.

Projekt źródłowy:

https://github.com/OpenMW/openmw

Dokumentacja środowiska deweloperskiego upstream:

https://wiki.openmw.org/index.php?title=Development_Environment_Setup

## Klonowanie

```bash
git clone https://github.com/homoklikus/OpenMW-Runtime-Localization-Fork.git
cd OpenMW-Runtime-Localization-Fork
```

Publiczną gałęzią rozwojową jest `main`.

## Konfiguracja

Poniższa konfiguracja została użyta w przetestowanym buildzie lokalizacji
w czasie działania. Buduje silnik gry, wyłączając narzędzia, które nie są
potrzebne do testowania runtime.

```bash
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$HOME/OpenMW-RuntimeLocalization-install" \
  -DOPENMW_USE_SYSTEM_MYGUI=OFF \
  -DBUILD_LAUNCHER=OFF \
  -DBUILD_WIZARD=OFF \
  -DBUILD_MWINIIMPORTER=OFF \
  -DBUILD_OPENCS=OFF \
  -DBUILD_ESSIMPORTER=OFF \
  -DBUILD_BSATOOL=OFF \
  -DBUILD_ESMTOOL=OFF \
  -DBUILD_NIFTEST=OFF \
  -DBUILD_NAVMESHTOOL=OFF \
  -DBUILD_BULLETOBJECTTOOL=OFF
```

Wyłączone aplikacje i narzędzia możesz ponownie włączyć, jeśli system posiada
odpowiadające im zależności.

## Budowanie i instalacja

```bash
cmake --build build -j"$(nproc)"
cmake --install build
```

Po instalacji główny plik wykonywalny powinien znajdować się pod skonfigurowanym
prefiksem instalacji:

```text
$HOME/OpenMW-RuntimeLocalization-install/bin/openmw
```

## Build przyrostowy

Po zmianie kodu źródłowego:

```bash
cmake --build build -j"$(nproc)"
cmake --install build
```

Pełna ponowna konfiguracja CMake zwykle nie jest potrzebna, chyba że zmieniły
się opcje budowania lub zależności.

## Izolowany profil testowy

Użycie osobnego profilu XDG zapobiega mieszaniu ustawień i zapisów testowych
z inną instalacją OpenMW.

```bash
mkdir -p "$HOME/OpenMW-RuntimeLocalization-test/config"
mkdir -p "$HOME/OpenMW-RuntimeLocalization-test/data"

XDG_CONFIG_HOME="$HOME/OpenMW-RuntimeLocalization-test/config" \
XDG_DATA_HOME="$HOME/OpenMW-RuntimeLocalization-test/data" \
"$HOME/OpenMW-RuntimeLocalization-install/bin/openmw"
```

Odpowiadający temu log OpenMW jest zwykle zapisywany w:

```text
$HOME/OpenMW-RuntimeLocalization-test/config/openmw/
```

## Dane lokalizacyjne

Fork silnika nie zawiera danych lokalizacyjnych.

Aby przetestować lokalizację w czasie działania, zainstaluj osobno zewnętrzną
warstwę lokalizacyjną i skonfiguruj OpenMW tak, aby ładowało ją jak zwykłą
zawartość. Warstwa lokalizacyjna powinna wypełniać API opisane w
[API_PL.md](API_PL.md).

Zalecany model danych opisano w
[LOCALIZATION_LAYER_PL.md](LOCALIZATION_LAYER_PL.md).

## Rozwiązywanie problemów

### CMake nie może znaleźć zależności

Zwykle oznacza to, że standardowe zależności deweloperskie OpenMW są niepełne
albo CMake nie może znaleźć ich prefiksu instalacji.

Najpierw rozwiąż problem z zależnościami jak dla zwykłego OpenMW. Fork
lokalizacji w czasie działania nie dodaje osobnego stosu zależności.

### Ponowna konfiguracja z czystego katalogu build

Jeżeli cache CMake został utworzony z niezgodnymi ścieżkami zależności albo
ustawieniami generatora:

```bash
rm -rf build
```

Następnie ponownie uruchom polecenie konfiguracji.

### Potwierdzenie wersji kodu źródłowego

```bash
git status -sb
git log --oneline -5
```

Dla powtarzalnych testów zapisuj dokładny commit forka użyty do buildu.
