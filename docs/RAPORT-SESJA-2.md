# MWGodot — raport z sesji 2 (2026-11-15, po południu)

Zakres: punkty 1–6 z planu „bez dostępu do PC”. Dane: wyłącznie własne, syntetyczne. Każdy punkt jest
pokryty testami automatycznymi, a cały zestaw przechodzi na **Godot 4.7.1 i 4.5.1**.

## 0. Zgodność z Godot 4.7

Pełny zestaw testów uruchomiłem na 4.7.1. Wykryta i poprawiona różnica: importer glTF w 4.7 nie włącza już
sam `vertex_color_use_as_albedo` — loader ustawia to jawnie. GDExtension zbudowane dla 4.5 działa w 4.7.

## 1. Przygotowanie na prawdziwe pliki NIF

* Zapis NIF obejmuje teraz prawie wszystkie bloki czytnika (brak tylko NiPalette i NiSkinPartition).
* `synthetic_hard.py` – 4 trudne modele + plik `.kf`: przełączniki, LOD, billboard, sort adjust, collision
  switch, kamera, światła (z listą efektów), NiTextureEffect, 2 zestawy UV i sloty dark/detail/gloss/glow,
  tekstura wewnętrzna NiPixelData, 7 typów właściwości, ukryty węzeł, macierz ze ścinaniem, indeks poza
  zakresem, zerowe normalne, dodatkowe dane, 9 typów kontrolerów, klucze XYZ i TBC, kontroler z
  częstotliwością 2, dwa systemy cząsteczek ze wszystkimi modyfikatorami i koliderami, skin z 5 wpływami.
* 6 plików celowo uszkodzonych (ucięty, pusty, zły nagłówek, zła wersja, nieznany blok, absurdalny
  licznik) – każdy daje czytelny `NifError`, nigdy wyjątek Pythona.
* `NifError` niesie lokalizację: numer i typ bloku, offset początku bloku i błędu, listę bloków odczytanych
  poprawnie; przy „śmieciach” zamiast nazwy typu podpowiada, że poprzedni blok był źle odczytany.
* `mwconv inspect plik.nif [--convert]` – lista bloków; przy błędzie ostatnie poprawne bloki i zrzut bajtów
  z zaznaczonym miejscem błędu.
* `mwconv scan` – odczyt + konwersja w pamięci **wszystkich** NIF/KF z instalacji, raport JSON: błędy
  pogrupowane (z przykładami), histogram typów bloków, straty konwersji, brakujące tekstury, najwolniejsze
  pliki. **To pierwsze polecenie do uruchomienia u Ciebie** – raport zawiera tylko metadane.
* Tekstury wewnętrzne (NiPixelData RGB/RGBA) osadzane w GLB jako PNG.

## 2. Kontrolery, cząsteczki, animacje

| Element NIF | Wynik w Godocie | Test |
|---|---|---|
| NiVisController | ścieżka `visible` | ukryty w t=0,6 s, widoczny w t=0,2 s |
| NiUVController | `uv1_offset` materiału | (0,5; 0,25) w t=1 s |
| NiAlphaController | alfa `albedo_color` | 0,2 w t=1 s |
| NiMaterialColorController (diffuse/emissive) | `albedo_color` / `emission` | odtwarzacz utworzony |
| NiFlipController | podmiana `albedo_texture` | druga tekstura w t=0,3 s |
| NiGeomMorpherController | natywne morph targets glTF + kanał weights | waga 1,0 w t=1 s |
| NiPathController | próbkowana ścieżka translacji | x = 50 jedn. w połowie |
| NiLookAt/NiRollController | opis w extras (rzadkie, bez odtwarzania) | – |
| cząsteczki + modyfikatory | CPUParticles3D pod węzłem emitera, gradient koloru, krzywa grow/fade, grawitacja, mieszanie addytywne | 2 systemy, parametry z NIF |
| `.kf` (NiSequenceStreamHelper) | `*.anim.json` → AnimationPlayer z klipami wg kluczy tekstowych, tory trafiają w kości Skeleton3D | klipy idle/bend, Bone2 90° w t=1 s, pętla |

Poprawiony błąd semantyki czasu: czas klucza = czas sceny · frequency + phase (wcześniej odwrotnie).

## 3. Świat w Godocie

* Woda: płaszczyzna z prostym shaderem w każdej komórce zewnętrznej (poziom 0) i we wnętrzach z flagą wody.
* Drzwi: klawisz E (promień 3 m), cel z DODT/DNAM; wejście do wnętrza zwalnia świat, wyjście wraca do
  strumieniowania.
* Pora dnia: skala czasu 30 jak w grze, słońce, kolor nieba i światło otoczenia; pogoda losowana
  deterministycznie (dzień + region) z szans rekordu REGN, mgła wg pogody; wnętrza: kolor otoczenia
  i mgły z AMBI.
* Konwerter eksportuje `regions.json` (REGN: nazwa, szanse pogody, kolor mapy, dźwięki) oraz flagi wody
  i kolory AMBI w komórkach.
