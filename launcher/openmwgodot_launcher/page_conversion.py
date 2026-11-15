"""Strona „Konwersja”: źródło, cel, zakres, operacje (konwertuj/aktualizuj, weryfikuj, napraw, wyczyść),
rzeczywisty postęp, błędy i anulowanie."""

from __future__ import annotations

import json
import subprocess

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (QComboBox, QFileDialog, QFrame, QGridLayout, QHBoxLayout, QLabel, QLineEdit,
                               QPlainTextEdit, QProgressBar, QPushButton, QVBoxLayout, QWidget)

from mwcore import conversion, install

from . import theme
from .art import serif_font
from .i18n import tr

STAGE_NAMES = {"vfs": "Pliki gry", "world": "Świat (ESM/ESP)", "models": "Modele", "textures": "Tekstury",
               "bake": "Wypiekanie scen", "start": "Start"}
STEP_NAMES = {"base": "Gra bazowa", "profile": "Mody profilu"}


def fmt_eta(s: float) -> str:
    if s < 0:
        return ""
    m, sec = divmod(int(s), 60)
    return f" · pozostało ok. {m} min {sec:02d} s" if m else f" · pozostało ok. {sec} s"


class ConversionPage(QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        core = win.core
        lay = QVBoxLayout(self)
        lay.setContentsMargins(14, 10, 14, 10)
        top = QHBoxLayout()
        t = QLabel(tr("conversion"))
        t.setFont(serif_font(24))
        t.setProperty("class", "cardtitle")
        top.addWidget(t, 1)
        lay.addLayout(top)

        g = QGridLayout()
        self.src = QLineEdit()
        self.src.setPlaceholderText("Katalog Morrowinda, „Data Files” albo openmw.cfg")
        b1 = QPushButton("Wybierz…")
        b1.clicked.connect(self._browse_src)
        b2 = QPushButton("Wykryj")
        b2.clicked.connect(self._detect)
        g.addWidget(QLabel("Źródło:"), 0, 0)
        g.addWidget(self.src, 0, 1)
        g.addWidget(b1, 0, 2)
        g.addWidget(b2, 0, 3)
        self.src_info = QLabel()
        self.src_info.setWordWrap(True)
        g.addWidget(self.src_info, 1, 1, 1, 3)
        self.dst = QLineEdit(str(core.converted_dir))
        b3 = QPushButton("Wybierz…")
        b3.clicked.connect(self._browse_dst)
        g.addWidget(QLabel("Cel:"), 2, 0)
        g.addWidget(self.dst, 2, 1, 1, 2)
        g.addWidget(b3, 2, 3)
        self.scope = QComboBox()
        self.scope.addItem("Pełna konwersja (zalecana)", "full")
        self.scope.addItem("Tylko Balmora i okolice (test)", "balmora")
        self.scope.setToolTip("Szybki start (gra przed końcem konwersji) będzie dostępny, gdy Runtime nauczy się "
                              "bezpiecznie obsługiwać brakujące zasoby.")
        g.addWidget(QLabel("Zakres:"), 3, 0)
        g.addWidget(self.scope, 3, 1, 1, 3)
        lay.addLayout(g)

        ops = QHBoxLayout()
        self.btn_run = QPushButton("Konwertuj / aktualizuj")
        self.btn_verify = QPushButton("Weryfikuj")
        self.btn_repair = QPushButton("Napraw")
        self.btn_clean = QPushButton("Wyczyść cache")
        self.btn_cancel = QPushButton("Anuluj")
        self.btn_run.clicked.connect(self.start)
        self.btn_verify.clicked.connect(lambda: self.verify(repair=False))
        self.btn_repair.clicked.connect(lambda: self.verify(repair=True))
        self.btn_clean.clicked.connect(self.clean)
        self.btn_cancel.clicked.connect(self.cancel)
        for b in (self.btn_run, self.btn_verify, self.btn_repair, self.btn_clean, self.btn_cancel):
            ops.addWidget(b)
        lay.addLayout(ops)

        self.stage_lbl = QLabel("")
        self.bar = QProgressBar()
        self.bar.setRange(0, 1)
        self.bar.setValue(0)
        self.bar.setTextVisible(False)
        self.err_lbl = QLabel("")
        lay.addWidget(self.stage_lbl)
        lay.addWidget(self.bar)
        lay.addWidget(self.err_lbl)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(2000)
        lay.addWidget(self.log, 1)

        r = win.conv_runner
        r.stage.connect(self._on_stage)
        r.progress.connect(self._on_progress)
        r.asset_error.connect(self._on_asset_error)
        r.warning.connect(lambda m: self._append(f"⚠ {m}"))
        r.log_line.connect(self._append)
        r.finished.connect(self._on_finished)
        r.on_step_done = self._step_done
        self._step = ""
        self._warns = 0
        self._update_buttons()

    # --- źródło / cel -------------------------------------------------------------------------------
    def refresh(self):
        inst = self.win.core.config["install"]
        if inst and not self.src.text():
            self.src.setText(inst["path"])
        self.scope.setCurrentIndex(0 if self.win.core.config["conversion_scope"] == "full" else 1)
        self._show_report(self.win.core.install_report() if inst else None)
        self._update_buttons()

    def _show_report(self, rep):
        if rep is None:
            self.src_info.setText("<i>Wskaż instalację gry (Steam, GOG lub ręczną).</i>")
            return
        parts = []
        for c in rep.components:
            col = theme.OK if c["esm"] else (theme.ERR if c["required"] else theme.MUTED)
            bsa = " + BSA" if c["bsa"] else (" (bez BSA)" if c["esm"] else "")
            parts.append(f"<span style='color:{col}'>{'✓' if c['esm'] else '✗'} {c['name']}{bsa}</span>")
        txt = " &nbsp; ".join(parts)
        if rep.problems:
            txt += "<br><span style='color:%s'>%s</span>" % (theme.WARN, "; ".join(rep.problems))
        self.src_info.setText(txt)

    def _browse_src(self):
        d = QFileDialog.getExistingDirectory(self, "Katalog Morrowinda")
        if d:
            self.src.setText(d)
            self._apply_src()

    def _browse_dst(self):
        d = QFileDialog.getExistingDirectory(self, "Katalog na przekonwertowane dane")
        if d:
            self.dst.setText(d)

    def _detect(self):
        found = install.detect()
        if not found:
            self.src_info.setText(f"<span style='color:{theme.WARN}'>Nie wykryto instalacji – wskaż ją ręcznie.</span>")
            return
        self.src.setText(found[0].path)
        self._apply_src()

    def _apply_src(self) -> bool:
        rep = self.win.core.set_install(self.src.text().strip())
        self._show_report(rep)
        self.win.pages["home"].refresh()
        return rep.ok

    def _apply_target(self):
        c = self.win.core.config
        c["converted_dir"] = self.dst.text().strip() or None
        c["conversion_scope"] = self.scope.currentData()
        c.save()

    # --- operacje -------------------------------------------------------------------------------------
    def start(self):
        if self.win.conv_runner.is_running():
            return
        if not self._apply_src():
            self.win.message("Konwersja", "Źródło nie jest poprawną instalacją Morrowinda.", "warn")
            return
        if self.win.game.is_running():
            self.win.message("Konwersja", "Zamknij grę przed konwersją.", "warn")
            return
        self._apply_target()
        steps = self.win.core.conversion_steps(self.scope.currentData())
        self.log.clear()
        self._warns = 0
        self.err_lbl.setText("")
        self._append(f"Kroki: {', '.join(STEP_NAMES.get(s['name'], s['name']) for s in steps)}")
        self.win.conv_runner.start(steps)
        self._update_buttons()
        self.win.update_statusbar()

    def _step_done(self, step):
        if step["name"] == "profile" or (step["name"] == "base" and self.win.core.plan().profile_out is None):
            conversion.write_record(self.win.core.plan(), self.scope.currentData())

    def cancel(self):
        self.win.conv_runner.cancel()
        self.stage_lbl.setText("Przerywanie – kończenie bieżących zasobów…")

    def _converter(self, *args) -> dict:
        core = self.win.core
        r = subprocess.run([core.python(), "-m", "mwconv", *args], cwd=core.converter_cwd(), capture_output=True,
                           text=True, timeout=600)
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"error": r.stderr[-500:] or r.stdout[-500:]}

    def _outs(self) -> list:
        plan = self.win.core.plan()
        if plan is None:
            return []
        return [plan.base_out] + ([plan.profile_out] if plan.profile_out else [])

    def verify(self, repair: bool):
        if self.win.conv_runner.is_running():
            return
        self._apply_target()
        total_bad, problems = 0, []
        for out in self._outs():
            if not (out / ".mwconv").exists():
                problems.append(f"{out}: brak konwersji")
                continue
            r = self._converter("verify", "--out", str(out), "--deep", *([] if repair else ["--no-mark"]))
            total_bad += len(r.get("bad", []))
            problems += r.get("world_problems", [])
            for b in r.get("bad", [])[:20]:
                self._append(f"✗ {b['file']}: {b['problem']}")
        if total_bad == 0 and not problems:
            self.stage_lbl.setText(f"<span style='color:{theme.OK}'>Weryfikacja: dane kompletne</span>")
            self.win.last_message = "weryfikacja ok"
            return
        self.stage_lbl.setText(f"<span style='color:{theme.WARN}'>Weryfikacja: {total_bad} uszkodzonych plików, "
                               f"{len(problems)} problemów świata</span>")
        for p in problems:
            self._append(f"⚠ {p}")
        self.win.last_message = f"weryfikacja: {total_bad} uszkodzonych"
        if repair:
            self._append("Naprawa: ponowna konwersja tylko uszkodzonych/brakujących zasobów…")
            self.start()

    def clean(self):
        outs = self._outs()
        found = []
        for out in outs:
            if (out / ".mwconv").exists():
                found += [(out, x) for x in self._converter("clean", "--out", str(out)).get("orphans", [])]
        if not found:
            self.win.message("Czyszczenie", "Brak nieużywanych plików.")
            return
        if not self.win.confirm("Wyczyść cache", f"Usunąć {len(found)} nieużywanych plików z katalogu konwersji?\n"
                                                  "Oryginalna instalacja gry nie jest zmieniana."):
            return
        for out in {o for o, _ in found}:
            self._converter("clean", "--out", str(out), "--yes")
        self._append(f"Usunięto {len(found)} nieużywanych plików.")
        self.win.last_message = f"usunięto {len(found)}"

    # --- postęp ---------------------------------------------------------------------------------------
    def _on_stage(self, step, stage):
        self._step = step
        self.stage_lbl.setText(f"{STEP_NAMES.get(step, step)}: {STAGE_NAMES.get(stage, stage)}")
        if stage in ("vfs", "world", "start"):
            self.bar.setRange(0, 0)  # nieokreślony – etap bez liczby plików

    def _on_progress(self, stage, done, total, eta):
        if total <= 0:
            return
        self.bar.setRange(0, total)
        self.bar.setValue(done)
        self.bar.setTextVisible(True)
        self.bar.setFormat("%v / %m")
        self.stage_lbl.setText(f"{STEP_NAMES.get(self._step, self._step)}: {STAGE_NAMES.get(stage, stage)} — "
                               f"{done} / {total} plików{fmt_eta(eta)}")

    def _on_asset_error(self, key, err):
        self._append(f"✗ {key}: {err}")
        self.err_lbl.setText(f"<span style='color:{theme.ERR}'>Błędy zasobów: {self.win.conv_runner.errors}</span>"
                             " (szczegóły w logu i raporcie konwersji)")

    def _on_finished(self, status, code):
        self.bar.setRange(0, 1)
        self.bar.setValue(1 if status == "done" else 0)
        msg = {"done": f"<span style='color:{theme.OK}'>Konwersja zakończona</span>",
               "cancelled": f"<span style='color:{theme.WARN}'>Przerwano – ukończone zasoby zachowane; "
                            "„Konwertuj” wznowi pracę</span>",
               "failed": f"<span style='color:{theme.ERR}'>Konwersja nie powiodła się (kod {code}) – zobacz log</span>"}
        self.stage_lbl.setText(msg.get(status, status))
        self._update_buttons()
        self.win.pages["home"].refresh()

    def _append(self, line: str):
        if line.strip():
            self.log.appendPlainText(line)

    def _update_buttons(self):
        running = self.win.conv_runner.is_running()
        for b in (self.btn_run, self.btn_verify, self.btn_repair, self.btn_clean):
            b.setEnabled(not running)
        self.btn_cancel.setEnabled(running)
