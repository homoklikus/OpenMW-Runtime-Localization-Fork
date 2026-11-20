"""Procesy potomne w Qt: konwerter (kolejne kroki, postęp MWPROGRESS, anulowanie) oraz gra / edytor."""

from __future__ import annotations

import json
import os
import time
from collections import deque
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, QTimer, Signal
from .i18n import tr


class ConversionRunner(QObject):
    """Uruchamia kroki konwersji po kolei (`python -m mwconv convert …`).

    Postęp jest rzeczywisty (zdarzenia z konwertera). Szacowany czas pojawia się dopiero, gdy etap ma
    ≥ 3% postępu i trwa ≥ 3 s. Anulowanie: SIGTERM (konwerter kończy bieżące zasoby i zapisuje stan),
    po 20 s – kill.
    """

    stage = Signal(str, str)                  # krok (base/profile), etap (vfs/world/models/textures/bake)
    progress = Signal(str, int, int, float)   # etap, wykonane, razem, ETA [s] (-1 = brak wiarygodnej)
    asset_error = Signal(str, str)
    warning = Signal(str)
    log_line = Signal(str)
    finished = Signal(str, int)               # status: done | cancelled | failed, kod wyjścia

    def __init__(self, python: str, cwd: Path, parent=None):
        super().__init__(parent)
        self.python = python
        self.cwd = Path(cwd)
        self.proc: QProcess | None = None
        self.queue: deque = deque()
        self.current: dict | None = None
        self.cancelled = False
        self.errors = 0
        self._buf = b""
        self._stage_t0 = 0.0
        self._kill_timer = QTimer(self)
        self._kill_timer.setSingleShot(True)
        self._kill_timer.timeout.connect(self._kill)
        self.on_step_done = None          # callback(step) – np. zapis rekordu konwersji

    def is_running(self) -> bool:
        return self.proc is not None and self.proc.state() != QProcess.NotRunning

    def start(self, steps: list[dict]) -> None:
        if self.is_running():
            raise RuntimeError(tr('konwersja już trwa'))
        self.queue = deque(steps)
        self.cancelled = False
        self.errors = 0
        self._next()

    def _next(self) -> None:
        if not self.queue:
            self.current = None
            self.finished.emit("done", 0)
            return
        self.current = self.queue.popleft()
        self.proc = QProcess(self)
        env = QProcessEnvironment.systemEnvironment()
        env.insert("PYTHONPATH", str(self.cwd) + os.pathsep + env.value("PYTHONPATH", ""))
        env.insert("PYTHONUNBUFFERED", "1")
        self.proc.setProcessEnvironment(env)
        self.proc.setWorkingDirectory(str(self.cwd))
        self.proc.setProcessChannelMode(QProcess.MergedChannels)
        self.proc.readyReadStandardOutput.connect(self._read)
        self.proc.finished.connect(self._done)
        self.proc.errorOccurred.connect(self._error)
        self._buf = b""
        self.stage.emit(self.current["name"], "start")
        self.proc.start(self.python, self.current["args"])  # lista argumentów – bez powłoki

    def _read(self) -> None:
        self._buf += bytes(self.proc.readAllStandardOutput())
        while b"\n" in self._buf:
            line, self._buf = self._buf.split(b"\n", 1)
            self._line(line.decode("utf-8", "replace").rstrip("\r"))

    def _line(self, line: str) -> None:
        if not line.startswith("MWPROGRESS "):
            self.log_line.emit(line)
            return
        try:
            ev = json.loads(line[11:])
        except json.JSONDecodeError:
            return
        e = ev.get("event")
        if e == "stage":
            self._stage_t0 = time.monotonic()
            self.stage.emit(self.current["name"], ev.get("stage", ""))
            if ev.get("total"):
                self.progress.emit(ev["stage"], 0, int(ev["total"]), -1.0)
        elif e == "progress":
            done, total = int(ev["done"]), int(ev["total"])
            if done <= 1 or self._stage_t0 == 0.0:
                self._stage_t0 = time.monotonic() if done <= 1 else self._stage_t0
            el = time.monotonic() - self._stage_t0
            eta = -1.0
            if total > 0 and done / total >= 0.03 and el >= 3.0 and done > 0:
                eta = el / done * (total - done)
            self.progress.emit(ev["stage"], done, total, eta)
        elif e == "asset_error":
            self.errors += 1
            self.asset_error.emit(ev.get("key", ""), ev.get("error", ""))
        elif e == "warning":
            self.warning.emit(ev.get("message", ""))

    def _error(self, err) -> None:
        if err == QProcess.FailedToStart:
            self.log_line.emit(tr('Nie udało się uruchomić konwertera: {python}', python=self.python))
            self.queue.clear()
            self.finished.emit("failed", -1)

    def _done(self, code: int, _status) -> None:
        self._read()
        self._kill_timer.stop()
        if self.cancelled or code == 130:
            self.queue.clear()
            self.finished.emit("cancelled", code)
            return
        if code != 0:
            self.queue.clear()
            self.finished.emit("failed", code)
            return
        if self.on_step_done:
            self.on_step_done(self.current)
        self._next()

    def cancel(self) -> None:
        if self.is_running():
            self.cancelled = True
            self.queue.clear()
            self.proc.terminate()  # SIGTERM → bezpieczne przerwanie w konwerterze
            self._kill_timer.start(20000)

    def _kill(self) -> None:
        if self.is_running():
            self.proc.kill()


class GameRunner(QObject):
    """Gra lub edytor jako osobny proces; wyjście procesu → plik logu; sygnał z kodem wyjścia."""

    started = Signal(int)
    exited = Signal(int, str)   # kod wyjścia, ścieżka logu

    def __init__(self, kind: str, parent=None):
        super().__init__(parent)
        self.kind = kind
        self.proc: QProcess | None = None
        self.log_path = ""

    def is_running(self) -> bool:
        return self.proc is not None and self.proc.state() != QProcess.NotRunning

    def start(self, cmd: list[str], log_dir: Path, cwd: Path | None = None) -> bool:
        log_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = str(log_dir / f"{self.kind}-{time.strftime('%Y%m%d-%H%M%S')}.log")
        self.proc = QProcess(self)
        self.proc.setProcessChannelMode(QProcess.MergedChannels)
        self.proc.setStandardOutputFile(self.log_path)
        if cwd:
            self.proc.setWorkingDirectory(str(cwd))
        self.proc.finished.connect(lambda code, _s: self.exited.emit(code, self.log_path))
        self.proc.errorOccurred.connect(self._error)
        self.proc.start(cmd[0], cmd[1:])
        if not self.proc.waitForStarted(5000):
            return False
        self.started.emit(int(self.proc.processId()))
        return True

    def _error(self, err) -> None:
        if err == QProcess.FailedToStart:
            self.exited.emit(-1, self.log_path)

    def pid(self) -> int:
        return int(self.proc.processId()) if self.proc else 0

    def terminate(self) -> None:
        if self.is_running():
            self.proc.terminate()


def log_tail(path: str, n: int = 25) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return "".join(fh.readlines()[-n:])
    except OSError:
        return ""
