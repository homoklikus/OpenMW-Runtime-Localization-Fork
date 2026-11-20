"""Strona „Ustawienia”: Grafika, Dźwięk, Sterowanie, Język, Zaawansowane. Tylko opcje obsługiwane przez Runtime
(schemat w mwcore.settings). Ustawienia gry są per profil, ścieżki i język – globalne."""

from __future__ import annotations

import subprocess
from pathlib import Path

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout, QHBoxLayout, QLabel,
                               QLineEdit, QPushButton, QSpinBox, QTabWidget, QVBoxLayout, QWidget)

from mwcore import conversion, launch
from mwcore.settings import GAME_SCHEMA

from .art import serif_font
from .i18n import N_, get_lang, tr

CHOICE_LABELS = {"windowed": N_('okno'), "fullscreen": N_('pełny ekran'), "exclusive": N_('pełny ekran (wyłączny)'),
                 "off": N_('wyłączone'), "low": N_('niska'), "medium": N_('średnia'), "high": N_('wysoka')}


class SettingsPage(QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        lay = QVBoxLayout(self)
        lay.setContentsMargins(14, 10, 14, 10)
        top = QHBoxLayout()
        self.title = QLabel(tr("Ustawienia"))
        self.title.setFont(serif_font(24))
        self.title.setProperty("class", "cardtitle")
        top.addWidget(self.title, 1)
        lay.addLayout(top)
        self.tabs = QTabWidget()
        lay.addWidget(self.tabs, 1)
        self.widgets = {}
        forms = {}
        for sec, name in (("graphics", tr('Grafika')), ("audio", tr('Dźwięk')), ("controls", tr('Sterowanie')),
                          ("language", tr('Język')), ("world", tr('Świat')), ("advanced", tr('Zaawansowane'))):
            w = QWidget()
            f = QFormLayout(w)
            forms[sec] = f
            self.tabs.addTab(w, name)
        for o in GAME_SCHEMA:
            label = o.label_en if get_lang() == "en" else o.label_pl
            if o.kind == "bool":
                wdg = QCheckBox()
            elif o.kind == "int":
                wdg = QSpinBox()
                wdg.setRange(int(o.lo), int(o.hi))
            elif o.kind == "float":
                wdg = QDoubleSpinBox()
                wdg.setDecimals(4 if o.hi < 0.1 else 2)
                wdg.setSingleStep((o.hi - o.lo) / 20)
                wdg.setRange(o.lo, o.hi)
            elif o.key == "resolution":
                wdg = QComboBox()          # standardowe + natywne rozdzielczości ekranów (np. 3440x1440)
                self._fill_resolutions(wdg, "")
            elif o.key == "game_language":
                wdg = QComboBox()          # wypełniana w refresh() językami z bieżącej konwersji
            elif o.kind == "str":
                wdg = QLineEdit()
                wdg.setPlaceholderText(tr('puste = wyłączone'))
            else:
                wdg = QComboBox()
                for c in o.choices:
                    wdg.addItem(tr(CHOICE_LABELS.get(c, c)), c)
            self.widgets[o.key] = (o, wdg)
            forms[o.section].addRow(label, wdg)
        info = QLabel(tr('Dźwięk, napisy, mysz i część grafiki można też zmienić w grze (Esc → Ustawienia).'))
        info.setWordWrap(True)
        info.setProperty("class", "muted")
        forms["audio"].addRow(info)
        self.lang = QComboBox()
        self.lang.addItem("Polski", "pl")              # nazwy języków w ich własnym języku
        self.lang.addItem("English", "en")
        forms["language"].addRow(tr('Język launchera'), self.lang)
        self.lang.currentIndexChanged.connect(self._lang_changed)   # od razu, bez ponownego uruchomienia
        self.lang_info = QLabel("")
        self.lang_info.setWordWrap(True)
        self.lang_info.setProperty("class", "muted")
        forms["language"].addRow("", self.lang_info)
        # świat: roślinność (odpowiednik world.cfg forka OpenMW RLF) – liczona przy konwersji
        f = forms["world"]
        self.fl_enabled = QCheckBox(tr('Roślinność generowana przy konwersji ([flora] enabled)'))
        f.addRow("", self.fl_enabled)
        self.fl_source = QComboBox()
        self.fl_source.addItem(tr('Automatyczna – trawa Remirosa (dołączona do programu, bez ESP)'), "automatic")
        self.fl_source.addItem(tr('Z wtyczek groundcover'), "groundcover")
        self.fl_source.addItem(tr('Obie (hybryda)'), "hybrid")
        f.addRow(tr('Źródło'), self.fl_source)
        self.fl_density = QDoubleSpinBox()
        self.fl_density.setRange(0.0, 2.0)
        self.fl_density.setSingleStep(0.1)
        f.addRow(tr('Gęstość (0–2)'), self.fl_density)
        self.gc_legacy = QCheckBox(tr('Wtyczki groundcover bez roślinności proceduralnej ([Groundcover] enabled)'))
        f.addRow("", self.gc_legacy)
        self.gc_density = QDoubleSpinBox()
        self.gc_density.setRange(0.0, 1.0)
        self.gc_density.setSingleStep(0.1)
        f.addRow(tr('Gęstość wtyczek groundcover (0–1)'), self.gc_density)
        self.world_info = QLabel("")
        self.world_info.setWordWrap(True)
        self.world_info.setProperty("class", "muted")
        f.addRow("", self.world_info)
        self.fl_enabled.toggled.connect(self._world_enable)
        # zaawansowane
        f = forms["advanced"]
        self.godot = QLineEdit()
        self.godot.setPlaceholderText(tr('wykrywanie automatyczne'))
        bg = QPushButton("…")
        bg.clicked.connect(lambda: self._pick_file(self.godot))
        row = QHBoxLayout()
        row.addWidget(self.godot)
        row.addWidget(bg)
        f.addRow("Godot 4", row)
        self.godot_ver = QLabel("")
        f.addRow("", self.godot_ver)
        self.project = QLineEdit()
        self.project.setPlaceholderText(tr('wykrywanie automatyczne'))
        f.addRow(tr('Projekt gry'), self.project)
        self.python = QLineEdit()
        self.python.setPlaceholderText(tr("interpreter launchera"))
        f.addRow(tr("Python (konwerter)"), self.python)
        self.args = QLineEdit()
        self.args.setPlaceholderText(tr("np. {example}", example="--rendering-method gl_compatibility"))
        f.addRow(tr('Parametry uruchamiania'), self.args)
        self.minimize = QCheckBox(tr('Minimalizuj launcher po starcie gry'))
        f.addRow("", self.minimize)
        self.bake = QCheckBox(tr('Wypiekaj sceny z teksturami pod GPU po konwersji'))
        f.addRow("", self.bake)
        paths = self.win.core.paths
        info = QLabel(tr('Konfiguracja: {config}\nDane: {data}\nCache: {cache}\nLogi: {logs}', config=paths.config, data=paths.data, cache=paths.cache, logs=paths.logs)
                      + (tr('\n(tryb przenośny)') if paths.portable else ""))
        info.setProperty("class", "muted")
        f.addRow(tr('Katalogi'), info)
        drow = QHBoxLayout()
        b_logs = QPushButton(tr('Otwórz logi'))
        b_logs.clicked.connect(lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(paths.logs))))
        b_test = QPushButton(tr('Sprawdź Godota'))
        b_test.clicked.connect(self._check_godot)
        drow.addWidget(b_logs)
        drow.addWidget(b_test)
        f.addRow(tr('Diagnostyka'), drow)

    def _world_enable(self, on: bool):
        for w in (self.fl_source, self.fl_density):
            w.setEnabled(on)
        self.gc_legacy.setEnabled(not on)     # jak w forku: [Groundcover] działa tylko bez [flora]

    def _pick_file(self, edit):
        p, _ = QFileDialog.getOpenFileName(self, tr('Plik wykonywalny Godota'))
        if p:
            edit.setText(p)

    def _check_godot(self):
        self.save()
        g = self.win.core.godot()
        v = launch.godot_version(g) if g else None
        self.godot_ver.setText(f"{g} — {v}" if v else tr('Nie znaleziono działającego Godota 4.'))

    def refresh(self):
        core = self.win.core
        self.title.setText(tr('{v} — profil {name}', v=tr('Ustawienia'), name=core.profile.display_name))
        s = core.profile.settings
        langs = core.game_languages()
        o_gl, w_gl = self.widgets["game_language"]
        w_gl.clear()
        w_gl.addItem(tr('Automatycznie (jak launcher: {upper})', upper=core.config['language'].upper()), "auto")
        w_gl.addItem(tr('Oryginalny (bez tłumaczenia)'), "original")
        for L in langs:
            w_gl.addItem(L.upper(), L.lower())
        cur = str(s.get("game_language", "auto"))
        if w_gl.findData(cur) < 0:
            w_gl.addItem(tr('{upper} (brak w konwersji)', upper=cur.upper()), cur)
        self.lang_info.setText(
            (tr('Tłumaczenia w konwersji: ') + ", ".join(L.upper() for L in langs) if langs else
             tr('Konwersja nie zawiera tłumaczeń. Pliki localization/language/&lt;wtyczka&gt;.yaml (format forka OpenMW RLF) dodaj jako mod i uruchom aktualizację konwersji.'))
            + tr('<br>Zmiana języka nie wymaga ponownej konwersji.'))
        self.lang_info.setTextFormat(Qt.RichText)
        for key, (o, w) in self.widgets.items():
            v = s.get(key, o.default)
            if isinstance(w, QLineEdit):
                w.setText(str(v or ""))
            elif isinstance(w, QCheckBox):
                w.setChecked(bool(v))
            elif isinstance(w, (QSpinBox, QDoubleSpinBox)):
                w.setValue(v)
            else:
                if o.key == "resolution" and w.findData(v) < 0:
                    self._fill_resolutions(w, v)
                w.setCurrentIndex(max(0, w.findData(v)))
        c = core.config
        self.lang.blockSignals(True)
        self.lang.setCurrentIndex(0 if c["language"] != "en" else 1)
        self.lang.blockSignals(False)
        self.godot.setText(c["godot_path"] or "")
        self.project.setText(c["project_dir"] or "")
        self.python.setText(c["python_path"] or "")
        self.args.setText(c["launch_args"] or "")
        self.minimize.setChecked(bool(c["minimize_on_play"]))
        self.bake.setChecked(bool(c["bake"]))
        fl = {**conversion.FLORA_DEFAULTS, **(c["flora"] or {})}
        self.fl_enabled.setChecked(bool(fl["enabled"]))
        self.fl_source.setCurrentIndex(max(0, self.fl_source.findData(fl["source"])))
        self.fl_density.setValue(float(fl["density"]))
        self.gc_legacy.setChecked(bool(fl["groundcover_enabled"]))
        self.gc_density.setValue(float(fl["groundcover_density"]))
        self._world_enable(self.fl_enabled.isChecked())
        res = core.resolution(False)
        gcs = [Path(g).name for g in (res.config.groundcover if res else [])]
        self.world_info.setText(
            (tr('Wtyczki groundcover: ') + ", ".join(gcs) if gcs else tr('Brak wtyczek groundcover (rozpoznawane automatycznie przy instalacji moda).'))
            + tr("\nTryb automatyczny: trawa Remirosa liczona z reguł forka na teksturach terenu; modele i tekstury Remiros' Groundcover (autor: Remiros) są dołączone do programu – nic nie trzeba instalować.")
            + tr('\nRoślinność jest liczona przy konwersji – po zmianie ustawień uruchom „Aktualizuj” na stronie Konwersja. Zasięg i gęstość rysowania w grze: zakładka Grafika.'))

    @staticmethod
    def screen_sizes() -> list:
        """Natywne rozdzielczości ekranów w pikselach fizycznych (logiczny rozmiar × skala HiDPI)."""
        from PySide6.QtGui import QGuiApplication
        out = []
        for sc in QGuiApplication.screens():
            g, r = sc.geometry(), sc.devicePixelRatio()
            out.append((round(g.width() * r), round(g.height() * r)))
        return out

    def _fill_resolutions(self, wdg, current: str) -> None:
        from mwcore.settings import resolution_choices
        native = set(f"{w}x{h}" for w, h in self.screen_sizes())
        wdg.clear()
        for r in resolution_choices(self.screen_sizes(), current):
            wdg.addItem(r + (tr('  (ekran)') if r in native else ""), r)

    def values(self) -> dict:
        out = {}
        for key, (o, w) in self.widgets.items():
            if isinstance(w, QLineEdit):
                out[key] = w.text().strip()
            elif isinstance(w, QCheckBox):
                out[key] = w.isChecked()
            elif isinstance(w, (QSpinBox, QDoubleSpinBox)):
                out[key] = w.value()
            else:
                out[key] = w.currentData()
        return out

    def _lang_changed(self, _i):
        """Język launchera: zapis pozostałych ustawień strony i przebudowa interfejsu (MainWindow.set_language).
        Język gry zostaje bez zmian."""
        lang = self.lang.currentData()
        if lang == self.win.core.config["language"]:
            return
        self.save()
        self.win.set_language(lang)

    def save(self):
        core = self.win.core
        p = core.profile
        p.settings.update(self.values())
        core.profiles.save(p)
        c = core.config
        c["godot_path"] = self.godot.text().strip()
        c["project_dir"] = self.project.text().strip()
        c["python_path"] = self.python.text().strip()
        c["launch_args"] = self.args.text().strip()
        c["minimize_on_play"] = self.minimize.isChecked()
        c["bake"] = self.bake.isChecked()
        fl_prev = dict(c["flora"] or {})
        c["flora"] = {"enabled": self.fl_enabled.isChecked(), "source": self.fl_source.currentData(),
                      "density": round(self.fl_density.value(), 2),
                      "exclusion_distance": float(fl_prev.get("exclusion_distance", 3.0)),
                      "groundcover_enabled": self.gc_legacy.isChecked(),
                      "groundcover_density": round(self.gc_density.value(), 2)}
        c.save()
        self.win.conv_runner.python = core.python()
