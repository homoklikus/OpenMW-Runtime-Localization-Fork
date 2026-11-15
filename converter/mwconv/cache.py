"""Pamięć podręczna konwersji (SQLite, tryb WAL): identyfikacja zmian przez SHA-256, wznawianie przerwanej
konwersji (każdy zasób zapisywany jest zaraz po skonwertowaniu), zależności model → tekstury."""

from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Optional

SCHEMA = """
CREATE TABLE IF NOT EXISTS assets (
  key TEXT NOT NULL,
  kind TEXT NOT NULL,
  source TEXT,
  sha256 TEXT,
  size INTEGER,
  mtime REAL,
  converter TEXT,
  status TEXT,
  error TEXT,
  outputs TEXT,
  deps TEXT,
  report TEXT,
  duration_ms REAL,
  updated REAL,
  PRIMARY KEY (kind, key)
);
CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started REAL, finished REAL, args TEXT, stats TEXT
);
"""


class Cache:
    """Uszkodzona baza nie przerywa pracy: plik jest odkładany jako *.corrupt-<czas> i tworzony od nowa
    (zasoby zostaną zweryfikowane i w razie potrzeby przekonwertowane ponownie)."""

    def __init__(self, path: Path, readonly: bool = False):
        self.path = path
        self.recovered_from: Optional[str] = None
        if readonly:
            self.db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            self._open()
        except sqlite3.DatabaseError:
            self.db.close()
            bad = path.with_name(f"{path.name}.corrupt-{int(time.time())}")
            path.replace(bad)
            for ext in ("-wal", "-shm"):
                side = path.with_name(path.name + ext)
                if side.exists():
                    side.unlink()
            self.recovered_from = str(bad)
            self._open()

    def _open(self):
        self.db = sqlite3.connect(str(self.path))
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=NORMAL")
        self.db.executescript(SCHEMA)
        self.db.execute("SELECT count(*) FROM assets").fetchone()

    def all(self, kind: Optional[str] = None) -> list[dict]:
        q = "SELECT kind, key, status, outputs, source, size, mtime FROM assets" + (" WHERE kind=?" if kind else "")
        rows = self.db.execute(q, (kind,) if kind else ()).fetchall()
        return [{"kind": r[0], "key": r[1], "status": r[2], "outputs": json.loads(r[3]) if r[3] else [],
                 "source": r[4], "size": r[5], "mtime": r[6]} for r in rows]

    def set_status(self, kind: str, key: str, status: str, error: Optional[str] = None):
        self.db.execute("UPDATE assets SET status=?, error=? WHERE kind=? AND key=?", (status, error, kind, key))
        self.db.commit()

    def get(self, kind: str, key: str) -> Optional[dict]:
        cur = self.db.execute("SELECT key, kind, source, sha256, size, mtime, converter, status, error, outputs, deps,"
                              " report, duration_ms FROM assets WHERE kind=? AND key=?", (kind, key))
        row = cur.fetchone()
        if not row:
            return None
        cols = ["key", "kind", "source", "sha256", "size", "mtime", "converter", "status", "error", "outputs",
                "deps", "report", "duration_ms"]
        d = dict(zip(cols, row))
        for k in ("outputs", "deps", "report"):
            d[k] = json.loads(d[k]) if d[k] else None
        return d

    def put(self, kind: str, key: str, **v):
        self.db.execute(
            "INSERT OR REPLACE INTO assets (key, kind, source, sha256, size, mtime, converter, status, error, outputs,"
            " deps, report, duration_ms, updated) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (key, kind, v.get("source"), v.get("sha256"), v.get("size"), v.get("mtime"), v.get("converter"),
             v.get("status"), v.get("error"), json.dumps(v.get("outputs")), json.dumps(v.get("deps")),
             json.dumps(v.get("report"), ensure_ascii=False) if v.get("report") is not None else None,
             v.get("duration_ms"), time.time()))
        self.db.commit()

    def run_start(self, args: dict) -> int:
        cur = self.db.execute("INSERT INTO runs (started, args) VALUES (?, ?)", (time.time(), json.dumps(args)))
        self.db.commit()
        return cur.lastrowid

    def run_finish(self, run_id: int, stats: dict):
        self.db.execute("UPDATE runs SET finished=?, stats=? WHERE id=?", (time.time(), json.dumps(stats), run_id))
        self.db.commit()

    def close(self):
        self.db.close()
