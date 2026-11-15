# MWGodot — raport z sesji 1 (2026-11-15)

Środowisko: chmura Anthropic, Linux x86_64, 2 CPU, 7 GB RAM, bez GPU (Mesa llvmpipe), Python 3.13,
GCC 13, Godot 4.5.1-stable (oficjalna binarka). Dane gry: **brak** – wszystkie testy na własnych danych
syntetycznych. Komputer użytkownika był niedostępny przez mostek, więc nic nie uruchamiałem lokalnie.

## 1. Architektura konwertera

Szczegóły: `ARCHITEKTURA.md`. W skrócie:

* **mwconv** (Python + numpy + Pillow, bez Blendera i GPU): własne czytniki NIF 4.0.0.2 (80 typów bloków,
  odczyt co do bajtu), ESM/ESP (TES3), BSA (TES3), LAND; zapis GLB bez zewnętrznych bibliotek.
* Każdy NIF → osobny GLB (Y-up, metry, przeliczenie wpisane w dane), tekstury → współdzielone PNG.
* Świat → **„mwgodot-world” v1**: JSON per komórka + teren per komórka + `objects.json` + `index.json`
  + `manifest.json` (źródła z SHA-256). SQLite tylko jako cache konwertera.
* Stabilne ID referencji `"<plik-źródłowy>#<refnum>"`, pełna historia nadpisań i źródeł, kolejność ładowania.
* Konwersja przyrostowa (SHA-256 + wersja konwertera + źródło w VFS), równoległa (procesy), wznawialna
  (zapis postępu po każdym zasobie), z raportem i pomiarami.
* Gra i CS 2.0 korzystają z tej samej warstwy `MWWorldDB` (import + nadpisania projektu).

## 2. Godot w środowisku chmurowym — potwierdzone

| Sprawdzenie | Wynik |
|---|---|
| Godot | 4.5.1.stable.official.f62fdbde1, pobrany z GitHuba |
| Tryb headless (`--headless`, skrypty `-s`, `--import`, edytor `-e --quit-after`) | działa |
| Rendering + zrzuty ekranu | działa przez Xvfb + OpenGL 3 (llvmpipe); Vulkan niedostępny (brak VK_KHR_surface) |
| Python 3.13, numpy 2.5, Pillow 12.3, pytest 9.1 | dostępne |
| Kompilator C++ (GCC 13), scons | dostępne |
| GDExtension (godot-cpp 4.5) | zbudowane w 16 s z profilem klas, wczytane przez Godota, test zaliczony |
| Import modeli i scen (runtime GLTFDocument i import edytorowy) | działa |
| Blender / narzędzia NIF | niepotrzebne – konwerter jest samodzielny |

## 3. Pierwsza rzeczywista konwersja NIF → GLB

Własne modele testowe zapisane w formacie NIF 4.0.0.2 (generator `nif/writer.py`) i przekonwertowane:

| Model | Co testuje | Wynik |
|---|---|---|
| `test_hut.nif` (27 bloków) | NiTriShape + NiTriStrips, normalne, UV, kolory wierzchołków, 3 tekstury DDS (DXT1/DXT5), NiAlphaProperty (test alfa), NiStencilProperty (dwustronność), węzeł z translacją+obrotem 30°+skalą 1.5, marker edytora (MRK), RootCollisionNode | 8 węzłów, 3 siatki, 78 trójkątów, 1 siatka kolizji, marker pominięty, 0 strat |
| `test_windmill.nif` | NiKeyframeController: obroty LINEAR, translacja kwadratowa (Hermite), klucze tekstowe | animacja `default` 4 s, kanały rotation (LINEAR) i translation (CUBICSPLINE) |
| `test_skinned.nif` | NiSkinInstance/NiSkinData, 2 kości, wagi, animacja kości | skin z 2 stawami, JOINTS_0/WEIGHTS_0, IBM |
| `test_crate.nif`, `bsa_crate.nif` | odniesienie skali, odczyt z archiwum BSA | OK |

Weryfikacja wyniku (nie tylko kod wyjścia):
* odczyt NIF „co do bajtu” (0 nadmiarowych bajtów) dla wszystkich modeli;
* **Khronos glTF-Validator: 5/5 plików, 0 błędów**; 1 ostrzeżenie (skinowana siatka nie w korzeniu –
  zgodne ze strukturą NIF, nie wpływa na Godota);
