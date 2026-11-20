"""Tłumaczenia launchera (pl, en): kompletność katalogu, brak tekstów wpisanych na stałe, prawdziwe okna w obu
językach, zmiana języka bez ponownego uruchomienia, zapamiętanie po ponownym uruchomieniu, kreator pierwszego
uruchomienia, komunikaty dynamiczne, niezależność języka launchera od języka gry."""

from __future__ import annotations

import ast
import json
import re
import string
from pathlib import Path

import pytest
from PySide6.QtWidgets import (QAbstractButton, QComboBox, QGroupBox, QLabel, QLineEdit, QListWidget, QTabWidget,
                               QWidget)

from test_launcher import convert_gui, make_window, wait_until

ROOT = Path(__file__).resolve().parents[2]
SOURCES = sorted((ROOT / "launcher" / "openmwgodot_launcher").glob("*.py")) + \
    sorted((ROOT / "converter" / "mwcore").glob("*.py"))
TR_FUNCS = ("tr", "N_", "translate")
# częste polskie słowa interfejsu – wykrywanie nie opiera się wyłącznie na diakrytykach
PL_WORDS = {"graj", "konwersja", "ustawienia", "mody", "profil", "wybierz", "wykryj", "napraw",
            "weryfikuj", "zastosuj", "odinstaluj", "anuluj", "dalej", "wstecz", "zakończ", "gotowe", "gotowy",
            "brak", "nie", "tak", "jest", "oraz", "albo", "katalog", "plik", "pliki", "plików", "dane", "gra",
            "gry", "grafika", "dźwięk", "sterowanie", "język", "świat", "zaawansowane", "pomoc", "logi", "dziennik",
            "strona", "główna", "kopiuj", "usuń", "nowy", "nazwa", "aktywny", "aktywne", "ostatnie",
            "działania", "instalacja", "instalacji", "rozmiar", "wymaga", "uwagi", "okno", "niska", "średnia",
            "wysoka", "wyłączone", "projekt", "projektu", "zasoby", "roślinność", "gęstość", "źródło", "cel",
            "zakres", "pełna", "tylko", "okolice", "uruchom", "otwórz", "sprawdź", "parametry", "konfiguracja"}
DIAC = re.compile(r"[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]")


def polish_hits(text: str) -> list[str]:
    t = re.sub(r"<[^>]+>|Calabró", " ", text)          # nazwiska nie są tekstem w danym języku
    out = ["diakrytyki"] if DIAC.search(t) else []
    out += [w for w in re.findall(r"[A-Za-zÀ-ž]+", t) if w.lower() in PL_WORDS]
    return out


def _trees():
    return [(f, ast.parse(f.read_text(encoding="utf-8"))) for f in SOURCES]


def catalog_keys() -> set[str]:
    keys = {"Domyślny"}
    for _f, t in _trees():
        for n in ast.walk(t):
            if not isinstance(n, ast.Call):
                continue
            name = getattr(n.func, "id", None) or getattr(n.func, "attr", None)
            if name in TR_FUNCS and n.args and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str):
                keys.add(n.args[0].value)
            if name == "add" and "activity" in ast.unparse(n.func) and len(n.args) >= 2:
                keys |= {c.value for c in ast.walk(n.args[1]) if isinstance(c, ast.Constant) and isinstance(c.value, str)}
    return keys


def _fields(s: str) -> set:
    return {f[1] for f in string.Formatter().parse(s) if f[1] is not None}


# --- katalog i kod --------------------------------------------------------------------------------------

def test_catalog_complete_and_consistent():
    from mwcore.i18n import missing
    from mwcore.i18n_en import EN
    keys = catalog_keys()
    assert len(keys) > 250
    assert missing(sorted(keys)) == []
    for k in keys:
        v = EN[k]
        assert _fields(k) == _fields(v), (k, v)                       # te same parametry {nazwa}
        assert k.count("%s") == v.count("%s") and k.count("%H") == v.count("%H"), k
        assert not polish_hits(v) or v == "Język / Language", (k, v)  # wpis angielski bez polskiego
    unused = set(EN) - keys
    assert not unused, f"nieużywane wpisy katalogu: {sorted(unused)[:10]}"


