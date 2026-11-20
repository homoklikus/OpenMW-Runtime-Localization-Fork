"""Kreator pierwszego uruchomienia: język → instalacja → walidacja → katalog docelowy → konwersja → koniec.
Postęp kreatora (ukończone kroki) jest zapisywany w konfiguracji – przerwanie nie gubi wyborów."""

from __future__ import annotations

from PySide6.QtWidgets import (QApplication, QComboBox, QFileDialog, QHBoxLayout, QLabel, QLineEdit, QProgressBar, QPushButton,
                               QMessageBox, QVBoxLayout, QWizard, QWizardPage)

from mwcore import conversion, install

from . import theme
from .runners import ConversionRunner
from .i18n import get_lang, set_lang, tr


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
        set_lang(core.config["language"])          # język launchera przed zbudowaniem stron (niezależny od gry)
        self.resize(600, 420)
        self.setWizardStyle(QWizard.ClassicStyle)
        self.runner = ConversionRunner(core.python(), core.converter_cwd(), self)
        self.runner.progress.connect(self._on_progress)
        self.runner.stage.connect(self._on_stage)
        self.runner.finished.connect(self._conv_done)
        self.runner.on_step_done = lambda step: conversion.write_record(self.core.plan(), self.scope.currentData()) \
            if step["name"] == "profile" or self.core.plan().profile_out is None else None
        self.p_lang = self._page_lang()
        self.addPage(self.p_lang)
        self._ids: list[int] = []
        self._build_pages()
        self.currentIdChanged.connect(self._saved_step)
        start = int(core.config["wizard_step"] or 0)
        if start:
            self.setStartId(min(start, 3))
        self.finished.connect(self._on_finished)

    def _retranslate_frame(self):
        self.setWindowTitle(tr('OpenMWGodot – pierwsza konfiguracja'))
        for b, t in ((QWizard.BackButton, tr('< Wstecz')), (QWizard.NextButton, tr('Dalej >')), (QWizard.CancelButton, tr('Anuluj')),
                     (QWizard.FinishButton, tr('Zakończ'))):
            self.setButtonText(b, t)

    def _build_pages(self):
        """Strony po wyborze języka – budowane od nowa po jego zmianie (wszystkie teksty w nowym języku)."""
        src_text = self.src.text() if hasattr(self, "src") else None
        for i in self._ids:
            pg = self.page(i)
            self.removePage(i)
            if pg is not None:
                pg.deleteLater()
        self._retranslate_frame()
        self.p_src = self._page_src()
        self.p_dst = self._page_dst()
        self.p_conv = self._page_conv()
        self.p_end = QWizardPage()
        self.p_end.setTitle(tr('Gotowe'))
        QVBoxLayout(self.p_end).addWidget(QLabel(tr('Konfiguracja zakończona. W głównym oknie kliknij „Graj”.\nJeśli konwersja nie skończyła się, wznów ją na stronie „Konwersja”.')))
        self._ids = [self.addPage(p) for p in (self.p_src, self.p_dst, self.p_conv, self.p_end)]
        if src_text is not None:
            self.src.setText(src_text)

    def _lang_changed(self, _i):
        lang = self.lang.currentData()
        if lang == get_lang():
            return
        self.core.config["language"] = lang
        self.core.config.save()
        set_lang(lang)
        self.p_lang.setTitle(tr('Język / Language'))
        self._build_pages()

    def _on_progress(self, st, d, t, _e):
        from .page_conversion import STAGE_NAMES
        self.bar.setRange(0, t)
        self.bar.setValue(d)
        self.stage.setText(f"{tr(STAGE_NAMES.get(st, st))}: {d}/{t}")

    def _on_stage(self, step, st):
        from .page_conversion import STAGE_NAMES, STEP_NAMES
        self.stage.setText(f"{tr(STEP_NAMES.get(step, step))}: {tr(STAGE_NAMES.get(st, st))}")

    def _saved_step(self, i):
        self.core.config["wizard_step"] = max(int(self.core.config["wizard_step"] or 0), i)
        self.core.config.save()

    def _page_lang(self):
        p = QWizardPage()
        p.setTitle(tr('Język / Language'))
        lay = QVBoxLayout(p)
        self.lang = QComboBox()
        self.lang.addItem("Polski", "pl")              # nazwy języków w ich własnym języku (jak w OpenMW)
        self.lang.addItem("English", "en")
        self.lang.setCurrentIndex(max(0, self.lang.findData(get_lang())))
        self.lang.currentIndexChanged.connect(self._lang_changed)
        lay.addWidget(self.lang)
        return p

    def _page_src(self):
        p = FnPage(lambda: self._validate_src())
        p.setTitle(tr('Instalacja Morrowinda'))
        p.setSubTitle(tr('Wskaż katalog gry (Steam, GOG, ręczna instalacja), „Data Files” albo openmw.cfg. Pliki gry nie są zmieniane.'))
        lay = QVBoxLayout(p)
        row = QHBoxLayout()
        self.src = QLineEdit((self.core.config["install"] or {}).get("path", ""))
        b = QPushButton(tr('Wybierz…'))
        b.clicked.connect(self._browse)
        d = QPushButton(tr("Wykryj"))
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
        d = QFileDialog.getExistingDirectory(self, tr('Katalog Morrowinda'))
        if d:
            self.src.setText(d)

    def _detect(self):
        found = install.detect()
        if found:
            self.src.setText(found[0].path)
        else:
            self.src_info.setText(tr("<span style='color:{WARN}'>Nie wykryto – wskaż ręcznie.</span>", WARN=theme.WARN))

    def _validate_src(self) -> bool:
        t = self.src.text().strip()
        if not t:
            return False
        rep = install.inspect(t)
        ok_c = [c["name"] for c in rep.components if c["esm"]]
        col = theme.OK if rep.ok else theme.ERR
        self.src_info.setText(f"<span style='color:{col}'>{tr('Znaleziono: ') + ', '.join(ok_c) if ok_c else tr('Brak danych gry')}</span>"
                              + ("<br>" + "; ".join(rep.problems) if rep.problems else ""))
        if rep.ok:
            self.core.set_install(t)
        return rep.ok

    def _page_dst(self):
        p = QWizardPage()
        p.setTitle(tr('Katalog na przekonwertowane dane'))
        p.setSubTitle(tr('Potrzeba kilku GB wolnego miejsca. Dane nie mogą być publikowane – zawierają zasoby gry.'))
        lay = QVBoxLayout(p)
        row = QHBoxLayout()
        self.dst = QLineEdit(str(self.core.converted_dir))
        b = QPushButton(tr('Wybierz…'))
        b.clicked.connect(lambda: (lambda d: d and self.dst.setText(d))(QFileDialog.getExistingDirectory(self)))
        row.addWidget(self.dst)
        row.addWidget(b)
        lay.addLayout(row)
        self.scope = QComboBox()
        self.scope.addItem(tr('Pełna konwersja (zalecana)'), "full")
        self.scope.addItem(tr('Tylko Balmora i okolice (test)'), "balmora")
        lay.addWidget(self.scope)
        return p

    def _page_conv(self):
        p = FnPage(lambda: not self.runner.is_running())
        p.setTitle(tr('Konwersja'))
        p.setSubTitle(tr('Można ją przerwać – ukończone zasoby zostaną zachowane i konwersję da się wznowić.'))
        lay = QVBoxLayout(p)
        self.btn = QPushButton(tr('Rozpocznij konwersję'))
        self.btn.clicked.connect(self._start)
        self.bar = QProgressBar()
        self.bar.setRange(0, 1)
        self.stage = QLabel("")
        lay.addWidget(self.btn)
        lay.addWidget(self.stage)
        lay.addWidget(self.bar)
        self._conv_page = p
        return p

    def _start(self):
        c = self.core.config
        text = self.dst.text().strip()
        path, err = self.core.check_converted(text)
        if err:
            self.stage.setText(f"<span style='color:#d0644f'>{err}</span>")
            if not QApplication.instance().property("headless_test"):
                QMessageBox.warning(self, tr("Katalog docelowy"), err)
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
        self.stage.setText({"done": tr('Konwersja zakończona.'), "cancelled": tr('Przerwano – można wznowić później.'),
                            "failed": tr('Błąd konwersji (kod {code}).', code=code)}.get(status, status))
        self._conv_page.completeChanged.emit()

    def _on_finished(self, _r):
        if self.runner.is_running():
            self.runner.cancel()
            self.runner.proc.waitForFinished(25000)
        if self.core.config["install"]:
            self.core.config["wizard_done"] = True
            self.core.config.save()
