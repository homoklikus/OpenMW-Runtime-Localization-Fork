#!/usr/bin/env python3
"""Tabela zgodności funkcji MWScript (docs/INWENTARYZACJA-OPENMW.md, punkt 4a).

Wejście: JSON {funkcja: liczba skryptów} policzony z danych gracza (Morrowind + Tribunal + Bloodmoon) po kompilacji
konwerterem – plik lokalny, nie trafia do repozytorium (tylko nazwy funkcji i liczby). Wyjście: tabela Markdown.
Statusy i wyniki porównań są wpisane niżej ręcznie – po każdym porównaniu (tools/openmw-xvfb/mwscript_compare.py)
uzupełnij słowniki VERIFIED/PARTIAL/MISSING.
  python3 tools/gen_mwscript_inventory.py fn_usage.json > tabela.md"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "converter"))
from mwconv.mwscript_sig import SIG  # noqa: E402

# przypadek porównawczy (tools/openmw-xvfb/mwscript_cases/*.json) → funkcje sprawdzone w nim z wynikiem „0 różnic”
CASES = {
    "stats_player": "setstrength modstrength modagility setintelligence modlongblade setsneak modacrobatics modalteration "
                    "modhealth modcurrenthealth modmagicka modcurrentmagicka modcurrentfatigue modfatigue setresistfire "
                    "modresistshock setwaterwalking modswimspeed setlevel gethealth gethealthgetratio getstrength getlongblade "
                    "getresistfire getlevel getmagicka sethealth setmagicka setfatigue setacrobatics setalteration "
                    "setagility setspeed setendurance setpersonality setluck setwillpower setlongblade position",
    "stats_npc": "sethealth modhealth modcurrentfatigue setintelligence modspeechcraft setsecurity setresistfire modendurance "
                 "setlevel modcurrenthealth modmagicka setwillpower modresistshock modcurrentmagicka setchameleon setstrength "
                 "modfatigue setfatigue gethealth getfatiguegetratio getresistfire getwillpower getchameleon",
    "werewolf": "becomewerewolf setwerewolfacrobatics iswerewolf getacrobatics getwerewolfkills sethandtohand getpccrimelevel",
    "werewolf_undo": "undowerewolf",
    "misc_player": "additem equip getweapontype hasitemequipped addsoulgem removesoulgem hassoulgem drop getsquareroot "
                   "disableteleporting forcesneak getforcesneak forcerun getforcerun clearforcerun getstat",
    "rank": "raiserank lowerrank",
    "resurrect": "resurrect",
    "move_scale": "setscale modscale getscale moveworld move getpos getsecondspassed setangle fall",
    "water/water_ship/water_ext": "getwaterlevel setwaterlevel modwaterlevel",
    "events_death": "ondeath onknockout onmurder",
    "misc2": "setfight modfight setflee sethello setalarm modflee modresistfire modresistfrost modresistmagicka "
             "modresistparalysis modresistpoison modrestoration setmarksman modblock setalchemy setenchant modspeed modluck "
             "addspell removespell getspell setpccrimelevel getpccrimelevel pcjoinfaction pcraiserank modpcfacrep getpcrank "
             "moddisposition setdisposition getdisposition modreputation journal getjournalindex getflee getpccell "
             "getdeadcount getinterior getcommondisease payfine pcexpell pcexpelled pcclearexpelled getangle",
    "misc3": "lock getlocked unlock setpos getpos xbox scriptrunning getcurrentweather aifollow getcurrentaipackage "
             "startcombat stopcombat gettarget",
    "fail_global": "(błąd w skrypcie globalnym: brak obiektu → skrypt przerwany i zatrzymany)",
}
# zweryfikowane wcześniej sondą nowej gry na prawdziwych danych (15/15) – bez porównania funkcja po funkcji
PROBE = set("say saydone getdistance aitravel aiescort aiwander getaipackagedone messagebox getbuttonpressed enablenamemenu "
            "enableracemenu enableclassmenu enablebirthmenu enablestatreviewmenu enableinventorymenu enablemagicmenu "
            "enablemapmenu enablestatsmenu enablerest enableplayercontrols disableplayercontrols enableplayerfighting "
            "disableplayerfighting enableplayerjumping disableplayerjumping enableplayermagic disableplayermagic "
            "enableplayerviewswitch disableplayerviewswitch enablevanitymode disablevanitymode disable enable onactivate "
            "activate getitemcount unlock getstandingpc startscript stopscript getrace journal additem removeitem addtopic "
            "showmap menumode getsecondspassed getdisabled positioncell changeweather playbink fadein fadeout".split())
# częściowo zgodne: znana różnica
PARTIAL = {
    "ondeath": "flaga od razu po śmierci (OpenMW – po animacji śmierci; animacji brak); kasowanie odczytem zgodne",
    "onknockout": "powalenie bez animacji; od ciosu stałe 2 s (OpenMW – długość animacji knockdown)",
    "getlos": "linia wzroku na wysokości 1,5 m (OpenMW – wysokość oczu aktora z Bullet)",
    "getdetected": "jak getLOS; zasięg przetwarzania 7168 j. stały",
    "getpcsleep": "sen co godzinę po 1/60 s jak TimeAdvancer; brak przerywania snu stworzeniami (fSleepRandMod)",
    "wakeuppc": "jak GetPCSleep",
    "getpcinjail": "brak okna więzienia – prawda przez jedną klatkę skryptów po GoToJail",
    "gotojail": "brak okna więzienia (dni, umiejętności – od razu)",
    "becomewerewolf": "statystyki, szata, wiedza świadków i grzywna jak OpenMW; brak modelu wilkołaka, nakładki ekranu, pazurów",
    "undowerewolf": "jak BecomeWerewolf",
    "enablelevitation": "flaga zapisywana (LEVT); efekt Lewitacji nie jest jeszcze zaimplementowany",
    "disablelevitation": "jak EnableLevitation",
    "enableteleporting": "Znakowanie/Przywołanie respektują flagę; Boska/Almsivi interwencja nie istnieją (magia)",
    "disableteleporting": "jak EnableTeleporting",
    "setangle": "tylko oś Z; osie X/Y zgłaszane jako nieobsługiwane",
    "getcollidingpc": "zderzenie z ostatniego ruchu Godota (slide collisions) zamiast Bullet",
    "getcollidingactor": "jak GetCollidingPC",
    "getstandingactor": "kontakt z podłożem (normalna) zamiast Bullet",
    "hurtstandingactor": "jak GetStandingActor",
    "hurtcollidingactor": "jak GetCollidingPC",
    "getstandingpc": "jak GetStandingActor",
    "cast": "gracz: tylko wybór czaru (jak OpenMW); NPC: efekty od razu, bez AiCast/animacji",
    "explodespell": "gracz: tylko wybór czaru (jak OpenMW); NPC: efekty od razu, bez AiCast/animacji",
}
MISSING = {
    "turnmoonred": "brak księżyców na niebie (Masser/Secunda nie są renderowane) – instrukcja zgłaszana jako brakująca",
    "turnmoonwhite": "jak TurnMoonRed",
}
NOT_FUNCTION = {
    "fakeiswere": "nie funkcja: `player->fakeiswere` – OpenMW pomija odniesienie („Stray explicit reference”) i czyta "
                  "zmienną lokalną; kompilator konwertera tak samo (od tego etapu)",
}
DEPS = {
    "getpcsleep": "odpoczynek (okno)", "wakeuppc": "odpoczynek (okno)", "becomewerewolf": "statystyki, ekwipunek, AI, przestępstwa",
    "undowerewolf": "statystyki, ekwipunek", "setwerewolfacrobatics": "statystyki", "iswerewolf": "stan wilkołaka",
    "getwerewolfkills": "śmierć NPC (wilkołak)", "getdetected": "AI (wykrywanie)", "getlos": "fizyka (promień)",
    "gettarget": "AI (walka, powitanie)", "getattacked": "walka, przestępstwa (spłata)", "onknockout": "kondycja, powalenie",
    "ondeath": "śmierć aktora", "onmurder": "przestępstwa (morderstwo)", "getpcinjail": "więzienie", "getpctraveling": "podróże",
    "getpcsneaking": "skradanie", "forcesneak": "ruch aktora", "clearforcesneak": "ruch aktora", "forcerun": "ruch aktora",
    "move": "fizyka, aktorzy na obiekcie", "moveworld": "fizyka, aktorzy na obiekcie", "setscale": "przebudowa węzła",
    "getwaterlevel": "woda komórki", "setwaterlevel": "woda komórki", "modwaterlevel": "woda komórki",
    "modregion": "pogoda", "raiserank": "frakcje", "resurrect": "stan aktora, koniec gry", "face": "AI (AiFace)",
    "drop": "ekwipunek, świat", "equip": "ekwipunek", "hitonme": "walka", "placeitemcell": "świat (komórki)",
}
TESTS = {
    "test_mwscript_functions": "setstrength modstrength sethealth modcurrenthealth setresistfire getresistfire modcurrentfatigue "
        "onknockout getattacked ondeath onmurder resurrect moveworld setscale modscale getscale fall getwaterlevel "
        "setwaterlevel forcesneak getforcesneak getpcsneaking clearforcesneak drop equip hasitemequipped getweapontype "
        "hitonme hitattemptonme getsquareroot getstat disableteleporting enableteleporting becomewerewolf iswerewolf "
        "undowerewolf getpcsleep wakeuppc forcerun getforcerun getwerewolfkills",
    "test_scripts": "startscript stopscript enable disable onactivate activate journal additem getitemcount menumode",
}


_ATTR = "strength intelligence willpower agility speed endurance personality luck".split()
_SKILL = ("block armorer mediumarmor heavyarmor bluntweapon longblade axe spear athletics enchant destruction alteration "
          "illusion conjuration mysticism restoration alchemy unarmored security sneak acrobatics lightarmor shortblade "
          "marksman mercantile speechcraft handtohand").split()
_EFF = ("resistmagicka resistfire resistfrost resistshock resistdisease resistblight resistcorprus resistpoison "
        "resistparalysis resistnormalweapons waterbreathing chameleon waterwalking swimspeed superjump flying armorbonus "
        "castpenalty silence blindness paralysis invisible attackbonus defendbonus").split()


def _family(f: str) -> bool:
    for pre in ("modcurrent", "get", "set", "mod"):
        if f.startswith(pre):
            r = f[len(pre):]
            return r in _ATTR or r in _SKILL or r in _EFF or r in ("health", "magicka", "fatigue") \
                or r.endswith("getratio")
    return False


def main(argv):
    use = json.loads(Path(argv[0]).read_text(encoding="utf-8"))
    verified = {}
    for case, names in CASES.items():
        for n in names.split():
            verified.setdefault(n, []).append(case)
    tests = {}
    for t, names in TESTS.items():
        for n in names.split():
            tests.setdefault(n, []).append(t)
    rows = []
    counts = {"Zweryfikowane": 0, "Częściowo zgodne": 0, "Zaimplementowane": 0, "Brakujące": 0, "Nie funkcja": 0}
    for f in sorted(use, key=lambda k: (-use[k], k)):
        kind = SIG.get(f, ("?",))[0]
        op = {"f": "funkcja (wartość)", "i": "instrukcja"}.get(kind, "—")
        cmp_ = "zgodne: " + ", ".join(verified[f]) if f in verified else "—"
        test = ", ".join(tests.get(f, [])) or ("sonda nowej gry" if f in PROBE else "—")
        if f in NOT_FUNCTION:
            st, note = "Nie funkcja", NOT_FUNCTION[f]
        elif f in MISSING:
            st, note = "Brakujące", MISSING[f]
        elif f in PARTIAL:
            st, note = "Częściowo zgodne", PARTIAL[f]
        elif f in verified or f in PROBE:
            st, note = "Zweryfikowane", "" if f in verified else "sonda nowej gry (bez porównania funkcji osobno)"
        elif _family(f):
            st, note = "Zaimplementowane", "ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem"
        else:
            st, note = "Zaimplementowane", "nieporównane z OpenMW"
        counts[st] += 1
        rows.append(f"| `{f}` | {use[f]} | {op} | {st} | {test} | {cmp_} | {DEPS.get(f, '—')} | {note or '—'} |")
    print("| Funkcja | Skrypty | Rodzaj | Status | Test | Porównanie z OpenMW | Zależności | Znane różnice |")
    print("|---|---|---|---|---|---|---|---|")
    print("\n".join(rows))
    print()
    print("Podsumowanie: " + ", ".join(f"{k} {v}" for k, v in counts.items()) + f" (razem {len(use)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