def test_no_hardcoded_polish_ui_text():
    """Literał z polskimi diakrytykami poza tr()/N_() (bez docstringów) i każdy literał podany wprost do
    wywołania Qt pokazującego tekst – błąd."""
    text_calls = {"QLabel", "QPushButton", "QCheckBox", "QGroupBox", "setText", "setToolTip", "setPlaceholderText",
                  "setTitle", "setSubTitle", "setWindowTitle", "addItem", "addRow", "message", "confirm", "getText",
                  "information", "warning", "critical", "question", "page_title", "card", "setButtonText", "addTab"}
    allowed = {"Construction Set", "English", "Polski", "Godot 4", "OK", "Python", "Start"}
    bad = []
    for f, t in _trees():
        ok = set()
        for n in ast.walk(t):
            if isinstance(n, (ast.Module, ast.FunctionDef, ast.ClassDef)) and n.body and isinstance(n.body[0], ast.Expr) \
                    and isinstance(n.body[0].value, ast.Constant):
                ok.add(id(n.body[0].value))
            if isinstance(n, ast.Call) and (getattr(n.func, "id", None) or getattr(n.func, "attr", None)) in TR_FUNCS + ("tr_stored",):
                ok |= {id(c) for a in n.args[:1] for c in ast.walk(a)}
            if isinstance(n, ast.Call) and getattr(n.func, "attr", None) == "add" and "activity" in ast.unparse(n.func):
                ok |= {id(c) for a in n.args[1:2] for c in ast.walk(a)}
        for n in ast.walk(t):
            if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in ok and DIAC.search(n.value):
                if f.name in ("i18n_en.py", "settings.py") or n.value in allowed or n.value == "Domyślny":
                    continue                                    # katalog i schemat z label_pl/label_en
                bad.append(f"{f.name}:{n.lineno} {n.value[:50]!r}")
            if isinstance(n, ast.Call) and (getattr(n.func, "id", None) or getattr(n.func, "attr", None)) in text_calls:
                for a in n.args[:2]:
                    stack = [a]
                    while stack:
                        c = stack.pop()
                        if isinstance(c, ast.Call) and (getattr(c.func, "id", None) or getattr(c.func, "attr", None)) in TR_FUNCS + ("str", "len", "join", "tr_stored", "human_size", "human_time"):
                            continue
                        if isinstance(c, ast.Constant) and isinstance(c.value, str):
                            plain = re.sub(r"<[^>]*>|&\w+;|%\w|\{[^}]*\}|#[0-9a-fA-F]{3,8}|https?://\S+", "", c.value)
                            if polish_hits(plain) and c.value.strip(" :") not in allowed:
                                bad.append(f"{f.name}:{c.lineno} {c.value[:50]!r}")
                            continue
                        stack.extend(ast.iter_child_nodes(c))
    assert not bad, bad[:15]


def test_no_tr_at_import_time():
    """tr() na poziomie modułu zamraża język sprzed wczytania konfiguracji (pierwotna przyczyna: LANG importowany
    przez wartość i stałe tłumaczone przy imporcie)."""
    bad = []
    for f, t in _trees():
        def visit(n, infunc):
            for c in ast.iter_child_nodes(n):
                fi = infunc or isinstance(c, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda))
                if isinstance(c, ast.Call) and getattr(c.func, "id", None) == "tr" and not infunc:
                    bad.append(f"{f.name}:{c.lineno}")
                visit(c, fi)
        visit(t, False)
        src = f.read_text(encoding="utf-8")
        assert not re.search(r"import LANG\b|i18n\.LANG\b", src), f.name
    assert not bad, bad


# --- prawdziwe okna ---------------------------------------------------------------------------------------

def widget_texts(root: QWidget) -> list[str]:
    out = []
    for w in [root] + root.findChildren(QWidget):
        if isinstance(w, QLabel):
            out.append(w.text())
        if isinstance(w, QAbstractButton):
            out.append(w.text())
        if isinstance(w, QComboBox):
            out += [w.itemText(i) for i in range(w.count())]
        if isinstance(w, QLineEdit):
            out.append(w.placeholderText())
        if isinstance(w, QGroupBox):
            out.append(w.title())
        if isinstance(w, QTabWidget):
            out += [w.tabText(i) for i in range(w.count())]
        if isinstance(w, QListWidget):
            out += [w.item(i).text() for i in range(w.count())]
        if w.toolTip():
            out.append(w.toolTip())
    return [t for t in out if t]


def all_pages_texts(w) -> list[str]:
    texts = []
    for name in w.pages:
        w.show_page(name, save_settings=False)
        texts += widget_texts(w)
    w.show_page("home", save_settings=False)
    return texts


def polish_in(texts: list[str], ignore=()) -> list[str]:
    return [f"{t[:60]!r} {polish_hits(t)}" for t in texts if polish_hits(t) and not any(i in t for i in ignore)]


def _settings_lang(w, lang: str):
    p = w.pages["settings"]
    w.show_page("settings")
    p.lang.setCurrentIndex(p.lang.findData(lang))       # jak wybór użytkownika: od razu, bez restartu


