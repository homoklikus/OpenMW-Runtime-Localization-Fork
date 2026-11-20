"""Tłumaczenia interfejsu launchera (pl, en) – wspólny katalog z mwcore (`mwcore.i18n`, `mwcore.i18n_en`).

Kluczem jest tekst polski; `N_()` oznacza tekst do przetłumaczenia dopiero przy użyciu (stałe modułów – `tr()`
przy imporcie zamroziłby język sprzed wczytania konfiguracji). Język launchera jest niezależny od języka gry.
"""

from mwcore.i18n import LANGS, get_lang, set_lang, tr, tr_stored, translate  # noqa: F401


def N_(src: str) -> str:  # noqa: N802 – nazwa jak w gettext
    return src
