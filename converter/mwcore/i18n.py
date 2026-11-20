"""Tłumaczenia interfejsu launchera i komunikatów mwcore (pl – język źródłowy, en – katalog `i18n_en`).

Kluczem jest tekst źródłowy (polski), jak w gettext: `tr("Graj")` → „Graj” albo „Play”. Parametry przez nazwy:
`tr("Usunąć profil „{name}”?", name=n)`. Brak tłumaczenia → tekst źródłowy (test `test_i18n` pilnuje, żeby
każdy klucz miał wpis w katalogu angielskim).

Język launchera (`language` w konfiguracji launchera) jest niezależny od języka gry (`game_language` profilu).
"""

from __future__ import annotations

LANGS = ("pl", "en")
_lang = "pl"
_catalog: dict[str, str] | None = None


def _en() -> dict[str, str]:
    global _catalog
    if _catalog is None:
        from .i18n_en import EN
        _catalog = EN
    return _catalog


def set_lang(lang: str) -> None:
    global _lang
    _lang = lang if lang in LANGS else "pl"


def get_lang() -> str:
    return _lang


def translate(src: str, lang: str | None = None) -> str:
    if (lang or _lang) == "en":
        return _en().get(src, src)
    return src


def tr(src: str, **kw) -> str:
    """Tekst w bieżącym języku; z parametrami – str.format na przetłumaczonym szablonie."""
    t = translate(src)
    return t.format(**kw) if kw else t


def tr_stored(src: str, args: dict | None = None) -> str:
    """Tekst zapisany jako szablon źródłowy (dziennik działań): tłumaczony przy wyświetlaniu, także argumenty
    będące tekstami z katalogu."""
    if not args:
        return translate(src)
    a = {k: (translate(v) if isinstance(v, str) else v) for k, v in args.items()}
    try:
        return translate(src).format(**a)
    except (KeyError, IndexError, ValueError):
        return src


def missing(keys) -> list[str]:
    """Klucze bez tłumaczenia angielskiego (dla testów)."""
    en = _en()
    return [k for k in keys if k not in en]
