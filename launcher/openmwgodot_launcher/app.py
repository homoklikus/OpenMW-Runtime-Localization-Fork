"""Główne okno launchera wg grafiki referencyjnej: baner, pasek boczny z nawigacją, ekran główny z kartami
(Stan instalacji, Aktywny profil, Szybkie akcje, Ostatnie działania), ozdobny przycisk „Graj”, pasek stanu.
Godło i ilustracje są własne (rysowane kodem) – bez znaków towarowych i grafik Bethesdy."""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import QRectF, QSize, Qt, QTimer, QUrl
from PySide6.QtGui import QColor, QDesktopServices, QLinearGradient, QPainter, QPainterPath, QPen, QPixmap
from PySide6.QtWidgets import (QApplication, QComboBox, QDialog, QDialogButtonBox, QFrame, QGridLayout, QHBoxLayout,
                               QInputDialog, QLabel, QListWidget, QMessageBox, QPlainTextEdit, QPushButton,
                               QSizePolicy, QStackedWidget, QToolButton, QVBoxLayout, QWidget)

from mwcore import conversion

from . import APP_NAME, __version__, art, theme
from .core import LauncherCore
from .i18n import set_lang, tr
from .runners import ConversionRunner, GameRunner, log_tail


def human_size(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return (f"{int(n)} B" if unit == "B" else f"{n:.1f} {unit}").replace(".", ",")
        n /= 1024
    return str(n)


def human_time(t: float) -> str:
    if not t:
        return "—"
    lt, now = time.localtime(t), time.localtime()
    if lt.tm_yday == now.tm_yday and lt.tm_year == now.tm_year:
        return time.strftime("dzisiaj, %H:%M", lt)
    return time.strftime("%d.%m.%Y, %H:%M", lt)


def files_word(n: int) -> str:
    if n == 1:
        return "plik"
    if n % 10 in (2, 3, 4) and n % 100 not in (12, 13, 14):
        return "pliki"
    return "plików"


def card(title: str, icon: str | None = None) -> tuple[QFrame, QVBoxLayout]:
    f = QFrame()
    f.setProperty("class", "card")
    lay = QVBoxLayout(f)
    lay.setContentsMargins(14, 8, 14, 10)
    lay.setSpacing(6)
    head = QHBoxLayout()
    if icon:
        ic = QLabel()
        ic.setPixmap(art.icon_pixmap(icon, 22, theme.ACCENT))
        head.addWidget(ic)
    t = QLabel(title)
    t.setProperty("class", "cardtitle")
    t.setFont(art.serif_font(19))
    head.addWidget(t, 1)
    lay.addLayout(head)
    sep = QFrame()
    sep.setProperty("class", "sep")
    lay.addWidget(sep)
    return f, lay


def page_title(text: str) -> QLabel:
    t = QLabel(text)
    t.setFont(art.serif_font(24))
    t.setProperty("class", "cardtitle")
    return t


class PlayButton(QPushButton):
    """Ozdobny przycisk „Graj”: mosiężna rama ze ściętymi narożnikami, gradient, ikona i napis szeryfowy."""

    def __init__(self, parent=None):
        super().__init__(tr("play"), parent)
        self.setObjectName("play")
        self.setCursor(Qt.PointingHandCursor)
        self.setMinimumSize(QSize(260, 92))
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self._hover = False

    def enterEvent(self, e):
        self._hover = True
        self.update()

    def leaveEvent(self, e):
        self._hover = False
        self.update()

    @staticmethod
    def _octagon(rr: QRectF, c: float) -> QPainterPath:
        path = QPainterPath()
        path.moveTo(rr.left() + c, rr.top())
        for x, y in ((rr.right() - c, rr.top()), (rr.right(), rr.top() + c), (rr.right(), rr.bottom() - c),
                     (rr.right() - c, rr.bottom()), (rr.left() + c, rr.bottom()), (rr.left(), rr.bottom() - c),
                     (rr.left(), rr.top() + c)):
            path.lineTo(x, y)
        path.closeSubpath()
        return path

    def paintEvent(self, _e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(3, 3, -3, -3)
        en = self.isEnabled()
        outer = self._octagon(r, 14.0)
        g = QLinearGradient(0, r.top(), 0, r.bottom())
        g.setColorAt(0, QColor("#f3dda0" if en else "#7a6a52"))
        g.setColorAt(0.5, QColor("#b48a3e" if en else "#5a4c38"))
        g.setColorAt(1, QColor("#6b4f22" if en else "#3c3226"))
        p.fillPath(outer, g)
        ir = r.adjusted(6, 6, -6, -6)
        inner = self._octagon(ir, 10.0)
        gi = QLinearGradient(0, ir.top(), 0, ir.bottom())
        base = ("#9c7a3c", "#5e4520", "#3e2c12") if en else ("#4f4434", "#3a3126", "#2c251d")
        if self._hover and en:
            base = ("#b38c47", "#6e5226", "#463216")
        for k, col in zip((0, 0.55, 1), base):
            gi.setColorAt(k, QColor(col))
        p.fillPath(inner, gi)
        p.setPen(QPen(QColor("#f7e6b8" if en else "#8a7a60"), 1.2))
        p.drawPath(inner)
        p.setPen(QPen(QColor("#3a2a12"), 1.5))
        p.drawPath(outer)
        s = int(min(ir.height() * 0.55, 46))
        txt = self.text()
        p.setFont(art.serif_font(int(ir.height() * (0.48 if len(txt) < 8 else 0.30)), bold=True))
        tw = p.fontMetrics().horizontalAdvance(txt)
        total = s + 14 + tw
        x0 = ir.center().x() - total / 2
        p.drawPixmap(int(x0), int(ir.center().y() - s / 2), art.icon_pixmap("play", s))
        p.setPen(QColor("#2a1d0b"))
        p.drawText(QRectF(x0 + s + 15, ir.top() + 2, tw + 4, ir.height()), Qt.AlignVCenter, txt)
        p.setPen(QColor("#fbe7b3" if en else "#9a8a70"))
        p.drawText(QRectF(x0 + s + 14, ir.top(), tw + 4, ir.height()), Qt.AlignVCenter, txt)
        p.end()


class Banner(QWidget):
    HEIGHT = 140

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(self.HEIGHT)
        self._pm: QPixmap | None = None

    def paintEvent(self, _e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self._pm is None or self._pm.width() != self.width():
            self._pm = art.user_image("banner", self.width(), self.height()) or art.banner(self.width(), self.height())
        p.drawPixmap(0, 0, self._pm)
        p.drawPixmap(30, 16, theme.emblem(104))
        p.setFont(art.serif_font(52))
        p.setPen(QColor(0, 0, 0, 170))
        p.drawText(QRectF(154, 16, 700, 72), Qt.AlignLeft | Qt.AlignVCenter, APP_NAME)
        g = QLinearGradient(0, 24, 0, 84)
        g.setColorAt(0, QColor("#f6e2a8"))
        g.setColorAt(1, QColor("#b98d45"))
        p.setPen(QPen(g, 1))
        p.drawText(QRectF(152, 14, 700, 72), Qt.AlignLeft | Qt.AlignVCenter, APP_NAME)
        p.setFont(art.serif_font(20))
        p.setPen(QColor("#e8dcc3"))
        p.drawText(QRectF(250, 84, 600, 30), Qt.AlignLeft | Qt.AlignVCenter, tr("subtitle"))
        p.end()


class ProfilesPage(QWidget):
    def __init__(self, core: LauncherCore, win):
        super().__init__()
        self.core = core
        self.win = win
        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 12, 18, 12)
        lay.addWidget(page_title("Profile"))
        info = QLabel("Profil to zestaw aktywnych modów i ich kolejności, ustawienia gry i zapisy. Przekonwertowana gra "
                      "jest wspólna – profil z modami przechowuje tylko różnice. Usunięcie profilu nie usuwa zapisów gry.")
        info.setWordWrap(True)
        info.setProperty("class", "muted")
        lay.addWidget(info)
        self.list = QListWidget()
        lay.addWidget(self.list, 1)
        row = QHBoxLayout()
        for text, fn in (("Nowy", self.new), ("Kopiuj", self.copy), ("Zmień nazwę", self.rename),
                         ("Usuń", self.delete), ("Ustaw aktywny", self.activate)):
            b = QPushButton(text)
            b.clicked.connect(fn)
            row.addWidget(b)
        lay.addLayout(row)
        self.refresh()

    def _confirm(self, title, text):
        if self.win:
            return self.win.confirm(title, text)
        return QMessageBox.question(self, title, text) == QMessageBox.Yes

    def refresh(self):
        self.list.clear()
        for p in self.core.profiles.list():
            mark = "   ✓ aktywny" if p.id == self.core.profile.id else ""
            self.list.addItem(f"{p.name}   [{p.id}]   mody: {len(p.enabled_mods())}{mark}")
            self.list.item(self.list.count() - 1).setData(Qt.UserRole, p.id)

    def _sel(self):
        it = self.list.currentItem()
        return it.data(Qt.UserRole) if it else None

    def new(self):
        name, ok = QInputDialog.getText(self, "Nowy profil", "Nazwa:")
        if ok and name.strip():
            p = self.core.profiles.create(name)
            self.core.activity.add("info", f"Utworzono profil „{p.name}”")
            self.refresh()

    def copy(self):
        pid = self._sel()
        if pid:
            src = self.core.profiles.get(pid)
            name, ok = QInputDialog.getText(self, "Kopiuj profil", "Nazwa kopii:", text=f"{src.name} (kopia)")
            if ok:
                p = self.core.profiles.create(name, copy_from=pid)
                self.core.activity.add("info", f"Skopiowano profil „{src.name}” jako „{p.name}”")
                self.refresh()

    def rename(self):
        pid = self._sel()
        if pid:
            name, ok = QInputDialog.getText(self, "Zmień nazwę", "Nowa nazwa:", text=self.core.profiles.get(pid).name)
            if ok:
                self.core.profiles.rename(pid, name)
                self.refresh()

    def delete(self):
        pid = self._sel()
        if not pid:
            return
        name = self.core.profiles.get(pid).name
        if not self._confirm("Usuń profil", f"Usunąć profil „{name}”?\n\nZostaną usunięte jego ustawienia i nakładka "
                                            "konwersji. Zapisy gry NIE zostaną usunięte."):
            return
        try:
            self.core.profiles.delete(pid)
        except ValueError as e:
            QMessageBox.warning(self, "Profil", str(e))
            return
        self.core.activity.add("info", f"Usunięto profil „{name}” (zapisy gry zachowane)")
        if self.core.config["active_profile"] == pid:
            self.core.set_active_profile(self.core.profiles.list()[0].id)
        self.refresh()

    def activate(self):
        pid = self._sel()
        if pid:
            self.core.set_active_profile(pid)
            self.refresh()


class ProfilesDialog(QDialog):
    def __init__(self, core: LauncherCore, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Profile")
        self.resize(480, 340)
        lay = QVBoxLayout(self)
        lay.addWidget(ProfilesPage(core, None))
        bb = QDialogButtonBox(QDialogButtonBox.Close)
        bb.rejected.connect(self.accept)
        lay.addWidget(bb)


class HomePage(QWidget):
    def __init__(self, win: "MainWindow"):
        super().__init__()
        self.win = win
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 10, 14, 10)
        root.setSpacing(10)
        top = QHBoxLayout()
        top.setSpacing(12)
        c1, l1 = card("Stan instalacji")
        inner = QHBoxLayout()
        self.checks_host = QWidget()
        self.checks = QGridLayout(self.checks_host)
        self.checks.setContentsMargins(0, 0, 0, 0)
        self.checks.setVerticalSpacing(7)
        inner.addWidget(self.checks_host, 1)
        self.preview = QLabel()
        self.preview.setFixedSize(270, 150)
        self.preview.setStyleSheet("border: 1px solid #5a4a38; border-radius: 4px;")
        self.preview.setToolTip("Widok z ostatniej sesji gry (zapisywany lokalnie) albo ilustracja")
        inner.addWidget(self.preview)
        l1.addLayout(inner)
        top.addWidget(c1, 3)
        c2, l2 = card("Aktywny profil", "user")
        prow = QHBoxLayout()
        self.profile_box = QComboBox()
        self.profile_box.setMinimumHeight(30)
        self.profile_box.currentIndexChanged.connect(self._profile_changed)
        gear = QToolButton()
        gear.setIcon(art.icon("gear", 20))
        gear.setIconSize(QSize(20, 20))
        gear.setToolTip("Zarządzaj profilami")
        gear.setMinimumSize(32, 30)
        gear.clicked.connect(lambda: win.show_page("profiles"))
        prow.addWidget(self.profile_box, 1)
        prow.addWidget(gear)
        l2.addLayout(prow)
        self.pinfo = {}
        for key, ic in (("mods", "puzzle"), ("size", "database"), ("last", "calendar"), ("ready", "ok")):
            row = QHBoxLayout()
            il = QLabel()
            il.setPixmap(art.icon_pixmap(ic, 18, "#cfc3a8"))
            lab = QLabel()
            row.addWidget(il)
            row.addWidget(lab, 1)
            l2.addLayout(row)
            self.pinfo[key] = (il, lab)
        l2.addStretch(1)
        top.addWidget(c2, 2)
        root.addLayout(top)
        mid = QHBoxLayout()
        mid.setSpacing(12)
        c3, l3 = card("Szybkie akcje")
        tiles = QHBoxLayout()
        tiles.setSpacing(8)
        self.tiles = {}
        for key, ic, title, sub, fn in (
                ("conversion", "refresh", "Konwersja", "Aktualizuj\nzasoby gry", lambda: win.show_page("conversion")),
                ("mods", "cube", "Mody", "Instaluj i zarządzaj\nmodami", lambda: win.show_page("mods")),
                ("settings", "sliders", "Ustawienia", "Grafika,\nsterowanie", lambda: win.show_page("settings")),
                ("cs", "tools", "Construction\nSet", "Edytor świata\ni modów", lambda: win.launch_editor())):
            b = QPushButton()
            b.setProperty("class", "tile")
            b.setMinimumHeight(96)
            b.setCursor(Qt.PointingHandCursor)
            bl = QVBoxLayout(b)
            bl.setContentsMargins(4, 6, 4, 6)
            i = QLabel()
            i.setPixmap(art.icon_pixmap(ic, 30, "#e8d6ac"))
            i.setAlignment(Qt.AlignCenter)
            t = QLabel(title)
            t.setAlignment(Qt.AlignCenter)
            t.setStyleSheet("font-weight: 600; font-size: 10pt; background: transparent;")
            t.setWordWrap(True)
            s = QLabel(sub)
            s.setAlignment(Qt.AlignCenter)
            s.setWordWrap(True)
            s.setStyleSheet(f"color: {theme.MUTED}; font-size: 8.5pt; background: transparent;")
            for w_ in (i, t, s):
                w_.setAttribute(Qt.WA_TransparentForMouseEvents)
                bl.addWidget(w_)
            b.clicked.connect(fn)
            tiles.addWidget(b)
            self.tiles[key] = b
        l3.addLayout(tiles)
        mid.addWidget(c3, 5)
        pv = QVBoxLayout()
        pv.addStretch(1)
        self.btn_play = PlayButton()
        self.btn_play.clicked.connect(lambda: win.play())
        pv.addWidget(self.btn_play)
        self.lbl_hint = QLabel()
        self.lbl_hint.setWordWrap(True)
        self.lbl_hint.setAlignment(Qt.AlignCenter)
        self.lbl_hint.setStyleSheet(f"color: {theme.WARN};")
        pv.addWidget(self.lbl_hint)
        pv.addStretch(1)
        mid.addLayout(pv, 3)
        root.addLayout(mid)
        c4, l4 = card("Ostatnie działania")
        self.activity_host = QWidget()
        self.activity_box = QVBoxLayout(self.activity_host)
        self.activity_box.setContentsMargins(0, 0, 0, 0)
        self.activity_box.setSpacing(3)
        l4.addWidget(self.activity_host)
        root.addWidget(c4)
        self._updating = False

    def _profile_changed(self, idx):
        if self._updating or idx < 0:
            return
        self.win.core.set_active_profile(self.profile_box.itemData(idx))
        self.win.refresh_all()

    def _check_row(self, r: int, ok: str, text: str, sub: str = ""):
        il = QLabel()
        il.setPixmap(art.icon_pixmap(ok, 20))
        lab = QLabel(text + (f"<br><span style='color:{theme.MUTED}; font-size:9pt'>{sub}</span>" if sub else ""))
        self.checks.addWidget(il, r, 0, Qt.AlignTop)
        self.checks.addWidget(lab, r, 1)

    @staticmethod
    def _clear(layout):
        while layout.count():
            it = layout.takeAt(0)
            w = it.widget()
            if w:
                w.setParent(None)
                w.deleteLater()
            elif it.layout():
                HomePage._clear(it.layout())

    def refresh(self):
        core = self.win.core
        self._clear(self.checks)
        rep = core.install_report()
        names = {"Morrowind": "Morrowind (gra podstawowa)", "Tribunal": "Tribunal", "Bloodmoon": "Bloodmoon"}
        r = 0
        if rep is None:
            self._check_row(0, "err", "Nie wskazano instalacji Morrowinda", "Konwersja → Wybierz… / Wykryj")
            r = 1
        else:
            for c in rep.components:
                state = "ok" if c["esm"] else ("err" if c["required"] else "dot")
                sub = "" if c["esm"] else ("brak – wymagany" if c["required"] else "nie zainstalowano")
                self._check_row(r, state, names.get(c["name"], c["name"]), sub)
                r += 1
        running = self.win.conv_runner.is_running()
        st = core.status()
        plan = core.plan()
        rec = conversion.read_record(plan) if plan else {}
        if running:
            self._check_row(r, "dot", "Konwersja w toku", "postęp na stronie Konwersja")
        elif st.state == conversion.READY:
            n = int(rec.get("files", 0))
            self._check_row(r, "ok", "Zasoby przekonwertowane",
                            f"{n} {files_word(n)} • {human_size(int(rec.get('bytes', 0)))}")
        else:
            self._check_row(r, "warn" if st.state in ("outdated", "incomplete") else "err",
                            "Zasoby: " + tr("st_" + st.state), "; ".join(st.details)[:70])
        self.checks.setRowStretch(r + 1, 1)
        self.preview.setPixmap(self._preview_pixmap())
        self._updating = True
        self.profile_box.clear()
        for p in core.profiles.list():
            self.profile_box.addItem(p.name, p.id)
            if p.id == core.profile.id:
                self.profile_box.setCurrentIndex(self.profile_box.count() - 1)
        self._updating = False
        self.pinfo["mods"][1].setText(f"Aktywne mody: {len(core.profile.enabled_mods())}")
        self.pinfo["size"][1].setText("Rozmiar danych: " + (human_size(int(rec["bytes"])) if rec.get("bytes") else "—"))
        self.pinfo["last"][1].setText(f"Ostatnia konwersja: {human_time(rec.get('time', 0))}")
        chk = core.check_play(running)
        il, lab = self.pinfo["ready"]
        il.setPixmap(art.icon_pixmap("ok" if chk.ok else "warn", 18))
        lab.setText(f"<span style='color:{theme.OK if chk.ok else theme.WARN}'>"
                    f"{'Profil gotowy do gry' if chk.ok else 'Profil wymaga uwagi'}</span>")
        self.btn_play.setText(tr("game_running") if self.win.game.is_running() else tr("play"))
        self.btn_play.update()
        self.lbl_hint.setText(chk.problems[0][1] if chk.problems else "")
        self._clear(self.activity_box)
        items = core.activity.recent(3) or [{"kind": "info", "t": 0,
                                             "text": "Brak działań – zacznij od wskazania instalacji Morrowinda."}]
        for a in items:
            roww = QWidget()
            row = QHBoxLayout(roww)
            row.setContentsMargins(0, 0, 0, 0)
            il = QLabel()
            il.setPixmap(art.icon_pixmap({"ok": "ok", "warn": "warn", "error": "err"}.get(a["kind"], "dot"), 18))
            row.addWidget(il)
            row.addWidget(QLabel(a["text"]), 1)
            tl = QLabel(human_time(a["t"]) if a.get("t") else "")
            tl.setStyleSheet(f"color: {theme.MUTED};")
            row.addWidget(tl)
            self.activity_box.addWidget(roww)

    def _preview_pixmap(self) -> QPixmap:
        """Widok z ostatniej sesji gry (Runtime zapisuje go lokalnie w katalogu zapisów) albo własna ilustracja."""
        shot = self.win.core.paths.saves(self.win.core.profile.id) / "last_view.png"
        w, h = self.preview.width(), self.preview.height()
        if shot.exists():
            pm = QPixmap(str(shot))
            if not pm.isNull():
                return pm.scaled(w, h, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation).copy(0, 0, w, h)
        return art.user_image("preview", w, h) or art.preview(w, h)


class DiagnosticsPage(QWidget):
    def __init__(self, win):
        super().__init__()
        self.win = win
        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 12, 18, 12)
        lay.addWidget(page_title("Dziennik i diagnostyka"))
        row = QHBoxLayout()
        for text, fn in (("Sprawdź Godota", self.check_godot), ("Ostatni log gry", lambda: self.show_log("game")),
                         ("Ostatni log edytora", lambda: self.show_log("editor")),
                         ("Otwórz katalog logów", lambda: win._open(win.core.paths.logs))):
            b = QPushButton(text)
            b.clicked.connect(fn)
            row.addWidget(b)
        lay.addLayout(row)
        self.text = QPlainTextEdit()
        self.text.setReadOnly(True)
        lay.addWidget(self.text, 1)

    def refresh(self):
        core = self.win.core
        gv = core.config["godot_version"]
        lines = [f"Launcher {__version__}, Python {sys.version.split()[0]}",
                 f"Konfiguracja: {core.paths.config}", f"Dane: {core.paths.data}", f"Logi: {core.paths.logs}",
                 f"Godot: {core.godot() or 'nie znaleziono'}" + (f" ({gv})" if gv else " (wersja nie sprawdzona)"),
                 f"Projekt gry: {core.project_dir() or 'nie znaleziono'}", "", "Ostatnie działania:"]
        for a in core.activity.recent(40):
            lines.append(f"  {human_time(a['t'])}  [{a['kind']}]  {a['text']}")
        self.text.setPlainText("\n".join(lines))

    def check_godot(self):
        from mwcore import launch
        g = self.win.core.godot()
        v = launch.godot_version(g) if g else None
        if v:
            self.win.core.config["godot_version"] = v
            self.win.core.config.save()
        self.text.appendPlainText(f"\nSprawdzenie Godota: {g} → {v or 'nie działa'}")
        self.win.update_statusbar()

    def show_log(self, kind):
        logs = sorted(self.win.core.paths.logs.glob(f"{kind}-*.log"))
        self.text.setPlainText(log_tail(str(logs[-1]), 400) if logs else "Brak logów.")


class HelpPage(QWidget):
    def __init__(self, win):
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 12, 18, 12)
        lay.addWidget(page_title("Pomoc"))
        txt = QLabel(
            "<b>1. Konwersja</b> – wskaż swoją legalną instalację Morrowinda (Steam, GOG lub ręczną). Konwerter lokalnie "
            "przygotuje modele, tekstury, teren i świat. Oryginalne pliki nie są zmieniane, a wyników nie wolno "
            "publikować.<br><br><b>2. Mody</b> – instaluj archiwa ZIP/7z; każdy mod to osobna warstwa, mod niżej na liście "
            "wygrywa konflikty, „Zastosuj” przebudowuje tylko zmienione zasoby.<br><br><b>3. Profile</b> – różne zestawy "
            "modów i ustawień; przekonwertowana gra jest wspólna.<br><br><b>4. Graj</b> – gra startuje w osobnym procesie "
            "Godota. Sterowanie: WASD, mysz, Spacja – skok, Shift – bieg, E – drzwi, F – latanie.<br><br>"
            "<b>Construction Set</b> – edytor świata w Godocie; zmiany zapisuje jako warstwę projektu, bez nadpisywania "
            "ESM/ESP.<br><br>Dokumentacja: <i>docs/LAUNCHER.md</i> i <i>docs/DEBIAN13.md</i> w katalogu projektu.")
        txt.setWordWrap(True)
        txt.setTextFormat(Qt.RichText)
        lay.addWidget(txt)
        lay.addStretch(1)