* HUD: region/wnętrze, dzień i godzina, pogoda, podpowiedź „[E] nazwa obiektu”.

## 4. Szybciej i lżej

| Benchmark syntetyczny (2 CPU) | sesja 1 | sesja 2 |
|---|---|---|
| szczytowe RSS przy wczytaniu ESM 33,7 MB / 100 tys. referencji | 300 MB | **215 MB** |
| przebieg bez zmian | 1,56 s | **0,26 s** (1 proces) / 0,33 s (2) |
| modele (2 procesy) | 1481/s | 1279/s (więcej pracy: kontrolery, morfy) |
| wczytanie ESM | 1,34 s | 0,94–1,03 s |

* ESM czytany strumieniowo, `slots` w strukturach, wysokości float32.
* Przebieg bez zmian pomija ESM i eksport świata (SHA-256 plików treści + wybór + VFS + wersja).
  Sprawdziłem też cache świata w pickle: zysk był mały (0,9 vs 1,4 s), plik 100 MB, więcej RAM – odrzucony.
* **Wypiekanie** (`--bake-godot`): GLB → `.scn` + tekstury `PortableCompressedTexture2D` (S3TC; BPTC/ETC2/ASTC
  do wyboru), współdzielone i deduplikowane, przyrostowo. Loader sam wybiera wypieczoną scenę. Na modelach
  testowych wczytanie 2,9× szybsze (4,8 vs 14,0 ms dla 6 modeli); zysk na prawdziwych teksturach będzie
  większy (bez dekodowania PNG i kompresji w trakcie gry). Wypiekanie wymaga binarki edytora Godota
  (moduły kompresji) – u gracza to ten sam plik, którego używa launcher.

## 5. Construction Set 2.0

* **Teren**: pędzle podnieś/obniż/wygładź/spłaszcz/maluj teksturę, działające w układzie świata na wszystkich
  komórkach w zasięgu (krawędzie bez szczelin – sprawdzone co do 1e-5 m), przeliczanie normalnych,
  podgląd na żywo w widoku 3D (raycast w teren), zapis do `overrides/terrain/<x>_<y>.json`; gra widzi zmiany.
* **Rekordy**: pola referencji (JSON w panelu) i rekordy bazowe (`overrides/objects.json`, np. nazwa, model,
  światło) – nakładane przez `MWWorldDB` w grze i edytorze.
* **Konflikty modów**: lista referencji zmienianych przez kilka plików z łańcuchem (ESM → ESP → projekt);
  konwerter zapisuje też historię nadpisań rekordów bazowych.

## 6. Launcher / instalator

* Scena startowa projektu: wykrywanie instalacji (openmw.cfg natywny i Flatpak, Steam, GOG/Wine) albo wybór
  ręczny, sprawdzenie Pythona/numpy/Pillow z podpowiedzią instalacji, wybór zakresu (Balmora i okolice /
  cała gra), wypiekanie, konwersja w tle z paskiem postępu (`--progress-json`, czytanie w osobnym wątku),
  przycisk „Graj”, ustawienia w `user://`.
* Test na układzie katalogów identycznym jak w grze (syntetyczny ESM pod nazwą `Morrowind.esm`,
  `Morrowind.ini`, `Morrowind.bsa`): wykrycie, konwersja, postęp do 100%, gotowość danych.
* Do zrobienia przy wydaniu: dołączenie Pythona z konwerterem (np. PyInstaller), żeby gracz nic nie instalował.

## Testy

| Zestaw | Wynik |
|---|---|
| pytest | 38/38 |
| glTF-Validator | 8/8 GLB bez błędów (w tym morfy i tekstury osadzone) |
| test_import | 31/31 |
| test_controllers | 20/20 |
| test_game | 16/16 |
| test_cs2 | 14/14 |
| test_world (budowa + CS) / verify | zaliczone / 8/8 |
| test_bake, test_editor_import, test_gdextension | zaliczone |
| test_launcher | 9/9 |
| całość `tools/run_tests.sh` | zaliczona na 4.7.1 i 4.5.1 |

## Ograniczenia (aktualne)

* Wszystko nadal sprawdzone tylko na danych syntetycznych – **skan NIF i konwersja Balmory na Twoim
  komputerze to następny krok**.
* NiLookAt/NiRollController, kolidery cząsteczek i bomba – tylko opisane; ambient/specular z
  NiMaterialColorController nie mają odpowiednika w BaseMaterial3D.
* Kierunki i siły cząsteczek przybliżone; nie ma jeszcze cząsteczek emitowanych z siatki.
* Animacje postaci: biblioteka klipów działa, ale nie ma jeszcze składania NPC z części ciała ani maszyny
  stanów animacji.
* Pogoda bez opadów i dźwięków; brak nieba z NIF-ów gry (sky_*.nif) i chmur.
* Launcher wymaga systemowego Pythona; brak paczki wydania.
* Edycja terenu bez cofania (undo) i bez podglądu pędzla.
