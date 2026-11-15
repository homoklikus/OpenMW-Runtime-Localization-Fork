"""Grafika launchera rysowana kodem (własny projekt, bez zasobów i znaków towarowych Bethesdy):
ikony liniowe, baner z krajobrazem wulkanicznym, ilustracja podglądu, ozdobny przycisk „Graj”."""

from __future__ import annotations

import math
import random

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (QBrush, QColor, QFont, QIcon, QLinearGradient, QPainter, QPainterPath, QPen, QPixmap,
                           QRadialGradient)

GOLD = QColor("#d9b878")
GOLD_DARK = QColor("#8a6c3a")

SERIF = ["Cinzel", "Trajan Pro", "Noto Serif Display", "Noto Serif", "DejaVu Serif", "Liberation Serif", "serif"]


def serif_font(px: int, bold: bool = False) -> QFont:
    f = QFont()
    f.setFamilies(SERIF)
    f.setPixelSize(px)
    f.setBold(bold)
    return f


# --- ikony ----------------------------------------------------------------------------------------

def _pen(p: QPainter, color: QColor, w: float):
    pen = QPen(color, w, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
    p.setPen(pen)
    p.setBrush(Qt.NoBrush)


def icon_pixmap(name: str, size: int = 24, color: str | QColor = "#e6dcc6") -> QPixmap:
    pm = QPixmap(size, size)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    c = QColor(color)
    s = size / 24.0
    p.scale(s, s)
    _pen(p, c, 1.8)
    pt = QPointF
    if name == "home":
        path = QPainterPath(pt(3, 11))
        for x, y in ((12, 3.5), (21, 11)):
            path.lineTo(x, y)
        p.drawPath(path)
        p.drawPolyline([pt(5.5, 9.5), pt(5.5, 20), pt(18.5, 20), pt(18.5, 9.5)])
        p.drawRect(QRectF(10, 14, 4, 6))
    elif name == "refresh":
        p.drawArc(QRectF(4, 4, 16, 16), 30 * 16, 150 * 16)
        p.drawArc(QRectF(4, 4, 16, 16), 210 * 16, 150 * 16)
        p.drawPolyline([pt(17.5, 3.5), pt(18.9, 8.1), pt(14.3, 8.3)])
        p.drawPolyline([pt(6.5, 20.5), pt(5.1, 15.9), pt(9.7, 15.7)])
    elif name == "cube":
        p.drawPolygon([pt(12, 3), pt(20, 7.5), pt(20, 16.5), pt(12, 21), pt(4, 16.5), pt(4, 7.5)])
        p.drawPolyline([pt(4, 7.5), pt(12, 12), pt(20, 7.5)])
        p.drawLine(pt(12, 12), pt(12, 21))
    elif name == "layers":
        p.drawPolygon([pt(12, 3.5), pt(21, 8), pt(12, 12.5), pt(3, 8)])
        p.drawPolyline([pt(3, 12), pt(12, 16.5), pt(21, 12)])
        p.drawPolyline([pt(3, 16), pt(12, 20.5), pt(21, 16)])
    elif name == "sliders":
        for y, x in ((6, 15), (12, 8), (18, 13)):
            p.drawLine(pt(3, y), pt(21, y))
            p.setBrush(QColor("#131314"))
            p.drawEllipse(pt(x, y), 2.4, 2.4)
            p.setBrush(Qt.NoBrush)
    elif name == "tools":
        p.drawLine(pt(5, 19), pt(14, 10))
        p.drawArc(QRectF(12, 3, 9, 9), 200 * 16, 260 * 16)
        p.drawLine(pt(6, 5), pt(19, 18))
        p.drawRect(QRectF(3.5, 3.5, 4, 3))
    elif name == "info":
        p.drawEllipse(pt(12, 12), 9, 9)
        p.drawLine(pt(12, 11), pt(12, 16.5))
        p.setBrush(c)
        p.drawEllipse(pt(12, 7.6), 0.9, 0.9)
    elif name == "help":
        p.drawEllipse(pt(12, 12), 9, 9)
        path = QPainterPath(pt(9.3, 9.6))
        path.cubicTo(pt(9.3, 6.5), pt(14.8, 6.5), pt(14.8, 9.6))
        path.cubicTo(pt(14.8, 11.5), pt(12, 11.6), pt(12, 13.8))
        p.drawPath(path)
        p.setBrush(c)
        p.drawEllipse(pt(12, 16.8), 0.9, 0.9)
    elif name == "folder":
        p.drawPolygon([pt(3, 6), pt(9, 6), pt(11, 8), pt(21, 8), pt(21, 19), pt(3, 19)])
    elif name == "logs":
        p.drawRect(QRectF(5, 3, 14, 18))
        for y in (8, 12, 16):
            p.drawLine(pt(8, y), pt(16, y))
    elif name == "user":
        p.drawEllipse(pt(12, 8), 4, 4)
        path = QPainterPath(pt(4, 20.5))
        path.cubicTo(pt(4.5, 13.5), pt(19.5, 13.5), pt(20, 20.5))
        p.drawPath(path)
    elif name == "puzzle":
        path = QPainterPath(pt(4, 8))
        for x, y in ((9, 8), (9, 6)):
            path.lineTo(x, y)
        path.arcTo(QRectF(9, 3, 4, 4), 180, -180)
        for x, y in ((13, 8), (18, 8), (18, 12)):
            path.lineTo(x, y)
        path.arcTo(QRectF(18, 12, 4, 4), 90, -180)
        for x, y in ((18, 20), (4, 20)):
            path.lineTo(x, y)
        path.closeSubpath()
        p.drawPath(path)
    elif name == "database":
        p.drawEllipse(QRectF(5, 3, 14, 5))
        p.drawLine(pt(5, 5.5), pt(5, 18.5))
        p.drawLine(pt(19, 5.5), pt(19, 18.5))
        p.drawArc(QRectF(5, 9.5, 14, 5), 180 * 16, 180 * 16)
        p.drawArc(QRectF(5, 16, 14, 5), 180 * 16, 180 * 16)
    elif name == "calendar":
        p.drawRect(QRectF(4, 5, 16, 15))
        p.drawLine(pt(4, 9.5), pt(20, 9.5))
        p.drawLine(pt(8, 3), pt(8, 7))
        p.drawLine(pt(16, 3), pt(16, 7))
    elif name == "gear":
        p.drawEllipse(pt(12, 12), 3, 3)
        for k in range(8):
            a = k * math.pi / 4
            p.drawLine(pt(12 + 6 * math.cos(a), 12 + 6 * math.sin(a)), pt(12 + 8.5 * math.cos(a), 12 + 8.5 * math.sin(a)))
        p.drawEllipse(pt(12, 12), 6, 6)
    elif name in ("ok", "warn", "err", "dot"):
        col = {"ok": QColor("#3f8f2c"), "warn": QColor("#c99a2e"), "err": QColor("#b5483a"), "dot": QColor("#3a6fb0")}[name]
        p.setPen(Qt.NoPen)
        p.setBrush(col)
        p.drawEllipse(pt(12, 12), 10, 10)
        _pen(p, QColor("#ffffff"), 2.4)
        if name == "ok":
            p.drawPolyline([pt(7, 12.5), pt(10.5, 16), pt(17, 8.5)])
        elif name == "warn":
            p.drawLine(pt(12, 6.5), pt(12, 13))
            p.drawPoint(pt(12, 17))
        elif name == "err":
            p.drawLine(pt(8, 8), pt(16, 16))
            p.drawLine(pt(16, 8), pt(8, 16))
        else:
            p.drawLine(pt(12, 10.5), pt(12, 17))
            p.drawPoint(pt(12, 7))
    elif name == "play":
        p.setPen(Qt.NoPen)
        g = QLinearGradient(0, 3, 0, 21)
        g.setColorAt(0, QColor("#ffd777"))
        g.setColorAt(1, QColor("#c08a20"))
        p.setBrush(g)
        p.drawPolygon([pt(6, 3.5), pt(20.5, 12), pt(6, 20.5)])
    elif name == "godot_chip":
        p.drawRoundedRect(QRectF(3, 6, 18, 13), 4, 4)
        p.drawEllipse(pt(9, 12.5), 2, 2)
        p.drawEllipse(pt(15, 12.5), 2, 2)
        p.drawLine(pt(7, 6), pt(6, 3))
        p.drawLine(pt(17, 6), pt(18, 3))
    p.end()
    return pm


def icon(name: str, size: int = 24, color: str = "#e6dcc6") -> QIcon:
    ic = QIcon(icon_pixmap(name, size, color))
    ic.addPixmap(icon_pixmap(name, size, "#f4dfaa"), QIcon.Active)
    return ic


# --- baner ------------------------------------------------------------------------------------------

def banner(w: int, h: int, seed: int = 7) -> QPixmap:
    """Zmierzch nad krainą wulkaniczną: niebo, dymiący wulkan z lawą, grzbiety, sylwetka miasta (własny rysunek)."""
    rnd = random.Random(seed)
    pm = QPixmap(w, h)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    sky = QLinearGradient(0, 0, 0, h)
    sky.setColorAt(0.0, QColor("#3a1d1c"))
    sky.setColorAt(0.35, QColor("#5e2e2b"))
    sky.setColorAt(0.7, QColor("#8a4e4b"))
    sky.setColorAt(1.0, QColor("#2a1a18"))
    p.fillRect(0, 0, w, h, sky)
    # chmury
    for _ in range(26):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h * 0.5)
        r = rnd.uniform(w * 0.04, w * 0.12)
        g = QRadialGradient(QPointF(x, y), r)
        g.setColorAt(0, QColor(40, 18, 16, 90))
        g.setColorAt(1, QColor(40, 18, 16, 0))
        p.setPen(Qt.NoPen)
        p.setBrush(g)
        p.drawEllipse(QPointF(x, y), r * 1.8, r * 0.6)
    vx = w * 0.56
    # dym
    for k in range(18):
        t = k / 18
        x = vx + math.sin(t * 5) * w * 0.02 + t * w * 0.05
        y = h * 0.38 - t * h * 0.45
        r = h * (0.04 + t * 0.12)
        g = QRadialGradient(QPointF(x, y), r)
        g.setColorAt(0, QColor(30, 24, 24, 160))
        g.setColorAt(1, QColor(30, 24, 24, 0))
        p.setBrush(g)
        p.drawEllipse(QPointF(x, y), r, r)
    # wulkan
    mtn = QPainterPath(QPointF(w * 0.30, h))
    mtn.lineTo(vx - w * 0.035, h * 0.40)
    mtn.lineTo(vx + w * 0.03, h * 0.40)
    mtn.lineTo(w * 0.86, h)
    mtn.closeSubpath()
    mg = QLinearGradient(0, h * 0.4, 0, h)
    mg.setColorAt(0, QColor("#3a2c2a"))
    mg.setColorAt(1, QColor("#141110"))
    p.setBrush(mg)
    p.drawPath(mtn)
    # lawa
    _pen(p, QColor(255, 120, 40, 200), max(1.5, h * 0.008))
    for dx in (-0.012, 0.004, 0.018):
        path = QPainterPath(QPointF(vx + w * dx * 0.5, h * 0.41))
        for k in range(1, 6):
            path.lineTo(vx + w * dx * (1 + k * 0.9) + rnd.uniform(-3, 3), h * (0.41 + k * 0.07))
        p.drawPath(path)
    glow = QRadialGradient(QPointF(vx, h * 0.40), h * 0.12)
    glow.setColorAt(0, QColor(255, 140, 60, 170))
    glow.setColorAt(1, QColor(255, 140, 60, 0))
    p.setPen(Qt.NoPen)
    p.setBrush(glow)
    p.drawEllipse(QPointF(vx, h * 0.40), h * 0.12, h * 0.08)
    # grzbiety
    for layer, (col, base, amp) in enumerate(((QColor("#241c1a"), 0.78, 0.10), (QColor("#151211"), 0.88, 0.07))):
        path = QPainterPath(QPointF(0, h))
        x = 0.0
        while x <= w:
            path.lineTo(x, h * base - abs(math.sin(x / w * 7 + layer * 2)) * h * amp - rnd.uniform(0, h * 0.02))
            x += w / 60
        path.lineTo(w, h)
        path.closeSubpath()
        p.setBrush(col)
        p.drawPath(path)
    # sylwetka miasta z oświetlonymi oknami (prawa strona)
    p.setBrush(QColor("#120c0b"))
    x = w * 0.62
    while x < w * 0.98:
        bw = rnd.uniform(w * 0.012, w * 0.03)
        bh = rnd.uniform(h * 0.06, h * 0.22)
        top = h * 0.86 - bh
        p.drawRect(QRectF(x, top, bw, bh + h * 0.2))
        if rnd.random() < 0.3:
            p.drawEllipse(QPointF(x + bw / 2, top), bw * 0.5, bw * 0.35)
        for _ in range(int(bh / (h * 0.04))):
            if rnd.random() < 0.5:
                p.fillRect(QRectF(x + rnd.uniform(1, bw - 3), top + rnd.uniform(2, bh - 4), 2, 2), QColor("#f0b860"))
        x += bw + rnd.uniform(1, w * 0.01)
    # grzybowa wieża (prawa strona) i skały – własna sylwetka
    p.setBrush(QColor("#151110"))
    tx, ty = w * 0.83, h * 0.86
    stem = QPainterPath(QPointF(tx - w * 0.008, ty))
    stem.cubicTo(QPointF(tx - w * 0.012, ty - h * 0.25), QPointF(tx + w * 0.02, ty - h * 0.35), QPointF(tx + w * 0.012, ty - h * 0.52))
    stem.lineTo(tx + w * 0.026, ty - h * 0.52)
    stem.cubicTo(QPointF(tx + w * 0.034, ty - h * 0.33), QPointF(tx + w * 0.006, ty - h * 0.22), QPointF(tx + w * 0.012, ty))
    stem.closeSubpath()
    p.drawPath(stem)
    cap = QPainterPath(QPointF(tx - w * 0.05, ty - h * 0.50))
    cap.cubicTo(QPointF(tx - w * 0.03, ty - h * 0.82), QPointF(tx + w * 0.07, ty - h * 0.82), QPointF(tx + w * 0.09, ty - h * 0.52))
    cap.cubicTo(QPointF(tx + w * 0.03, ty - h * 0.56), QPointF(tx - w * 0.01, ty - h * 0.56), QPointF(tx - w * 0.05, ty - h * 0.50))
    p.drawPath(cap)
    for k in range(3):
        rx = w * (0.9 + k * 0.035)
        rock = QPainterPath(QPointF(rx - w * 0.03, h))
        rock.lineTo(rx - w * 0.01, h * (0.55 + 0.08 * k))
        rock.lineTo(rx + w * 0.012, h * (0.48 + 0.1 * k))
        rock.lineTo(rx + w * 0.03, h)
        rock.closeSubpath()
        p.drawPath(rock)
    # przyciemnienie od lewej (miejsce na tytuł) i dół
    fade = QLinearGradient(0, 0, w, 0)
    fade.setColorAt(0, QColor(14, 14, 14, 240))
    fade.setColorAt(0.38, QColor(14, 14, 14, 150))
    fade.setColorAt(0.55, QColor(14, 14, 14, 0))
    p.fillRect(0, 0, w, h, fade)
    bot = QLinearGradient(0, h * 0.7, 0, h)
    bot.setColorAt(0, QColor(14, 14, 14, 0))
    bot.setColorAt(1, QColor(14, 14, 14, 255))
    p.fillRect(0, 0, w, h, bot)
    p.end()
    return pm


