"""Dziennik działań launchera (ostatnie zdarzenia na ekranie głównym): <state>/activity.jsonl.
Zawiera wyłącznie opisy operacji – bez ścieżek do plików gry ani danych osobowych."""

from __future__ import annotations

import json
import time
from pathlib import Path

MAX_LINES = 500


class Activity:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def add(self, kind: str, text: str) -> None:
        """kind: ok | info | warn | error"""
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"t": time.time(), "kind": kind, "text": text}, ensure_ascii=False) + "\n")
        self._trim()

    def recent(self, n: int = 5) -> list[dict]:
        if not self.path.exists():
            return []
        out = []
        for line in self.path.read_text(encoding="utf-8", errors="replace").splitlines()[-n * 3:]:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return list(reversed(out))[:n]

    def _trim(self) -> None:
        try:
            lines = self.path.read_text(encoding="utf-8").splitlines()
            if len(lines) > MAX_LINES:
                self.path.write_text("\n".join(lines[-MAX_LINES:]) + "\n", encoding="utf-8")
        except OSError:
            pass