def test_launcher_pl_en_switch_restart_and_game_language(env, qapp, fake_game, tmp_path):
    cfgdir = tmp_path / "cfg" / "openmwgodot"
    cfgdir.mkdir(parents=True)
    (cfgdir / "launcher.json").write_text(json.dumps({"wizard_done": True, "language": "pl"}))
    # 1. start z language: pl – cały interfejs po polsku (wybrane napisy kluczowe)
    w = make_window()
    w.core.set_install(str(fake_game))
    pl_texts = all_pages_texts(w)
    for must in ("Strona główna", "Konwersja", "Ustawienia", "Graj", "Dziennik i diagnostyka", "Język launchera"):
        assert any(must in t for t in pl_texts), must
    game_lang_before = w.core.profile.settings.get("game_language", "auto")
    rt_before = w.core.runtime_args()
    # 2. przełączenie na EN bez restartu
    _settings_lang(w, "en")
    assert w.core.config["language"] == "en"
    assert w.current_page() == "settings"
    en_texts = all_pages_texts(w)
    bad = polish_in(en_texts, ignore=("Polski",))
    assert not bad, bad[:10]
    for must in ("Home", "Conversion", "Settings", "Play", "Log and diagnostics", "Launcher language"):
        assert any(must in t for t in en_texts), must
    assert "Polski" in widget_texts(w.pages["settings"])      # nazwa języka w jego własnym języku
    # 4. komunikaty dynamiczne: pasek stanu, problemy „Graj”, dziennik działań (wpis zapisany po polsku)
    w.core.activity.add("ok", "Zainstalowano mod „{name}”", name="X")
    w.show_page("home")
    home_texts = widget_texts(w.pages["home"])
    assert any("Installed mod “X”" in t for t in home_texts), home_texts
    assert not polish_in(widget_texts(w)), polish_in(widget_texts(w))
    res, _page = convert_gui(qapp, w)
    assert res["status"] == "done"
    conv_texts = widget_texts(w.pages["conversion"])
    assert not polish_in(conv_texts, ignore=("Polski",)), polish_in(conv_texts)
    # 7. język gry nie zmienił się wskutek zmiany języka launchera
    gl = w.core.profile.settings.get("game_language")
    assert gl == (game_lang_before if game_lang_before != "auto" else "pl"), gl
    rt = json.loads(Path([a for a in w.core.runtime_args() if a.startswith("--settings=")][0].split("=", 1)[1]).read_text())
    rt_b = json.loads(Path([a for a in rt_before if a.startswith("--settings=")][0].split("=", 1)[1]).read_text()) \
        if any(a.startswith("--settings=") for a in rt_before) else {}
    effective = lambda r: r.get("language") if r.get("game_language", "auto") == "auto" else r.get("game_language")  # noqa: E731
    assert effective(rt) == "pl" and (not rt_b or effective(rt_b) == "pl"), (rt, rt_b)
    w.close()
    # 5. zamknięcie i ponowne uruchomienie – EN zapamiętany
    w2 = make_window()
    assert not polish_in(all_pages_texts(w2), ignore=("Polski",))
    assert w2.pages["settings"].lang.currentData() == "en"
    # 6. powrót na PL
    _settings_lang(w2, "pl")
    pl2 = all_pages_texts(w2)
    assert any("Strona główna" in t for t in pl2) and not any(t == "Home" for t in pl2)
    assert json.loads((cfgdir / "launcher.json").read_text())["language"] == "pl"
    assert w2.core.profile.settings.get("game_language") == gl       # gra nadal w tym samym języku
    w2.close()


def test_first_run_wizard_language(env, qapp):
    from openmwgodot_launcher.core import LauncherCore
    from openmwgodot_launcher.wizard import FirstRunWizard
    core = LauncherCore()
    core.config["language"] = "en"
    core.config.save()
    wz = FirstRunWizard(core)                 # kreator w języku launchera (wcześniej zawsze po polsku)
    texts = widget_texts(wz) + [wz.windowTitle()] + [wz.page(i).title() + wz.page(i).subTitle() for i in wz.pageIds()]
    assert not polish_in(texts, ignore=("Polski", "Język / Language")), polish_in(texts)
    assert wz.lang.currentData() == "en"
    wz.lang.setCurrentIndex(wz.lang.findData("pl"))          # zmiana na stronie języka – reszta stron po polsku
    titles = [wz.page(i).title() for i in wz.pageIds()]
    assert "Instalacja Morrowinda" in titles and core.config["language"] == "pl"
    wz.lang.setCurrentIndex(wz.lang.findData("en"))
    titles = [wz.page(i).title() for i in wz.pageIds()]
    assert "Morrowind installation" in titles and len(titles) == 5
    wz.close()


@pytest.mark.parametrize("lang", ["pl", "en"])
def test_mwcore_messages_follow_language(lang):
    from mwcore import i18n
    from mwcore.profiles import Profile
    prev = i18n.get_lang()
    i18n.set_lang(lang)
    try:
        assert i18n.tr("nie ma moda {mod_id}", mod_id="m") == ("nie ma moda m" if lang == "pl" else "no such mod m")
        assert Profile("default", "Domyślny").display_name == ("Domyślny" if lang == "pl" else "Default")
        assert Profile("default", "Moja gra").display_name == "Moja gra"
        assert i18n.tr_stored("Usunięto profil „{name}” (zapisy gry zachowane)", {"name": "Domyślny"}) == (
            "Usunięto profil „Domyślny” (zapisy gry zachowane)" if lang == "pl"
            else "Deleted profile “Default” (saved games kept)")
    finally:
        i18n.set_lang(prev)
