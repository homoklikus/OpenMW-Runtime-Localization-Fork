# Budowanie w systemie Windows

[English](BUILD_WINDOWS.md) | **Polski**

Ten dokument opisuje planowaną ścieżkę budowania
**OpenMW — Runtime Localization Fork** w systemie Windows.

Fork bazuje na OpenMW 0.51.0 i nie dodaje żadnych zależności zewnętrznych
specyficznych dla Windows. Zmiany lokalizacji w czasie działania są zmianami
silnika w C++/Lua i mają korzystać z tego samego środowiska zależności MSVC co
oryginalne OpenMW 0.51.0.

## Status walidacji

Build tego forka dla Linuxa został przetestowany bezpośrednio.

Build Windows należy traktować jako wymagający niezależnej walidacji przed
publikacją binariów. Poniższe instrukcje celowo wykorzystują toolchain upstream
OpenMW zamiast wprowadzać osobny system zależności specyficzny dla forka.

## Wymagania

Użyj środowiska deweloperskiego odpowiedniego dla OpenMW 0.51.0, obejmującego:

- 64-bitowy toolchain C++ Visual Studio,
- CMake,
- Git,
- biblioteki zewnętrzne wymagane przez OpenMW.

Visual Studio 2022 z pakietem **Desktop development with C++** jest praktycznym
środowiskiem MSVC do budowania kodu źródłowego.

Projekt źródłowy:

https://github.com/OpenMW/openmw

Dokumentacja środowiska deweloperskiego upstream:

https://wiki.openmw.org/index.php?title=Development_Environment_Setup

OpenMW utrzymuje również infrastrukturę do budowania zależności dla
obsługiwanych platform. Używaj wersji zależności zgodnych z bazą źródłową
OpenMW 0.51.0.

## Klonowanie

W PowerShell:

```powershell
git clone https://github.com/homoklikus/OpenMW-Runtime-Localization-Fork.git
Set-Location OpenMW-Runtime-Localization-Fork
```

## Konfiguracja

Otwórz środowisko deweloperskie Visual Studio x64 albo w inny sposób udostępnij
toolchain MSVC dla CMake.

Poniższa konfiguracja odpowiada zredukowanemu buildowi runtime dla Linuxa,
wyłączając aplikacje, które nie są potrzebne do testowania forka silnika:

```powershell
$InstallDir = Join-Path $PWD "install"

cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_INSTALL_PREFIX="$InstallDir" `
  -DOPENMW_USE_SYSTEM_MYGUI=OFF `
  -DBUILD_LAUNCHER=OFF `
  -DBUILD_WIZARD=OFF `
  -DBUILD_MWINIIMPORTER=OFF `
  -DBUILD_OPENCS=OFF `
  -DBUILD_ESSIMPORTER=OFF `
  -DBUILD_BSATOOL=OFF `
  -DBUILD_ESMTOOL=OFF `
  -DBUILD_NIFTEST=OFF `
  -DBUILD_NAVMESHTOOL=OFF `
  -DBUILD_BULLETOBJECTTOOL=OFF
```

Jeżeli środowisko zależności OpenMW wymaga pliku toolchain CMake, ścieżki prefix
albo dodatkowych zmiennych, dodaj te same argumenty, które są wymagane przez
odpowiadający build upstream OpenMW 0.51.0.

Nie zgaduj ścieżek zależności: użyj ścieżek dostarczonych przez zainstalowane
środowisko zależności.

## Budowanie

```powershell
cmake --build build --config RelWithDebInfo --parallel
```

## Instalacja

```powershell
cmake --install build --config RelWithDebInfo
```

Przy powyższym prefiksie pliki runtime zostaną zainstalowane w:

```text
install\
```

## Build przyrostowy

Po zmianach w kodzie źródłowym:

```powershell
cmake --build build --config RelWithDebInfo --parallel
cmake --install build --config RelWithDebInfo
```

## Uruchamianie

Nie zakładaj, że wystarczy skopiować sam plik `openmw.exe`.

OpenMW dla Windows wymaga również odpowiednich bibliotek runtime oraz zasobów
z pasującego środowiska buildu / zależności. Dla pakietów przeznaczonych do
redystrybucji korzystaj z podejścia deployment/packaging upstream OpenMW dla
tej samej generacji kodu źródłowego.

Warstwa lokalizacyjna jest oddzielona od silnika i nie jest częścią binarnego
pakietu Windows, chyba że świadomie dystrybuujesz własną zgodną zawartość
lokalizacyjną osobno.

## Zalecana walidacja

Przed opublikowaniem buildu Windows tego forka sprawdź co najmniej:

1. OpenMW dociera do głównego menu bez błędów brakujących DLL.
2. Zwykła, niezlokalizowana gra uruchamia się poprawnie.
3. Syntetyczna warstwa lokalizacji w czasie działania może wypełnić
   `content.translations`.
4. Nazwy tematów dialogowych przeznaczone do wyświetlenia pozostają oddzielone
   od kanonicznych identyfikatorów tematów.
5. Działa lokalizacja odpowiedzi INFO.
6. Działają teksty wyświetlane `Choice`, napisów `Say` i `MessageBox`.
7. Settery nazw rekordów działają dla kilku reprezentatywnych typów rekordów.
8. `refreshDerivedLocalization()` aktualizuje nazwy wyświetlane pochodne od GMST.
9. Istniejące zapisy gry wczytują się.
10. Build bez żadnej warstwy lokalizacyjnej zachowuje się jak zwykłe OpenMW
    0.51.0 w zmodyfikowanych ścieżkach.

Zobacz [API_PL.md](API_PL.md) oraz
[ARCHITECTURE_PL.md](ARCHITECTURE_PL.md).

## Rozwiązywanie problemów

### CMake nie może znaleźć bibliotek zewnętrznych

Najpierw potraktuj to jako problem środowiska zależności zwykłego OpenMW.
Fork nie dodaje nowego pakietu zależności.

### Niezgodny generator lub architektura

Usuń katalog build i skonfiguruj projekt ponownie:

```powershell
Remove-Item -Recurse -Force build
```

Następnie ponownie uruchom CMake z poziomu środowiska toolchain x64.

### Zapisanie dokładnej wersji buildu

```powershell
git status -sb
git log --oneline -5
```

Przechowuj SHA commita razem z każdym testowym binarium, które dystrybuujesz.