class MainWindow(QWidget):
    def __init__(self, core: LauncherCore):
        super().__init__()
        self.core = core
        art.THEME_DIR = core.paths.config / "theme"
        set_lang(core.config["language"])
        self.setObjectName("root")
        self.setWindowTitle(f"{APP_NAME} Launcher {__version__} (alpha)")
        self.resize(1024, 683)
        self.setMinimumSize(920, 640)
        self.conv_runner = ConversionRunner(core.python(), core.converter_cwd(), self)
        self.game = GameRunner("game", self)
        self.editor = GameRunner("editor", self)
        self.game.exited.connect(self._game_exited)
        self.editor.exited.connect(self._editor_exited)
        self.conv_runner.finished.connect(self._conv_finished)
        self.last_message = ""
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        self.banner = Banner()
        outer.addWidget(self.banner)
        body = QHBoxLayout()
        body.setSpacing(0)
        outer.addLayout(body, 1)
        side = QFrame()
        side.setObjectName("sidebar")
        side.setFixedWidth(214)
        sl = QVBoxLayout(side)
        sl.setContentsMargins(8, 10, 8, 8)
        sl.setSpacing(3)
        self.nav = {}
        for key, ic, label in (("home", "home", "Strona główna"), ("conversion", "refresh", "Konwersja"),
                               ("mods", "cube", "Mody"), ("profiles", "layers", "Profile"),
                               ("settings", "sliders", "Ustawienia"), ("cs", "tools", "Construction Set")):
            b = QPushButton(" " + label)
            b.setProperty("class", "nav")
            b.setIcon(art.icon(ic, 22))
            b.setIconSize(QSize(22, 22))
            b.setCheckable(key != "cs")
            b.setCursor(Qt.PointingHandCursor)
            if key == "cs":
                b.clicked.connect(lambda _=False: self.launch_editor())
            else:
                b.clicked.connect(lambda _=False, k=key: self.show_page(k))
            sl.addWidget(b)
            self.nav[key] = b
        sl.addSpacing(8)
        sep = QFrame()
        sep.setProperty("class", "sep")
        sl.addWidget(sep)
        sl.addSpacing(4)
        for key, ic, label in (("diagnostics", "info", "Dziennik i diagnostyka"), ("help", "help", "Pomoc")):
            b = QPushButton(" " + label)
            b.setProperty("class", "navsmall")
            b.setIcon(art.icon(ic, 18))
            b.setCheckable(True)
            b.clicked.connect(lambda _=False, k=key: self.show_page(k))
            sl.addWidget(b)
            self.nav[key] = b
        sl.addStretch(1)
        gl = QHBoxLayout()
        gi = QLabel()
        gi.setPixmap(art.icon_pixmap("godot_chip", 30, "#8f8574"))
        self.godot_lbl = QLabel()
        self.godot_lbl.setStyleSheet(f"color: {theme.MUTED}; font-size: 9pt;")
        gl.addWidget(gi)
        gl.addWidget(self.godot_lbl, 1)
        sl.addLayout(gl)
        body.addWidget(side)
        self.stack = QStackedWidget()
        body.addWidget(self.stack, 1)
        from .page_conversion import ConversionPage
        from .page_mods import ModsPage
        from .page_settings import SettingsPage
        self.pages = {"home": HomePage(self), "conversion": ConversionPage(self), "mods": ModsPage(self),
                      "profiles": ProfilesPage(core, self), "settings": SettingsPage(self),
                      "diagnostics": DiagnosticsPage(self), "help": HelpPage(self)}
        for p in self.pages.values():
            self.stack.addWidget(p)
        sb = QFrame()
        sb.setObjectName("statusbar")
        sbl = QHBoxLayout(sb)
        sbl.setContentsMargins(12, 4, 12, 4)
        self.status_icon = QLabel()
        self.status_text = QLabel()
        sbl.addWidget(self.status_icon)
        sbl.addWidget(self.status_text, 1)
        for ic, text, fn in (("folder", "Otwórz katalog danych", lambda: self._open(self.core.converted_dir)),
                             ("logs", "Logi", lambda: self._open(self.core.paths.logs)),
                             ("info", "O projekcie", self.about)):
            b = QPushButton(" " + text)
            b.setProperty("class", "flat")
            b.setIcon(art.icon(ic, 18))
            b.clicked.connect(fn)
            sbl.addWidget(b)
        outer.addWidget(sb)
        self.show_page("home")

    # --- nawigacja ------------------------------------------------------------------------------
    def show_page(self, name: str):
        cur = self.stack.currentWidget() if hasattr(self, "stack") else None
        if cur is self.pages.get("settings") and name != "settings":
            cur.save()  # ustawienia zapisywane przy opuszczeniu strony
        page = self.pages[name]
        if hasattr(page, "refresh"):
            page.refresh()
        self.stack.setCurrentWidget(page)
        for k, b in self.nav.items():
            if b.isCheckable():
                b.setChecked(k == name)
        self.update_statusbar()

    def refresh_all(self):
        cur = self.stack.currentWidget()
        if hasattr(cur, "refresh"):
            cur.refresh()
        self.update_statusbar()

    def update_statusbar(self):
        gv = self.core.config["godot_version"]
        g = self.core.godot()
        head = f"Godot {gv.split('.stable')[0]}" if gv else ("Godot: znaleziono" if g else "Godot: brak")
        self.godot_lbl.setText(head + "\nMWGodot Runtime")
        if self.conv_runner.is_running():
            ic, txt = "dot", "Konwersja w toku…"
        elif self.game.is_running():
            ic, txt = "dot", "Gra działa"
        else:
            chk = self.core.check_play(False)
            ic, txt = ("ok", "Gotowy") if chk.ok else ("warn", "Wymaga uwagi: " + chk.problems[0][1][:90])
        self.status_icon.setPixmap(art.icon_pixmap(ic, 20))
        self.status_text.setText(txt)

    def _open(self, path: Path):
        Path(path).mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def about(self):
        self.message("O projekcie", f"{APP_NAME} {__version__} (alpha)\n\nEksperymentalny port Morrowinda na Godot 4. "
                                   "Projekt nie zawiera danych Bethesdy – gracz dostarcza własną, legalną instalację, "
                                   "konwertowaną lokalnie.\n\nMorrowind® i The Elder Scrolls® są znakami towarowymi "
                                   "ZeniMax Media Inc. Projekt nie jest z nimi powiązany.\n\nKod: licencja MIT.")

    def message(self, title: str, text: str, kind: str = "info"):
        self.last_message = text
        if QApplication.instance().property("headless_test"):
            return
        {"info": QMessageBox.information, "warn": QMessageBox.warning, "error": QMessageBox.critical}[kind](self, title, text)

    def confirm(self, title: str, text: str) -> bool:
        app = QApplication.instance()
        if app.property("headless_test"):
            return bool(app.property("auto_confirm"))
        return QMessageBox.question(self, title, text) == QMessageBox.Yes

    def _conv_finished(self, status: str, code: int):
        plan = self.core.plan()
        rec = conversion.read_record(plan) if plan else {}
        if status == "done":
            n = int(rec.get("files", 0))
            self.core.activity.add("ok", f"Konwersja zakończona pomyślnie ({n} {files_word(n)}, "
                                         f"{human_size(int(rec.get('bytes', 0)))})")
        elif status == "cancelled":
            self.core.activity.add("warn", "Konwersja przerwana – ukończone zasoby zachowane")
        else:
            self.core.activity.add("error", f"Konwersja nie powiodła się (kod {code})")
        self.refresh_all()

    # --- Graj ------------------------------------------------------------------------------------
    def play(self, extra_user: list[str] | None = None):
        if self.game.is_running():
            self.message("Gra", "Gra już działa w tym profilu.", "info")
            return False
        chk = self.core.check_play(self.conv_runner.is_running())
        if not chk.ok:
            self.message("Nie można uruchomić gry", "\n".join(f"• {m}" for _c, m in chk.problems), "warn")
            if chk.action in ("convert", "mods", "settings"):
                self.show_page({"convert": "conversion"}.get(chk.action, chk.action))
            return False
        lock = self.core.lock("game")
        holder = lock.holder()
        if holder and not self.confirm("Gra już działa",
                                       f"W tym profilu działa już gra (PID {holder}). Uruchomić drugą instancję?"):
            return False
        cmd = self.core.game_command(extra_user or self._test_extra())
        if not self.game.start(cmd, self.core.paths.logs, self.core.project_dir()):
            self.message("Błąd", f"Nie udało się uruchomić Godota:\n{cmd[0]}", "error")
            return False
        lock.acquire(self.game.pid())
        if self.core.config["minimize_on_play"] and not QApplication.instance().property("headless_test"):
            self.showMinimized()
        self.refresh_all()
        return True

    def _test_extra(self) -> list[str]:
        v = QApplication.instance().property("test_user_args")
        return list(v) if v else []

    def _game_exited(self, code: int, log: str):
        self.core.lock("game").release()
        self.showNormal()
        self.raise_()
        self.last_exit = code
        if code == 0 and not self.core.config["godot_version"]:
            from mwcore import launch  # wersja zapamiętywana raz, po pierwszej grze (nigdy przy starcie launchera)
            v = launch.godot_version(self.core.godot() or "")
            if v:
                self.core.config["godot_version"] = v
                self.core.config.save()
        if code != 0:
            self.core.activity.add("error", f"Gra zakończyła się błędem (kod {code})")
            self.message("Gra zakończyła się błędem", f"Kod wyjścia: {code}\nLog: {log}\n\n{log_tail(log)}", "error")
        self.refresh_all()

    # --- Construction Set ---------------------------------------------------------------------------
    def launch_editor(self, extra_user: list[str] | None = None):
        if self.editor.is_running():
            self.message("Construction Set", "Edytor już działa.", "info")
            return False
        chk = self.core.check_play(self.conv_runner.is_running())
        blocking = [m for c, m in chk.problems if c in ("install", "conversion", "godot", "project", "running")]
        if blocking:
            self.message("Nie można uruchomić edytora", "\n".join(f"• {m}" for m in blocking), "warn")
            return False
        cmd = self.core.editor_command(extra_user or self._test_extra())
        ok = self.editor.start(cmd, self.core.paths.logs, self.core.project_dir())
        if not ok:
            self.message("Błąd", "Nie udało się uruchomić Construction Set.", "error")
        return ok

    def _editor_exited(self, code: int, log: str):
        self.last_editor_exit = code
        if code != 0:
            self.core.activity.add("error", f"Construction Set zakończył się błędem (kod {code})")
            self.message("Construction Set zakończył się błędem", f"Kod wyjścia: {code}\nLog: {log}\n\n{log_tail(log)}",
                         "error")

    def closeEvent(self, e):
        if self.conv_runner.is_running():
            if not self.confirm("Konwersja w toku", "Przerwać konwersję i zamknąć launcher? Ukończone zasoby zostaną "
                                                    "zachowane, konwersję można później wznowić."):
                e.ignore()
                return
            self.conv_runner.cancel()
            self.conv_runner.proc.waitForFinished(25000)
        if self.game.is_running() and not self.confirm("Gra działa",
                                                       "Gra nadal działa. Zamknąć launcher? Gra zostanie zamknięta."):
            e.ignore()
            return
        e.accept()


def main(argv=None) -> int:
    app = QApplication.instance() or QApplication(argv if argv is not None else sys.argv)
    app.setApplicationName(APP_NAME)
    app.setDesktopFileName("openmwgodot")
    app.setStyleSheet(theme.QSS)
    from PySide6.QtGui import QIcon
    app.setWindowIcon(QIcon(theme.emblem(128)))
    core = LauncherCore()
    if not core.config["wizard_done"]:
        from .wizard import FirstRunWizard
        FirstRunWizard(core).exec()
    win = MainWindow(core)
    win.show()
    if os.environ.get("OPENMWGODOT_AUTOQUIT_MS"):  # testy: start i zamknięcie bez interakcji
        QTimer.singleShot(int(os.environ["OPENMWGODOT_AUTOQUIT_MS"]), app.quit)
    return app.exec()
