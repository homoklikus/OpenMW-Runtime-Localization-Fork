"""Ciemny motyw z delikatnym nawiązaniem do estetyki Morrowinda (brąz, mosiądz, pergamin) i własne
godło rysowane kodem (bez znaków towarowych i grafik Bethesdy)."""

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QBrush, QColor, QLinearGradient, QPainter, QPainterPath, QPen, QPixmap, QPolygonF

# Paleta z grafiki referencyjnej (średnie kolorów z próbek obrazu): grafitowe tło, ciemne karty,
# złote akcenty i ramki, zielone potwierdzenia, niebieskie informacje.
BG = "#0e0e0e"
PANEL = "#171819"
SIDEBAR = "#131314"
BORDER = "#3d3830"
TILE = "#282522"
TILE_BORDER = "#6e6457"
TEXT = "#ece6da"
MUTED = "#a8a090"
ACCENT = "#d7b46e"
ACCENT_DARK = "#8a6a32"
OK = "#5fb040"
WARN = "#d9a441"
ERR = "#d0644f"

QSS = f"""
* {{ color: {TEXT}; font-size: 10pt; }}
QWidget#root, QDialog, QWizard, QWizardPage {{ background: {BG}; }}
QLabel#title {{ font-size: 18pt; font-weight: 600; color: {ACCENT}; letter-spacing: 1px; }}
QLabel#subtitle, QLabel.muted {{ color: {MUTED}; }}
QLabel#version {{ color: {MUTED}; font-size: 9pt; }}
QFrame#panel {{ background: {PANEL}; border: 1px solid {BORDER}; border-radius: 6px; }}
QPushButton {{ background: #24211e; border: 1px solid {BORDER}; border-radius: 5px; padding: 6px 12px; }}
QPushButton:hover {{ border-color: {ACCENT_DARK}; background: #3a3029; }}
QPushButton:pressed {{ background: #2a231e; }}
QPushButton:disabled {{ color: #6f6556; border-color: #3a3129; }}
QPushButton#play {{ font-size: 16pt; font-weight: 700; color: #1b1714; padding: 10px 28px;
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #e0bf7c, stop:1 {ACCENT_DARK});
    border: 1px solid #f0d9a6; border-radius: 8px; }}
QPushButton#play:hover {{ background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #f0d090, stop:1 #9c7b44); }}
QPushButton#play:disabled {{ color: #4d4234; background: #5a4c38; border-color: #6a5a42; }}
QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox, QPlainTextEdit, QListWidget, QTableWidget, QTextEdit {{
    background: #101010; border: 1px solid {BORDER}; border-radius: 4px; padding: 3px; selection-background-color: {ACCENT_DARK}; }}
QComboBox QAbstractItemView {{ background: #120f0d; }}
QProgressBar {{ background: #120f0d; border: 1px solid {BORDER}; border-radius: 4px; text-align: center; height: 16px; }}
QProgressBar::chunk {{ background: {ACCENT_DARK}; border-radius: 3px; }}
QTabWidget::pane {{ border: 1px solid {BORDER}; border-radius: 4px; }}
QTabBar::tab {{ background: #2a231e; padding: 5px 10px; border: 1px solid {BORDER}; border-bottom: none; }}
QTabBar::tab:selected {{ background: {PANEL}; color: {ACCENT}; }}
QHeaderView::section {{ background: #2a231e; border: none; padding: 3px; }}
QCheckBox::indicator {{ width: 14px; height: 14px; }}
QToolTip {{ background: {PANEL}; border: 1px solid {ACCENT_DARK}; }}
QFrame#sidebar {{ background: {SIDEBAR}; border-right: 1px solid #26231f; }}
QPushButton.nav {{ text-align: left; padding: 9px 12px; border: 1px solid transparent; border-radius: 6px;
    background: transparent; font-size: 11pt; }}
QPushButton.nav:hover {{ background: #1e1c1a; border-color: #3d3830; }}
QPushButton.nav:checked {{ color: #fbf3df; font-weight: 600; border: 1px solid #c9a865;
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #a78850, stop:1 #61481b); }}
QPushButton.navsmall {{ text-align: left; padding: 6px 12px; border: none; background: transparent; font-size: 9.5pt; }}
QPushButton.navsmall:hover {{ color: {ACCENT}; }}
QFrame.card {{ background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #1b1b1b, stop:1 #161717);
    border: 1px solid #4a4237; border-radius: 8px; }}
QLabel.cardtitle {{ color: #e2c58c; font-size: 14pt; }}
QPushButton.tile {{ background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #2e2620, stop:1 #221c17);
    border: 1px solid #5a4a38; border-radius: 6px; padding: 8px 6px; }}
QPushButton.tile:hover {{ border-color: {ACCENT}; background: #352b23; }}
QToolButton {{ background: #24211e; border: 1px solid {BORDER}; border-radius: 5px; }}
QToolButton:hover {{ border-color: {ACCENT}; }}
QFrame#statusbar {{ background: #15110e; border-top: 1px solid #3a3027; }}
QPushButton.flat {{ background: transparent; border: none; padding: 4px 8px; }}
QPushButton.flat:hover {{ color: {ACCENT}; }}
QFrame.sep {{ background: #2e2b27; max-height: 1px; min-height: 1px; border: none; }}
"""


def emblem(size: int = 72) -> QPixmap:
    """Godło: mosiężny pierścień z trzema promieniami i grzbietem gór (własny projekt)."""
    pm = QPixmap(size, size)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    s = size
    c = QPointF(s / 2, s / 2)
    g = QLinearGradient(0, 0, 0, s)
    g.setColorAt(0, QColor("#f0d9a6"))
    g.setColorAt(1, QColor("#7a5c2e"))
    p.setPen(QPen(QBrush(g), s * 0.06))
    p.setBrush(QColor("#161515"))
    p.drawEllipse(c, s * 0.42, s * 0.42)
    # góry (sylwetka)
    path = QPainterPath()
    path.moveTo(s * 0.18, s * 0.66)
    for x, y in ((0.32, 0.44), (0.42, 0.55), (0.52, 0.34), (0.66, 0.56), (0.74, 0.48), (0.84, 0.66)):
        path.lineTo(s * x, s * y)
    path.closeSubpath()
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(ACCENT))
    p.drawPath(path)
    # promienie
    p.setPen(QPen(QColor("#f0d9a6"), s * 0.03, Qt.SolidLine, Qt.RoundCap))
    for dx in (-0.12, 0.0, 0.12):
        p.drawLine(QPointF(s * (0.52 + dx * 0.4), s * 0.30), QPointF(s * (0.52 + dx), s * 0.16))
    p.end()
    return pm


def status_color(state: str) -> str:
    return {"ready": OK, "running": ACCENT, "outdated": WARN, "incomplete": WARN}.get(state, ERR)
