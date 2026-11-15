"""Strona „Ustawienia”: Grafika, Dźwięk, Sterowanie, Język, Zaawansowane. Tylko opcje obsługiwane przez Runtime
(schemat w mwcore.settings). Ustawienia gry są per profil, ścieżki i język – globalne."""

from __future__ import annotations

import subprocess

from PySide6.QtCore import QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout, QHBoxLayout, QLabel,
                               QLineEdit, QPushButton, QSpinBox, QTabWidget, QVBoxLayout, QWidget)

from mwcore import launch
from mwcore.settings import GAME_SCHEMA

from .art import serif_font
from .i18n import LANG, tr

CHOICE_LABELS = {"windowed": "okno", "fullscreen": "pełny ekran", "exclusive": "pełny ekran (wyłączny)",
                 "off": "wyłączone", "low": "niska", "medium": "średnia", "high": "wysoka"}


class SettingsPage(QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        lay = QVBoxLayout(self)
        lay.setContentsMargins(14, 10, 14, 10)
        top = QHBoxLayout()
        self.title = QLabel(tr("settings"))
        self.title.setFont(serif_font(24))
        self.title.setProperty("class", "cardtitle")
        top.addWidget(self.title, 1)
        lay.addLayout(top)
        self.tabs = QTabWidget()
        lay.addWidget(self.tabs, 1)
        self.widgets = {}
        forms = {}
        for sec, name in (("graphics", "Grafika"), ("audio", "Dźwięk"), ("controls", "Sterowanie"),
                          ("language", "Język"), ("advanced", "Zaawansowane")):
            w = QWidget()
            f = QFormLayout(w)
            forms[sec] = f
            self.tabs.addTab(w, name)
        for o in GAME_SCHEMA:
            label = o.label_en if LANG == "en" else o.label_pl
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
            else:
                wdg = QComboBox()
                for c in o.choices:
                    wdg.addItem(CHOICE_LABELS.get(c, c), c)
            self.widgets[o.key] = (o, wdg)
            forms[o.section].addRow(label, wdg)
        forms["audio"].addRow(QLabel("Runtime nie ma jeszcze dźwięku – opcje pojawią się, gdy będzie obsługiwany."))
        self.lang = QComboBox()
        self.lang.addItem("Polski", "pl")
        self.lang.addItem("English", "en")
        forms["language"].addRow("Język launchera (po ponownym uruchomieniu)", self.lang)
        forms["language"].addRow(QLabel("Język gry: lokalizacja Runtime nie jest jeszcze przeniesiona "
                                        "(system YAML forka OpenMW – osobny etap)."))
        # zaawansowane
        f = forms["advanced"]
        self.godot = QLineEdit()
        self.godot.setPlaceholderText("wykrywanie automatyczne")
        bg = QPushButton("…")
        bg.clicked.connect(lambda: self._pick_file(self.godot))
        row = QHBoxLayout()
        row.addWidget(self.godot)
        row.addWidget(bg)
        f.addRow("Godot 4", row)
        self.godot_ver = QLabel("")
        f.addRow("", self.godot_ver)
        self.project = QLineEdit()
        self.project.setPlaceholderText("wykrywanie automatyczne")
        f.addRow("Projekt gry", self.project)
        self.python = QLineEdit()
        self.python.setPlaceholderText("interpreter launchera")
        f.addRow("Python (konwerter)", self.python)
        self.args = QLineEdit()
        self.args.setPlaceholderText("np. --rendering-method gl_compatibility")
        f.addRow("Parametry uruchamiania", self.args)
        self.minimize = QCheckBox("Minimalizuj launcher po starcie gry")
        f.addRow("", self.minimize)
        self.bake = QCheckBox("Wypiekaj sceny z teksturami pod GPU po konwersji")
        f.addRow("", self.bake)
        paths = self.win.core.paths
        info = QLabel(f"Konfiguracja: {paths.config}\nDane: {paths.data}\nCache: {paths.cache}\nLogi: {paths.logs}"
                      + ("\n(tryb przenośny)" if paths.portable else ""))
        info.setProperty("class", "muted")
        f.addRow("Katalogi", info)
        drow = QHBoxLayout()
        b_logs = QPushButton("Otwórz logi")
        b_logs.clicked.connect(lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(paths.logs))))
        b_test = QPushButton("Sprawdź Godota")
        b_test.clicked.connect(self._check_godot)
        drow.addWidget(b_logs)
        drow.addWidget(b_test)
        f.addRow("Diagnostyka", drow)

    def _pick_file(self, edit):
        p, _ = QFileDialog.getOpenFileName(self, "Plik wykonywalny Godota")
        if p:
            edit.setText(p)

    def _check_godot(self):
        self.save()
        g = self.win.core.godot()
        v = launch.godot_version(g) if g else None
        self.godot_ver.setText(f"{g} — {v}" if v else "Nie znaleziono działającego Godota 4.")

    def refresh(self):
        core = self.win.core
        self.title.setText(f"{tr('settings')} — profil {core.profile.name}")
        s = core.profile.settings
        for key, (o, w) in self.widgets.items():
            v = s.get(key, o.default)
            if isinstance(w, QCheckBox):
                w.setChecked(bool(v))
            elif isinstance(w, (QSpinBox, QDoubleSpinBox)):
                w.setValue(v)
            else:
                w.setCurrentIndex(max(0, w.findData(v)))
        c = core.config
        self.lang.setCurrentIndex(0 if c["language"] != "en" else 1)
        self.godot.setText(c["godot_path"] or "")
        self.project.setText(c["project_dir"] or "")
        self.python.setText(c["python_path"] or "")
        self.args.setText(c["launch_args"] or "")
        self.minimize.setChecked(bool(c["minimize_on_play"]))
        self.bake.setChecked(bool(c["bake"]))

    def values(self) -> dict:
        out = {}
        for key, (o, w) in self.widgets.items():
            if isinstance(w, QCheckBox):
                out[key] = w.isChecked()
            elif isinstance(w, (QSpinBox, QDoubleSpinBox)):
                out[key] = w.value()
            else:
                out[key] = w.currentData()
        return out

    def save(self):
        core = self.win.core
        p = core.profile
        p.settings.update(self.values())
        core.profiles.save(p)
        c = core.config
        c["language"] = self.lang.currentData()
        c["godot_path"] = self.godot.text().strip()
        c["project_dir"] = self.project.text().strip()
        c["python_path"] = self.python.text().strip()
        c["launch_args"] = self.args.text().strip()
        c["minimize_on_play"] = self.minimize.isChecked()
        c["bake"] = self.bake.isChecked()
        c.save()
        self.win.conv_runner.python = core.python()