* skala: ściany 256 jedn. = 3,6576 m, wysokość 288 jedn. = 4,1148 m, okap ±144 jedn. — zgodne co do 1e-5 m;
* orientacja: północ MW (+Y) → −Z Godota, góra MW (+Z) → +Y; nawinięcie trójkątów zgodne z normalnymi;
* transformacje węzłów: (100, −160, 150) jedn. → (1,4287; 2,1431; 2,2860) m, obrót 30° wokół Z → 30° wokół Y;
* skin: w pozie wiązania Σ wᵢ·Jᵢ·IBMᵢ·v = v dla wszystkich wierzchołków (błąd < 1e-5);
* animacja: 90° wokół +Y (MW) → 90° wokół −Z (Godot), wartości Hermite zgodne.

## 4. Import do Godota

Test `godot/tests/test_import.gd` — **31/31 sprawdzeń zaliczonych** (ścieżka runtime, ta sama co w grze):
AABB domku (−2,0574; 0; −2,0574)–(2,0574; 4,1148; 2,6289) m, szerokość ścian, tekstura 128 px,
pozycja/skala/obrót szyldu, alpha scissor z progiem 128/255, cull disabled, kolory wierzchołków dachu,
kolizja z RootCollisionNode jako StaticBody3D i niewidoczna siatka kolizji, brak siatki markera,
AnimationPlayer z animacją 4 s i dokładnym obrotem w t = 1 s, Skeleton3D z 2 kośćmi i Skin.
Import edytorowy (ResourceImporterScene) też działa (`test_editor_import.gd`).

Zrzuty ekranu (Xvfb + OpenGL 3): `shot_models.png` (modele testowe: domek, wiatrak, zgięta rura ze
skinem, skrzynka) i `shot_world.png` (świat Synthville: 4 komórki terenu, 19 referencji).

## 5. Reprezentacja komórek świata (v1)

Przykład referencji (komórka `cells/ext/0_1.json`, chata przesunięta przez plugin):

```json
{"sid": "mwg_synthtown.esm#1", "base": "synth_hut",
 "mw": {"pos": [1400.0, 8600.0, 488.0], "rot": [0.0, 0.0, 1.570796], "scale": 1.2},
 "godot": {"origin": [20.0025, 6.9723, -122.8725], "quat": [0.0, -0.7071068, 0.0, 0.70710677], "scale": 1.2},
 "source": "mwg_synthtown_patch.esp", "origin": "mwg_synthtown.esm", "overridden": ["mwg_synthtown.esm"]}
```

Przetestowane scalanie (`test_world.py`, Synthville = ESM + 2 ESP): nadpisanie referencji mastera,
usunięcie (DELE), nowa referencja pluginu, przeniesienie do innej komórki (MVRF/CNDT), podmiana LAND,
LTEX lokalne dla pliku z dziedziczeniem z masterów, drzwi z celem (DODT/DNAM), światła (LHDT).
Teren: wysokości VHGT (dekoder zweryfikowany odwrotnym koderem), normalne, VCLR, VTEX (transpozycja
bloków 4×4), triangulacja „diamond” jak w grze, kolizja trimesh zgodna z danymi co do 1 cm.

## 6. Construction Set 2.0 — stan prototypu

Działa (wtyczka `addons/mw_cs2`, logika w `MWCellEditing`, testy headless):
* panel w edytorze Godota: wczytanie świata, filtr i lista komórek, otwarcie komórki jako sceny roboczej;
* zaznaczanie referencji w widoku 3D, przesuwanie/obracanie/skalowanie gizmem Godota, usuwanie (Delete,
  z cofaniem), dodawanie obiektów z listy rekordów bazowych (z cofaniem), podgląd sid/bazy/źródła/pozycji MW;
* zapis **nadpisań projektu** (`modified`/`added`/`deleted`) – ESM/ESP nigdy nie są nadpisywane;
* scena robocza `.tscn` zawiera tylko transformacje i metadane (zweryfikowane: brak siatek i ścieżek do
  zasobów gry); modele i teren odtwarzane z danych gracza przy otwarciu;
* **ponowny import z nowym pluginem zachowuje zmiany projektu** (test `--phase=verify`: zmieniona,
  dodana i usunięta referencja przetrwały, referencja z nowego ESP widoczna).

Jeszcze nie ma: edycji terenu, edycji pól rekordów bazowych, wielu zaznaczeń w panelu, podglądu
konfliktów modów, eksportu do ESP/omwaddon.

## 7. Testy i benchmarki

| Zestaw | Wynik |
|---|---|
| pytest (konwerter) | 19/19 |
| Khronos glTF-Validator | 5/5 GLB bez błędów |
| Godot `test_import.gd` | 31/31 |
| Godot `test_editor_import.gd` | OK |
| Godot `test_world.gd` (budowa świata, fizyka, postać, CS 2.0) | 30/30 |
| Godot `test_world.gd --phase=verify` (ponowny import) | 8/8 |
| Godot `test_gdextension.gd` | OK |
| `tools/run_tests.sh` (całość od zera) | zaliczony |

