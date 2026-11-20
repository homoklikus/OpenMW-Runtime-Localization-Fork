"""Strona „Mody”: instalacja z archiwów (ZIP/7z), włączanie, kolejność, zależności, konflikty, usuwanie,
przebudowa tylko zmienionych zasobów (przyrostowa konwersja nakładki profilu)."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (QFileDialog, QHBoxLayout, QLabel, QListWidget, QListWidgetItem, QPlainTextEdit,
                               QPushButton, QSplitter, QVBoxLayout, QWidget)

from mwcore.archive import ArchiveError
from mwcore.mods import ModError

from . import theme
from .art import serif_font
from .i18n import tr


class ModsPage(QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        lay = QVBoxLayout(self)
        lay.setContentsMargins(14, 10, 14, 10)
        top = QHBoxLayout()
        self.title = QLabel(tr("Mody"))
        self.title.setFont(serif_font(24))
        self.title.setProperty("class", "cardtitle")
        top.addWidget(self.title, 1)
        lay.addLayout(top)
        sp = QSplitter(Qt.Vertical)
        self.list = QListWidget()
        self.list.itemChanged.connect(self._toggled)
        self.list.currentRowChanged.connect(lambda _r: self._details())
        sp.addWidget(self.list)
        self.info = QPlainTextEdit()
        self.info.setReadOnly(True)
        sp.addWidget(self.info)
        sp.setSizes([180, 110])
        lay.addWidget(sp, 1)
        row = QHBoxLayout()
        for text, fn, tip in ((tr("Instaluj…"), self.install_dialog, tr('Zainstaluj mod z archiwum ZIP lub 7z')),
                              ("▲", self.up, tr('Wyżej w kolejności (ładowany wcześniej)')),
                              ("▼", self.down, tr('Niżej w kolejności (wygrywa konflikty)')),
                              (tr('Usuń z profilu'), self.remove_from_profile, tr('Mod zostaje na dysku')),
                              (tr("Odinstaluj"), self.uninstall, tr('Usuń mod z dysku (z potwierdzeniem)')),
                              (tr("Zastosuj"), self.apply, tr('Przebuduj tylko zasoby zmienione przez mody'))):
            b = QPushButton(text)
            b.setToolTip(tip)
            b.clicked.connect(fn)
            row.addWidget(b)
        lay.addLayout(row)
        self.status = QLabel("")
        self.status.setWordWrap(True)
        lay.addWidget(self.status)
        self._loading = False

    # --- model ------------------------------------------------------------------------------------
    def _profile_mods(self) -> list[dict]:
        p = self.win.core.profile
        known = {m.id for m in self.win.core.mods.list()}
        mods = [m for m in p.mods if m["id"] in known or True]
        ids = {m["id"] for m in mods}
        for m in self.win.core.mods.list():  # zainstalowane, ale jeszcze nie w profilu → na końcu, wyłączone
            if m.id not in ids:
                mods.append({"id": m.id, "enabled": False})
        return mods

    def _save(self, mods: list[dict]):
        p = self.win.core.profile
        p.mods = mods
        self.win.core.profiles.save(p)

    def refresh(self):
        self._loading = True
        self.title.setText(f"{tr('Mody')} — {self.win.core.profile.display_name}")
        cur = self.list.currentRow()
        self.list.clear()
        store = self.win.core.mods
        for m in self._profile_mods():
            info = store.get(m["id"])
            label = info.name if info else tr('{v} (brak w magazynie!)', v=m['id'])
            extra = ", ".join(p["file"] for p in info.plugins) if info and info.plugins else tr('tylko zasoby')
            it = QListWidgetItem(f"{label}   —   {extra}")
            it.setData(Qt.UserRole, m["id"])
            it.setFlags(it.flags() | Qt.ItemIsUserCheckable)
            it.setCheckState(Qt.Checked if m.get("enabled") else Qt.Unchecked)
            if info is None:
                it.setForeground(Qt.red)
            self.list.addItem(it)
        self._loading = False
        if self.list.count():
            self.list.setCurrentRow(max(0, min(cur, self.list.count() - 1)))
        self._summary()

    def _current_ids(self) -> list[dict]:
        out = []
        for i in range(self.list.count()):
            it = self.list.item(i)
            out.append({"id": it.data(Qt.UserRole), "enabled": it.checkState() == Qt.Checked})
        return out

    def _toggled(self, _it):
        if not self._loading:
            self._save(self._current_ids())
            self._summary()

    def _summary(self):
        res = self.win.core.resolution(with_conflicts=True)
        if res is None:
            self.status.setText(tr('Najpierw wskaż instalację Morrowinda (Konwersja).'))
            return
        parts = [tr('Kolejność pluginów: {join}', join=', '.join(res.content))]
        if res.missing_masters:
            parts.append(tr("<span style='color:%s'>Brakujące zależności: %s</span>") % (
                theme.ERR, "; ".join(f"{m['plugin']} → {', '.join(m['missing'])}" for m in res.missing_masters)))
        if res.missing_mods:
            parts.append(tr("<span style='color:%s'>Brak modów: %s</span>") % (theme.ERR, ", ".join(res.missing_mods)))
        mod_conf = [c for c in res.conflicts if len([p for p in c["providers"] if p != tr('(gra)')]) > 1]
        parts.append(tr('Konflikty plików: {v} (między modami: {v2}) – wygrywa mod niżej na liście', v=len(res.conflicts), v2=len(mod_conf)))
        self.status.setText("<br>".join(parts))
        self.last_resolution = res

    def _details(self):
        it = self.list.currentItem()
        if it is None:
            self.info.setPlainText("")
            return
        m = self.win.core.mods.get(it.data(Qt.UserRole))
        if m is None:
            self.info.setPlainText(tr('Mod nie jest zainstalowany – usuń go z profilu.'))
            return
        lines = [f"{m.name}  [{m.id}]", tr('Archiwum: {archive_name}  (SHA-256 {v}…)', archive_name=m.archive_name, v=m.archive_sha256[:16]),
                 tr('Plików: {files}, katalog danych: {data_root}', files=m.files, data_root=m.data_root)]
        for p in m.plugins:
            lines.append(tr('Plugin {v} – wymaga: {v2}', v=p['file'], v2=', '.join(p['masters']) or '—'))
        res = getattr(self, "last_resolution", None)
        if res:
            mine = [c for c in res.conflicts if m.id in c["providers"]]
            if mine:
                lines.append(tr('Konflikty ({v}):', v=len(mine)))
                for c in mine[:15]:
                    lines.append(tr('  {v}: {join} (wygrywa {v2})', v=c['file'], join=' → '.join(c['providers']), v2=c['winner']))
        self.info.setPlainText("\n".join(lines))

    # --- akcje -----------------------------------------------------------------------------------
    def install_archive(self, path: str) -> bool:
        try:
            m = self.win.core.mods.install(path)
        except (ArchiveError, ModError, OSError) as e:
            self.win.message(tr('Instalacja moda'), tr('Nie zainstalowano: {e}', e=e), "error")
            return False
        mods = self._current_ids() + [{"id": m.id, "enabled": True}]
        self._save([x for i, x in enumerate(mods) if x["id"] not in {y["id"] for y in mods[:i]}])
        self.refresh()
        self.win.last_message = tr('zainstalowano {id}', id=m.id)
        self.win.core.activity.add("ok", 'Zainstalowano mod „{name}”', name=m.name)
        self.status.setText(self.status.text() + tr('<br>Zainstalowano „{name}”. Kliknij „Zastosuj”, aby przekonwertować tylko zmienione zasoby.', name=m.name))
        return True

    def install_dialog(self):
        f, _ = QFileDialog.getOpenFileName(self, tr('Archiwum moda'), "", tr('Archiwa (*.zip *.7z)'))
        if f:
            self.install_archive(f)

    def _move(self, d):
        r = self.list.currentRow()
        mods = self._current_ids()
        if 0 <= r < len(mods) and 0 <= r + d < len(mods):
            mods[r], mods[r + d] = mods[r + d], mods[r]
            self._save(mods)
            self.refresh()
            self.list.setCurrentRow(r + d)

    def up(self):
        self._move(-1)

    def down(self):
        self._move(1)

    def remove_from_profile(self):
        it = self.list.currentItem()
        if it:
            mid = it.data(Qt.UserRole)
            self._save([m for m in self._current_ids() if m["id"] != mid])
            # mod zainstalowany wróci na listę jako wyłączony – usunięty z kolejności profilu
            p = self.win.core.profile
            p.mods = [m for m in p.mods if m["id"] != mid]
            self.win.core.profiles.save(p)
            self.refresh()

    def uninstall(self):
        it = self.list.currentItem()
        if not it:
            return
        mid = it.data(Qt.UserRole)
        if not self.win.confirm(tr("Odinstaluj mod"), tr('Usunąć mod „{mid}” z dysku? Inne profile, które go używają, zgłoszą brak moda.', mid=mid)):
            return
        try:
            self.win.core.mods.remove(mid)
            self.win.core.activity.add("info", 'Odinstalowano mod „{mid}”', mid=mid)
        except ModError as e:
            self.win.message(tr('Mody'), str(e), "warn")
        self.refresh()

    def apply(self):
        self.win.show_page("conversion")
        self.win.pages["conversion"].start()
