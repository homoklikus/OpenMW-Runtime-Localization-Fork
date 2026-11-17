# first-fish – pierwszy natywny mod OpenMWGodot (eksperyment)

Mała ryba przybrzeżna w stylu Vvardenfell (low-poly, ciemnoturkusowy grzbiet, ochrowe pasy, rdzawe płetwy,
kolczasty grzebień grzbietowy) pływająca na płyciźnie przy pomoście Seyda Neen. Minimalny prototyp – **nie** system
fauny: bez kolizji, walki, łupów, dźwięków i zapisu stanu.

Wszystko w tym katalogu jest własnym zasobem projektu – model, tekstura i animacja powstają ze skryptu
`blender/build_fish.py`. Żadnych zasobów Morrowinda ani cudzych modeli.

## Pliki

| Plik | Co to |
|---|---|
| `mod.json` | opis modu: stworzenie (model, animacja, skrypt zachowania, parametry) i miejsce pojawiania się |
| `blender/build_fish.py` | źródło assetu: siatka, UV, tekstura, materiał, szkielet, wagi, animacja, eksport |
| `blender/first_fish.blend` | wynik w formacie Blendera (do ręcznej edycji) |
| `models/first_fish.glb` | eksport glTF 2.0: 83 wierzchołki, 128 trójkątów, szkielet 4 kości, animacja `swim_idle`, tekstura osadzona |
| `textures/first_fish_albedo.png` | tekstura 128×128 (ta sama co w GLB), generowana proceduralnie |
| `scripts/fish_swim.gd` | zachowanie: błądzenie w małym obszarze wody |
| `scenes/` | pusty – rybka nie potrzebuje sceny Godota (model wczytywany w czasie działania) |

## Pipeline Blender → glTF → Godot

1. `blender --background --python mods/first-fish/blender/build_fish.py` (albo moduł `bpy` z PyPI:
   `python -c "import runpy; runpy.run_path('mods/first-fish/blender/build_fish.py')"`, Blender 5.3).
   Skrypt buduje wszystko od zera: profil korpusu z 8 pierścieni po 8 wierzchołków, płetwy jako płaskie wielokąty,
   UV (korpus w górnej połowie tekstury, płetwy w dolnej), teksturę (numpy), materiał Principled BSDF
   (tekstura bez filtrowania, chropowatość 0,55, dwustronny), szkielet `head → spine → tail1 → tail2` z wagami
   liniowymi wzdłuż ryby i akcję `swim_idle` w ścieżce NLA.
2. Eksport GLB (`export_yup`): Blender Z w górę i głowa w +Y → glTF Y w górę i głowa w **−Z** (przód węzła
   Godota). Skala 1 jednostka = 1 m, długość ok. 0,36 m z płetwą ogonową.
3. Godot nie importuje pliku do projektu: `godot/scripts/mw/mw_native_mods.gd` wczytuje GLB w czasie działania
   (`GLTFDocument.append_from_file` + `generate_scene`) – mod można podmienić bez przebudowy projektu. Materiał
   glTF staje się `StandardMaterial3D` z teksturą albedo i bez odrzucania tylnych ścian.

## Animacja i zachowanie

* `swim_idle`: 1 s, 24 kl./s, interpolacja liniowa, klatka końcowa = początkowa. Fala biegnie od głowy do ogona:
  obrót kości wokół osi pionowej z amplitudą 3° / 6° / 12° / 22° i opóźnieniem fazy 0,7 rad na kość. Godot
  ustawia pętlę i gra ją z prędkością zależną od tempa pływania; każda rybka startuje w innej fazie.
* `fish_swim.gd`: cel losowany w kole o promieniu `radius` wokół punktu domowego, tylko tam, gdzie woda ma co
  najmniej `min_depth + min_clearance`; kurs zmienia się płynnie (`turn_rate_deg`), prędkość ok. 0,25 m/s ±30 %,
  nowy cel co 4–9 s albo po dotarciu. Wysokość zawsze między dnem terenu + 0,2 m a lustrem wody − 0,25 m – nie
  wyskakuje i nie wbija się w dno; płycizna przed nosem → nowy cel.

## Gdzie jest rybka

`mod.json` → `spawns`: 3 rybki, środek (−9200, −72900) w jednostkach Morrowinda, promień 260 j. (3,7 m) – płycizna
przy pomoście Seyda Neen (obok strażnika na nabrzeżu), 1,6–2,9 m wody. Rybki pojawiają się przy wczytaniu komórki
(−2, −9) jako dzieci jej węzła i znikają razem z nią; nie trafiają do zapisu gry.

Ładowarka szuka modów w `mods/` obok katalogu `godot/` (inny katalog: `--mods=ŚCIEŻKA` albo ustawienie
`native_mods_dir`; `--mods=` bez ścieżki wyłącza mody).

## Testy

```
godot --headless --path godot -s res://tests/test_first_fish.gd                 # 19 sprawdzeń, bez danych gry
godot --headless --path godot -s res://tests/probe_first_fish.gd -- --data=WYNIKI --project=KATALOG \
      --start="Seyda Neen" --scripts=0                                              # prawdziwe dane, 60 s
```

`test_first_fish.gd` (też w `tools/run_tests.sh`): import GLB, rozmiar i osie, szkielet, materiał, animacja (pętla,
wygięcie ogona), 3 rybki przez 120 s symulacji nad nierównym dnem (pas wody, obszar, droga, zmiany kursu).
`probe_first_fish.gd`: 3 rybki w świecie przy pomoście, 60 s pływania, animacja, brak błędów; z `PROBE_SHOTS=katalog`
na ekranie (np. Xvfb) zrzut zbliżenia – tylko lokalnie, bo zawiera obraz gry.

## Ograniczenia

* Brak kolizji z obiektami (pale pomostu, kamienie) – dno to tylko teren komórki zewnętrznej.
* Tylko komórki zewnętrzne i jedna wysokość wody komórki; brak ucieczki przed graczem, ławicy, dnia i nocy.
* Brak interakcji: nie da się złowić, zabić ani zebrać; brak dźwięków i zapisu stanu.
* Skrypt zachowania z katalogu modu jest wykonywany jak kod gry – mody z obcych źródeł wymagałyby piaskownicy
  albo listy dozwolonych skryptów (poza zakresem eksperymentu).
* Oświetlenie i mgła podwodna – takie jak reszta świata w OpenMWGodot.