Benchmark syntetyczny (`tools/bench.py`, 2 CPU): 2004 modeli NIF (9,6 MB), 408 tekstur DDS 256 px,
ESM 33,7 MB (34 tys. rekordów, 2500 komórek, 100 tys. referencji, 1400 LAND).

| | 1 proces | 2 procesy |
|---|---|---|
| modele | 2,78 s (722/s, śr. 1,3 ms) | 1,35 s (1481/s) |
| tekstury | 0,33 s (1237/s) | 0,34 s |
| wczytanie ESM + scalanie | 1,35 s | 1,34 s |
| szczytowe RSS (proces główny, z danymi świata) | 300 MB | 300 MB |
| rozmiar wyników | 19,1 MB (GLB 15,5 MB) | |
| ponowny przebieg bez zmian | 1,56 s (głównie ponowne parsowanie ESM) | |

**Nie przyjmuję czasu dla prawdziwej gry.** Modele syntetyczne są małe (10–200 trójkątów), a tekstury
proceduralne kompresują się do PNG wyjątkowo dobrze; rzeczywiste NIF-y i tekstury 256–1024 px będą
wolniejsze. Pierwszy realny pomiar: konwersja Balmory na Twoim Debianie (polecenie w `DEBIAN13.md`),
potem `--all-cells --all-models --all-textures` – raport zapisze czasy, przepustowość, RAM i rozmiary.

## 8. Ograniczenia i brakujące funkcje

Konwerter NIF:
* nie konwertowane (pomijane z wpisem w raporcie): systemy cząsteczek, NiVisController, NiUVController,
  NiAlphaController, NiMaterialColorController, NiFlipController, NiGeomMorpherController (morfy),
  NiPathController/NiLookAtController, światła i NiTextureEffect w NIF, tekstury wewnętrzne (NiPixelData);
* sloty dark/detail/gloss/bump/decal tylko w `extras` (potrzebny własny shader);
* obroty TBC interpolowane liniowo; częstotliwość/faza kontrolera przybliżone; pliki `.kf`
  (animacje postaci) i podział animacji wg kluczy tekstowych – jeszcze nie;
* postacie NPC (składanie z części ciała BODY/rasy) – nie;
* czytnik NIF przetestowany tylko na własnych plikach – **pierwszy test na prawdziwych NIF-ach
  Morrowinda jest najważniejszym kolejnym krokiem** (układ pól odpowiada nif.xml, ale bez realnych
  danych to hipoteza).

Świat i runtime:
* mieszanie tekstur terenu jest przybliżone (bez znanego przesunięcia mapy tekstur względem OpenMW –
  do kalibracji na prawdziwych danych, MCP-openMW ma już narzędzie do tej hipotezy);
* brak wody, nieba/pogody, regionów, NPC/AI, skryptów MWScript, dźwięku, UI, przejść drzwi;
* MVRF obsługiwane w uproszczeniu (referencja przenoszona do komórki z CNDT);
* ESM parsowany przy każdym przebiegu (do dodania cache świata wg SHA-256 plików);
* RSS ~300 MB dla 100 tys. referencji – dalsze oszczędności: `__slots__`, leniwe dekodowanie LAND;
* oświetlenie scen testowych za jasne dla terenu (kosmetyka, ustawienia środowiska);
* GLB → natywne `.scn` z teksturami VRAM (etap 2 przez nasz Godot headless) – jeszcze nie.

## 9. Uruchomienie na Debianie 13

Pełna instrukcja: `DEBIAN13.md`. Najkrócej:

```bash
sudo apt install python3 python3-numpy python3-pil python3-pytest xvfb
# Godot 4.5.1: oficjalna binarka z GitHuba (instrukcja w DEBIAN13.md)
GODOT=godot ./tools/run_tests.sh
cd converter && python3 -m mwconv convert --openmw-cfg <ścieżka>/openmw.cfg --cell Balmora \
    --grid-range=-4,-4,-1,-1 --out ~/.local/share/mwgodot/mwdata
godot --path ../godot -- --data=$HOME/.local/share/mwgodot/mwdata
```

## Następne kroki (proponowane)

1. Konwersja Balmory na Twoim komputerze (dane zostają lokalnie) → poprawki czytnika NIF/ESM wg raportu.
2. Kalibracja terenu i materiałów z porównaniem do OpenMW (MCP-openMW, tryb tylko-do-odczytu).
3. Kontrolery: widoczność, UV, kolor materiału, flip; cząsteczki → GPUParticles3D.
4. Animacje postaci (`.kf`), składanie NPC.
5. Cache świata, wypiekanie `.scn` z teksturami VRAM, pomiary pełnej gry.
6. CS 2.0: edycja terenu, właściwości rekordów, widok konfliktów modów.
