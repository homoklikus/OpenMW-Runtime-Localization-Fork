# MWGodot — architektura (sesja 1)

## Zasada nadrzędna

Oryginalne formaty Morrowinda (NIF, ESM/ESP, BSA, LAND, DDS/TGA) są **wyłącznie wejściem**. Konwerter
uruchamiany lokalnie u gracza tworzy z nich nowoczesne formaty; Godot nigdy nie czyta plików Bethesdy.
W repozytorium i wydaniach są tylko kod i własne dane syntetyczne.

```
Instalacja gracza (Data Files, BSA, ESM/ESP)          ── tylko u gracza
        │  mwconv (Python 3 + numpy + Pillow, bez Blendera, bez GPU)
        ▼
<wyniki>/meshes/**.glb      glTF 2.0, jeden plik na NIF, tekstury jako zewnętrzne PNG
<wyniki>/textures/**.png    tekstury (kompresję VRAM robi Godot)
<wyniki>/world/…            model danych świata „mwgodot-world” v1 (JSON)
<wyniki>/reports/…          diagnostyka konwersji + pomiary
<wyniki>/.mwconv/cache.sqlite   SHA-256, wersje konwertera, zależności, wznawianie
        │
        ▼
Godot 4.5 (gra)  ←── ta sama warstwa danych ──→  Construction Set 2.0 (wtyczka edytora Godota)
                                                        │
                                                        ▼
                                <projekt>/overrides/cells/**.json  (zmiany projektu, nigdy ESM/ESP)
```

## Konwerter `mwconv` (katalog `converter/`)