def preview(w: int, h: int, caption: str = "") -> QPixmap:
    """Ilustracja w panelu „Stan instalacji”: kamienne domy o zaokrąglonych dachach pod górą (własny rysunek).
    Po pierwszej sesji gry zastępuje ją widok z gry zapisany lokalnie przez Runtime."""
    rnd = random.Random(5)
    pm = QPixmap(w, h)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    sky = QLinearGradient(0, 0, 0, h)
    sky.setColorAt(0, QColor("#4f6f97"))
    sky.setColorAt(0.6, QColor("#a9b3ba"))
    sky.setColorAt(1, QColor("#d7c3a0"))
    p.fillRect(0, 0, w, h, sky)
    p.setPen(Qt.NoPen)
    for col, pts in ((QColor("#7c8592"), [(0, .62), (.18, .38), (.33, .18), (.5, .36), (.62, .30), (.8, .5), (1, .42)]),
                     (QColor("#6a6458"), [(0, .7), (.25, .55), (.45, .62), (.7, .5), (1, .6)])):
        path = QPainterPath(QPointF(0, h))
        for x, y in pts:
            path.lineTo(w * x, h * y)
        path.lineTo(w, h)
        path.closeSubpath()
        p.setBrush(col)
        p.drawPath(path)
    ground = QLinearGradient(0, h * 0.75, 0, h)
    ground.setColorAt(0, QColor("#8f7d62"))
    ground.setColorAt(1, QColor("#5d5040"))
    p.fillRect(QRectF(0, h * 0.78, w, h * 0.22), ground)
    x = -w * 0.03
    while x < w:
        bw = w * rnd.uniform(0.17, 0.24)
        bh = h * rnd.uniform(0.32, 0.5)
        top = h * 0.82 - bh
        g = QLinearGradient(x, 0, x + bw, 0)
        g.setColorAt(0, QColor("#b39b77"))
        g.setColorAt(0.7, QColor("#8c7656"))
        g.setColorAt(1, QColor("#5e4e39"))
        p.setBrush(g)
        body = QPainterPath()
        body.moveTo(x, h * 0.84)
        body.lineTo(x, top + bw * 0.25)
        body.quadTo(x + bw / 2, top - bw * 0.12, x + bw, top + bw * 0.25)
        body.lineTo(x + bw, h * 0.84)
        body.closeSubpath()
        p.drawPath(body)
        p.setBrush(QColor(40, 30, 22, 220))
        p.drawRoundedRect(QRectF(x + bw * 0.38, h * 0.84 - bh * 0.42, bw * 0.24, bh * 0.42), bw * 0.12, bw * 0.12)
        for wy in (0.35, 0.55):
            p.drawRect(QRectF(x + bw * 0.15, top + bh * wy, bw * 0.09, bh * 0.08))
            p.drawRect(QRectF(x + bw * 0.76, top + bh * wy, bw * 0.09, bh * 0.08))
        if rnd.random() < 0.6:
            p.setBrush(QColor("#9b3527"))
            p.drawRect(QRectF(x + bw * 0.62, top + bh * 0.12, bw * 0.12, bh * 0.32))
        x += bw + w * rnd.uniform(0.0, 0.03)
    shade = QLinearGradient(0, 0, w, 0)
    shade.setColorAt(0, QColor(0, 0, 0, 60))
    shade.setColorAt(0.5, QColor(0, 0, 0, 0))
    shade.setColorAt(1, QColor(0, 0, 0, 50))
    p.fillRect(0, 0, w, h, shade)
    if caption:
        p.setPen(QColor("#f2ead8"))
        f = QFont()
        f.setPixelSize(max(10, h // 14))
        p.setFont(f)
        p.drawText(QRectF(0, 0, w - 8, h - 6), Qt.AlignRight | Qt.AlignBottom, caption)
    p.end()
    return pm


# --- lokalny motyw użytkownika ------------------------------------------------------------------
# Launcher nie zawiera grafik z gry ani logo Morrowind. Użytkownik może jednak położyć własne obrazy
# w katalogu konfiguracji: <config>/theme/banner.png i <config>/theme/preview.png. Pliki są czytane
# tylko lokalnie, nigdy nie trafiają do repozytorium ani raportów.
THEME_DIR: "Path | None" = None


def user_image(name: str, w: int, h: int):
    from pathlib import Path  # noqa: F401
    if THEME_DIR is None:
        return None
    f = THEME_DIR / f"{name}.png"
    if not f.is_file():
        return None
    pm = QPixmap(str(f))
    if pm.isNull():
        return None
    pm = pm.scaled(w, h, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
    return pm.copy((pm.width() - w) // 2, (pm.height() - h) // 2, w, h)


RESOURCES = __import__("pathlib").Path(__file__).resolve().parent.parent / "resources"


def image_banner(w: int, h: int):
    """Baner z pejzażem z grafiki referencyjnej (resources/banner.png): obraz dosunięty do prawej,
    z lewej płynne przejście w tło okna pod godło i tytuł. None, gdy pliku brak."""
    f = RESOURCES / "banner.png"
    src = QPixmap(str(f)) if f.is_file() else QPixmap()
    if src.isNull():
        return None
    img = src.scaledToHeight(h, Qt.SmoothTransformation)
    if img.width() < w * 0.55:  # bardzo szerokie okno – powiększ, żeby obraz zajmował większość banera
        img = src.scaledToWidth(int(w * 0.55), Qt.SmoothTransformation)
        img = img.copy(0, (img.height() - h) // 2, img.width(), h)
    pm = QPixmap(w, h)
    pm.fill(QColor("#0e0e0e"))
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    # tło po lewej: ciemne karmazynowe niebo dopasowane do lewej krawędzi obrazu
    sky = QLinearGradient(0, 0, 0, h)
    sky.setColorAt(0, QColor("#2a1a1a"))
    sky.setColorAt(0.6, QColor("#3a2322"))
    sky.setColorAt(1, QColor("#141110"))
    p.fillRect(0, 0, w, h, sky)
    x0 = w - img.width()
    p.drawPixmap(x0, 0, img)
    fade = QLinearGradient(x0, 0, x0 + img.width() * 0.35, 0)
    fade.setColorAt(0, QColor(42, 26, 26, 255))
    fade.setColorAt(1, QColor(42, 26, 26, 0))
    p.fillRect(x0, 0, int(img.width() * 0.35) + 1, h, fade)
    left = QLinearGradient(0, 0, w * 0.5, 0)
    left.setColorAt(0, QColor(14, 14, 14, 200))
    left.setColorAt(1, QColor(14, 14, 14, 0))
    p.fillRect(0, 0, w, h, left)
    bot = QLinearGradient(0, h * 0.75, 0, h)
    bot.setColorAt(0, QColor(14, 14, 14, 0))
    bot.setColorAt(1, QColor(14, 14, 14, 230))
    p.fillRect(0, 0, w, h, bot)
    p.end()
    return pm


def image_preview(w: int, h: int):
    """Ilustracja do karty „Stan instalacji” (resources/preview.png); None, gdy pliku brak."""
    f = RESOURCES / "preview.png"
    pm = QPixmap(str(f)) if f.is_file() else QPixmap()
    if pm.isNull():
        return None
    pm = pm.scaled(w, h, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
    return pm.copy((pm.width() - w) // 2, (pm.height() - h) // 2, w, h)
