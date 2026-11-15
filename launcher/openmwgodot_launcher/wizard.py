"""Kreator pierwszego uruchomienia: język → instalacja → walidacja → katalog docelowy → konwersja → koniec.
Postęp kreatora (ukończone kroki) jest zapisywany w konfiguracji – przerwanie nie gubi wyborów."""

from __future__ import annotations

from PySide6.QtWidgets import (QApplication, QComboBox, QFileDialog, QHBoxLayout, QLabel, QLineEdit, QProgressBar, QPushButton,
                               QMessageBox, QVBoxLayout, QWizard, QWizardPage)

from mwcore import conversion, install

from . import theme
from .runners import ConversionRunner


class FnPage(QWizardPage):
    """Strona kreatora z warunkiem ukończenia podanym jako funkcja (wirtualne isComplete)."""

    def __init__(self, complete=None):
        super().__init__()
        self._complete = complete

    def isComplete(self) -> bool:  # noqa: N802 – nazwa z Qt
        return bool(self._complete()) if self._complete else super().isComplete()


class FirstRunWizard(QWizard):
    def __init__(self, core):
        super().__init__()
        self.core = core
        self.setWindowTitle("OpenMWGodot – pierwsza konfiguracja")
        self.resize(600, 420)
        self.setWizardStyle(QWizard.ClassicStyle)
        for b, t in ((QWizard.BackButton, "< Wstecz"), (QWizard.NextButton, "Dalej >"), (QWizard.CancelButton, "Anuluj"),
                     (QWizard.FinishButton, "Zakończ")):
            self.setButtonText(b, t)
        self.runner = ConversionRunner(core.python(), core.converter_cwd(), self)
        self.p_lang = self._page_lang()
        self.p_src = self._page_src()
        self.p_dst = self._page_dst()
        self.p_conv = self._page_conv()
        self.p_end = QWizardPage()
        self.p_end.setTitle("Gotowe")
        QVBoxLayout(self.p_end).addWidget(QLabel("Konfiguracja zakończona. W głównym oknie kliknij „Graj”.\n"
                                                 "Jeśli konwersja nie skończyła się, wznów ją na stronie „Konwersja”."))
        for p in (self.p_lang, self.p_src, self.p_dst, self.p_conv, self.p_end):
            self.addPage(p)
        self.currentIdChanged.connect(self._saved_step)
        start = int(core.config["wizard_step"] or 0)
        if start:
            self.setStartId(min(start, 3))
        self.finished.connect(self._on_finished)

    def _saved_step(self, i):
        self.core.config["wizard_step"] = max(int(self.core.config["wizard_step"] or 0), i)
        self.core.config.save()

    def _page_lang(self):
        p = QWizardPage()
        p.setTitle("Język / Language")
        lay = QVBoxLayout(p)
        self.lang = QComboBox()
        self.lang.addItem("Polski", "pl")
        self.lang.addItem("English", "en")
        self.lang.currentIndexChanged.connect(lambda _i: (self.core.config.__setitem__("language", self.lang.currentData()),
                                                          self.core.config.save()))
        lay.addWidget(self.lang)
        return p

    def _page_src(self):
        p = FnPage(lambda: self._validate_src())
        p.setTitle("Instalacja Morrowinda")
        p.setSubTitle("Wskaż katalog gry (Steam, GOG, ręczna instalacja), „Data Files” albo openmw.cfg. "
                      "Pliki gry nie są zmieniane.")
        lay = QVBoxLayout(p)
        row = QHBoxLayout()
        self.src = QLineEdit((self.core.config["install"] or {}).get("path", ""))
        b = QPushButton("Wybierz…")
        b.clicked.connect(self._browse)
        d = QPushButton("Wykryj")
        d.clicked.connect(self._detect)
        row.addWidget(self.src)
        row.addWidget(b)
        row.addWidget(d)
        lay.addLayout(row)
        self.src_info = QLabel()
        self.src_info.setWordWrap(True)
        lay.addWidget(self.src_info)
        self.src.textChanged.connect(lambda _t: p.completeChanged.emit())
        return p

    def _browse(self):
        d = QFileDialog.getExistingDirectory(self, "Katalog Morrowinda")
        if d:
            self.src.setText(d)

    def _detect(self):
        found = install.detect()
        if found:
            self.src.setText(found[0].path)
        else:
            self.src_info.setText(f"<span style='color:{theme.WARN}'>Nie wykryto – wskaż ręcznie.</span>")

    def _validate_src(self) -> bool:
        t = self.src.text().strip()
        if not t:
            return False
        rep = install.inspect(t)
        ok_c = [c["name"] for c in rep.components if c["esm"]]
        col = theme.OK if rep.ok else theme.ERR
        self.src_info.setText(f"<span style='color:{col}'>{'Znaleziono: ' + ', '.join(ok_c) if ok_c else 'Brak danych gry'}</span>"
                              + ("<br>" + "; ".join(rep.problems) if rep.problems else ""))
        if rep.ok:
            self.core.set_install(t)
        return rep.ok

    def _page_dst(self):
        p = QWizardPage()
        p.setTitle("Katalog na przekonwertowane dane")
        p.setSubTitle("Potrzeba kilku GB wolnego miejsca. Dane nie mogą być publikowane – zawierają zasoby gry.")
        lay = QVBoxLayout(p)
        row = QHBoxLayout()
        self.dst = QLineEdit(str(self.core.converted_dir))
        b = QPushButton("Wybierz…")
        b.clicked.connect(lambda: (lambda d: d and self.dst.setText(d))(QFileDialog.getExistingDirectory(self)))
        row.addWidget(self.dst)
        row.addWidget(b)
        lay.addLayout(row)
        self.scope = QComboBox()
        self.scope.addItem("Pełna konwersja (zalecana)", "full")
        self.scope.addItem("Tylko Balmora i okolice (test)", "balmora")
        lay.addWidget(self.scope)
        return p

    def _page_conv(self):
        p = FnPage(lambda: not self.runner.is_running())
        p.setTitle("Konwersja")
        p.setSubTitle("Można ją przerwać – ukończone zasoby zostaną zachowane i konwersję da się wznowić.")
        lay = QVBoxLayout(p)
        self.btn = QPushButton("Rozpocznij konwersję")
        self.btn.clicked.connect(self._start)
        self.bar = QProgressBar()
        self.bar.setRange(0, 1)
        self.stage = QLabel("")
        lay.addWidget(self.btn)
        lay.addWidget(self.stage)
        lay.addWidget(self.bar)
        self.runner.progress.connect(lambda st, d, t, _e: (self.bar.setRange(0, t), self.bar.setValue(d),
                                                            self.stage.setText(f"{st}: {d}/{t}")))
        self.runner.stage.connect(lambda step, st: self.stage.setText(f"{step}: {st}"))
        self.runner.finished.connect(self._conv_done)
        self.runner.on_step_done = lambda step: conversion.write_record(self.core.plan(), self.scope.currentData()) \
            if step["name"] == "profile" or self.core.plan().profile_out is None else None
        self._conv_page = p
        return p

    def _start(self):
        c = self.core.config
        text = self.dst.text().strip()
        path, err = self.core.check_converted(text)
        if err:
            self.stage.setText(f"<span style='color:#d0644f'>{err}</span>")
            if not QApplication.instance().property("headless_test"):
                QMessageBox.warning(self, "Katalog docelowy", err)
            return
        c["converted_dir"] = str(path) if text else None
        if text:
            self.dst.setText(str(path))
        c["conversion_scope"] = self.scope.currentData()
        c.save()
        self.btn.setEnabled(False)
        self.runner.start(self.core.conversion_steps())
        self._conv_page.completeChanged.emit()

    def _conv_done(self, status, code):
        self.btn.setEnabled(True)
        self.stage.setText({"done": "Konwersja zakończona.", "cancelled": "Przerwano – można wznowić później.",
                            "failed": f"Błąd konwersji (kod {code})."}.get(status, status))
        self._conv_page.completeChanged.emit()

    def _on_finished(self, _r):
        if self.runner.is_running():
            self.runner.cancel()
            self.runner.proc.waitForFinished(25000)
        if self.core.config["install"]:
            self.core.config["wizard_done"] = True
            self.core.config.save()