| Moduł | Rola |
|---|---|
| `binio.py` | odczyt/zapis little-endian, ochrona przed absurdalnymi licznikami |
| `nif/reader.py` | pełny czytnik NIF 4.0.0.2/4.0.0.0 – 80 typów bloków Morrowinda, odczyt „co do bajtu” (format nie zapisuje rozmiarów bloków, więc nieznany typ ⇒ błąd, nie zgadywanie) |
| `nif/writer.py` | zapis NIF (podzbiór) – tylko do tworzenia własnych modeli testowych |
| `nif2gltf.py` | NIF → glTF: hierarchia, TRS, geometria (TriShape/TriStrips), normalne, UV×2, kolory wierzchołków, materiały, tekstury (sampler z clamp/filter), alfa (BLEND/MASK + extras dla trybów addytywnych), dwustronność (NiStencilProperty), RootCollisionNode, markery, skin (JOINTS/WEIGHTS + inverseBindMatrices), animacje NiKeyframeController (LINEAR/STEP/CUBICSPLINE z Hermite i TBC, XYZ→kwaterniony), klucze tekstowe, raport diagnostyczny |
| `coords.py` | jedno źródło prawdy o układach współrzędnych |
| `gltf.py` | zapis GLB bez zależności (numpy) + odczyt do testów |
| `textures.py` | DDS/TGA/BMP → PNG (Pillow), wykrywanie kanału alfa |
| `vfs.py` | VFS: katalogi danych + BSA TES3 (czytnik i zapis testowy), bez rozróżniania wielkości liter, priorytety, pochodzenie pliku, rozwiązywanie ścieżek tekstur jak w grze (`textures\`, preferencja `.dds`) |
| `esm/reader.py` | TES3: nagłówek i mastery, rekordy z modelem, LIGH, CELL (+ referencje, MVRF/CNDT, DELE, drzwi), LAND (VHGT/VNML/VCLR/VTEX), LTEX |
| `esm/writer.py` | zapis ESM/ESP do światów syntetycznych |
| `world.py` | scalanie wg kolejności ładowania, stabilne ID, eksport komórek/terenu/obiektów |
| `install.py` | wykrywanie konfiguracji: `openmw.cfg` lub `Morrowind.ini` + „Data Files” |
| `cache.py`, `pipeline.py` | konwersja przyrostowa, równoległa, wznawialna, z raportem i pomiarami |
| `synthetic*.py` | własne dane testowe („Synthville”) |

### Układ współrzędnych

* Morrowind/NIF: prawoskrętny, Z w górę, +Y = północ, jednostki gry.
* glTF/Godot: prawoskrętny, Y w górę, metry.
* `godot(x, y, z) = (mw_x, mw_z, −mw_y) / 69.99125109` (stała `UnitsPerMeter` z OpenMW). Odwzorowanie
  jest obrotem (det = +1), więc nawinięcie trójkątów się nie zmienia.
* Konwersja jest **wpisywana w dane** (wierzchołki, transformacje węzłów, macierze skinu, klatki
  kluczowe), a nie realizowana węzłem-korzeniem z obrotem — GLB są „czystymi” plikami Y-up w metrach,
  a fizyka Godota nie dostaje skalowanych ciał.
* Obrót referencji ESM: `R = Rx(−rx)·Ry(−ry)·Rz(−rz)` (wektory kolumnowe), w Godocie `M·R·Mᵀ`.
* Korzeń NIF ma zerowaną transformację (jak w silniku), chyba że nazywa się „Bip01”.

### Dlaczego GLB z zewnętrznymi PNG

Tysiące modeli współdzieli te same tekstury; osadzanie w GLB zwielokrotniłoby rozmiar i czas. PNG to
bezstratny format pośredni. **Etap 2** (planowany): nasz własny binarny Godot uruchamiany headless
u gracza wypieka GLB → natywne `.scn` z teksturami VRAM (BCn/ETC2), co skróci ładowanie w grze.

## Model danych świata „mwgodot-world” v1

Wybór: **tekstowe pliki JSON per komórka** jako format kanoniczny + **SQLite tylko jako cache
konwertera**. Uzasadnienie:

* komórka to naturalna jednostka strumieniowania i edycji — brak gigantycznej sceny / jednego GLB;
* JSON czyta natywnie Godot (gra i edytor) bez rozszerzeń; diffy w Gicie są czytelne (mody, przeglądy);
* SQLite po stronie konwertera daje transakcyjny zapis postępu (wznawianie) i szybkie zapytania;
* gdy rozmiar zacznie przeszkadzać (pełna gra ~2,5 tys. komórek zewn. + ~1,5 tys. wnętrz), ten sam model
  można spakować do binarnego „packa” bez zmiany API `MWWorldDB`.

Pliki: `manifest.json` (źródła z SHA-256, mastery, ostrzeżenia), `index.json`, `objects.json`,
`cells/ext/<x>_<y>.json`, `cells/int/<slug>.json`, `terrain/<x>_<y>.json` (wysokości/normalne/kolory
w base64, paleta tekstur + mapa 16×16).

**Stabilny identyfikator referencji**: `"<plik-który-ją-utworzył>#<refnum>"` (indeks mastera z FRMR
rozwiązywany przez nagłówek pluginu). Referencja ma też `source` (plik dostarczający obowiązującą
wersję) i `overridden` (historia nadpisań). LTEX rozwiązywane per plik z dziedziczeniem z masterów.

### Warstwy i Construction Set 2.0

1. **import** — `world/` z konwertera, tylko do odczytu, odtwarzalny w każdej chwili;
2. **projekt** — `overrides/cells/*.json`: `modified` (sid → nowe pola), `added` (sid `project#N`),
   `deleted` (lista sid).

`MWWorldDB.get_cell()` nakłada projekt na import. Ponowny import modów (nowe/zmienione ESP) przebudowuje
warstwę 1, a zmiany projektu trafiają w te same `sid`. Nadpisania bez celu (referencja usunięta przez
mod) są raportowane jako `override_orphans`. ESM/ESP nigdy nie są zapisywane.

## Godot (katalog `godot/`)

| Skrypt | Rola |
|---|---|
| `scripts/mw/mw_coords.gd` | lustrzane `coords.py` (+ odwrotność obrotu dla edytora) |
| `scripts/mw/mw_model_cache.gd` | GLB w czasie działania (GLTFDocument) — wyeksportowana gra nie może importować zasobów; obróbka wg `extras` (kolizje, ukryte węzły, tryby mieszania, billboardy), cache PackedScene |
| `scripts/mw/mw_world_db.gd` | warstwa danych wspólna dla gry i edytora |
| `scripts/mw/mw_terrain.gd` + `shaders/mw_terrain.gdshader` | siatka 65×65 (triangulacja „diamond” jak w grze), Texture2DArray z palety, mieszanie kafli, VCLR, kolizja trimesh |
| `scripts/mw/mw_cell_builder.gd` | węzeł komórki: teren + referencje (meta `mw_sid`/`mw_base`/`mw_source`) + światła LIGH |
| `scripts/mw/mw_cell_editing.gd` | logika CS 2.0: otwarcie, dodawanie, różnice, zapis nadpisań |
| `scripts/main.gd`, `scripts/player.gd` | gra: strumieniowanie komórek wokół gracza, postać 1-os. (WASD, skok, bieg, latanie) |
| `addons/mw_cs2/` | wtyczka edytora: panel, lista komórek, otwieranie jako scena robocza, informacje o referencji, dodawanie obiektów (z undo), zapis nadpisań |

Scena robocza CS 2.0 (`res://cs2_cells/*.tscn`) zawiera **tylko** transformacje i metadane referencji;
modele i teren są dziećmi bez właściciela, odtwarzanymi przy otwarciu przez `mw_cell_root.gd` z danych
gracza. Zweryfikowane testem: plik `.tscn` nie zawiera siatek ani ścieżek do zasobów gry.

## GDExtension

`gdextension/` – minimalne rozszerzenie C++ (godot-cpp 4.5) z natywnym dekoderem VHGT. Służy jako
sprawdzony szkielet pod przyszłe przyspieszenia (np. wczytywanie terenu, ewentualnie warstwa zgodności
MWScript). Kod OpenMW (GPLv3) nie jest w nim używany — patrz `LICENCJE.md`.
