"""Logika launchera bez Qt (testowalna): stan instalacji, profil, mody, plan konwersji, walidacja „Graj”,
polecenia procesów. Cała praca na danych jest delegowana do `mwcore`."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from mwcore import conversion, install, launch, mods
from mwcore.activity import Activity
from mwcore.jsonio import read_json
from mwcore.paths import AppPaths
from mwcore.profiles import Profile, ProfileStore
from mwcore.settings import LauncherConfig

from .bootstrap import APP_ROOT


@dataclass
class Check:
    ok: bool
    problems: list = field(default_factory=list)   # [(kod, komunikat)]
    action: str = ""                                # "convert" | "settings" | "mods" | ""


class LauncherCore:
    def __init__(self, paths: AppPaths | None = None):
        self.paths = (paths or AppPaths.detect(APP_ROOT)).ensure()
        self.config = LauncherConfig.load(self.paths.launcher_config)
        self.profiles = ProfileStore(self.paths)
        self.mods = mods.ModStore(self.paths)
        self.activity = Activity(self.paths.state / "activity.jsonl")
        self._install_report: install.InstallReport | None = None
        self._base_files: set | None = None
        if self.profiles.get(self.config["active_profile"]) is None:
            self.config["active_profile"] = self.profiles.list()[0].id
            self.config.save()

    # --- instalacja ----------------------------------------------------------------------------
    def install_report(self, refresh: bool = False) -> install.InstallReport | None:
        inst = self.config["install"]
        if not inst:
            return None
        if self._install_report is None or refresh or self._install_report.path != inst.get("path"):
            self._install_report = install.inspect(inst["path"])
            self._base_files = None
        return self._install_report

    def set_install(self, path: str) -> install.InstallReport:
        r = install.inspect(path)
        if r.ok:
            prev = (self.config["install"] or {}).get("path")
            if prev != r.path:
                self.activity.add("ok", f"Wykryto instalację Morrowinda ({' + '.join(c['name'] for c in r.components if c['esm'])})")
            self.config["install"] = {"kind": r.kind, "path": r.path}
            self.config.save()
            self._install_report = r
            self._base_files = None
        return r

    # --- profil i mody -------------------------------------------------------------------------
    @property
    def profile(self) -> Profile:
        return self.profiles.get(self.config["active_profile"]) or self.profiles.list()[0]

    def set_active_profile(self, pid: str) -> None:
        if self.profiles.get(pid) is None:
            raise KeyError(pid)
        self.config["active_profile"] = pid
        self.config.save()

    def base_files(self) -> set:
        """Pliki danych instalacji bazowej (do wykrywania konfliktów) – liczone raz na sesję."""
        if self._base_files is None:
            rep = self.install_report()
            self._base_files = set()
            if rep and rep.config:
                from mwconv.vfs import Vfs
                try:
                    self._base_files = set(Vfs.from_install(rep.config.data_dirs, rep.config.archives).files)
                except Exception:  # noqa: BLE001
                    self._base_files = set()
        return self._base_files

    def resolution(self, with_conflicts: bool = False) -> mods.Resolution | None:
        rep = self.install_report()
        if rep is None or rep.config is None:
            return None
        return mods.resolve(rep.config, self.profile.enabled_mods(), self.mods,
                            self.base_files() if with_conflicts else None)

    # --- konwersja -----------------------------------------------------------------------------
    @property
    def converted_dir(self) -> Path:
        return self.resolve_converted(self.config["converted_dir"])

    def resolve_converted(self, text: str | None) -> Path:
        """Ścieżka katalogu przekonwertowanych danych. Puste → domyślny katalog XDG; nazwa względna
        (np. „Balmora”) → podkatalog katalogu danych użytkownika, nigdy względem bieżącego katalogu."""
        if not text or not str(text).strip():
            return self.paths.default_converted
        p = Path(str(text).strip()).expanduser()
        return p if p.is_absolute() else self.paths.data / p

    def check_converted(self, text: str | None) -> tuple[Path, str | None]:
        """(ścieżka, błąd). Przekonwertowane dane zawierają zasoby gry – nie mogą trafić do repozytorium
        projektu ani do katalogu instalacji gry."""
        p = self.resolve_converted(text).resolve()
        repo = conversion.converter_dir().parent.resolve()
        if p == repo or repo in p.parents:
            return p, (f"Katalog {p} leży w katalogu projektu ({repo}). Przekonwertowane dane zawierają zasoby "
                       "gry i nie mogą trafić do repozytorium – wybierz katalog poza projektem.")
        inst = self.config["install"].get("path") if isinstance(self.config["install"], dict) else None
        if inst:
            ip = Path(inst).expanduser().resolve()
            if p == ip or ip in p.parents:
                return p, f"Katalog {p} leży w instalacji gry ({ip}) – wybierz inny, gra musi zostać nietknięta."
        return p, None

    def plan(self) -> conversion.Plan | None:
        res = self.resolution()
        rep = self.install_report()
        if res is None or rep is None:
            return None
        return conversion.make_plan(self.converted_dir, self.paths.profile_data(self.profile.id), rep.config, res)

    def conversion_steps(self, scope: str | None = None) -> list[dict]:
        plan = self.plan()
        if plan is None:
            return []
        godot = launch.find_godot(self.config["godot_path"], APP_ROOT) if self.config["bake"] else None
        project = launch.find_project(self.config["project_dir"], APP_ROOT)
        return conversion.steps(plan, scope or self.config["conversion_scope"],
                                bake_godot=godot or "", bake_project=str(project) if (godot and project) else "",
                                flora=self.config["flora"])

    def status(self) -> conversion.OutStatus:
        plan = self.plan()
        if plan is None:
            return conversion.OutStatus(conversion.MISSING, "", ["nie wskazano instalacji Morrowinda"])
        return conversion.play_status(plan)

    def converter_cwd(self) -> Path:
        return conversion.converter_dir()

    def python(self) -> str:
        return conversion.python_exe(self.config["python_path"])

    # --- „Graj” i edytor ------------------------------------------------------------------------
    def godot(self) -> str | None:
        return launch.find_godot(self.config["godot_path"], APP_ROOT)

    def project_dir(self) -> Path | None:
        return launch.find_project(self.config["project_dir"], APP_ROOT)

    def check_play(self, conversion_running: bool = False) -> Check:
        probs = []
        action = ""
        rep = self.install_report()
        if rep is None or not rep.ok:
            return Check(False, [("install", "Nie wskazano poprawnej instalacji Morrowinda.")], "convert")
        if conversion_running:
            return Check(False, [("running", "Trwa konwersja – poczekaj na jej zakończenie albo ją przerwij.")], "convert")
        res = self.resolution()
        if res.missing_mods:
            probs.append(("profile", "Profil odwołuje się do nieistniejących modów: " + ", ".join(res.missing_mods)))
            action = "mods"
        for mm in res.missing_masters:
            probs.append(("deps", f"{mm['plugin']} ({mm['mod']}) wymaga: {', '.join(mm['missing'])}"))
            action = "mods"
        st = self.status()
        msg = {conversion.MISSING: "Brak przekonwertowanych danych gry. Uruchom konwersję.",
               conversion.INCOMPLETE: "Konwersja jest niekompletna (przerwana?). Wznów ją albo napraw.",
               conversion.RUNNING: "Trwa konwersja (inny proces).",
               conversion.OUTDATED: "Dane wymagają aktualizacji: " + "; ".join(st.details),
               conversion.BROKEN: "Uszkodzone dane konwersji: " + "; ".join(st.details) + ". Użyj „Napraw”."}
        if st.state != conversion.READY:
            probs.append(("conversion", msg.get(st.state, st.state)))
            action = action or "convert"
        if self.godot() is None:
            probs.append(("godot", "Nie znaleziono Godota 4 (ustaw ścieżkę w Ustawieniach → Zaawansowane)."))
            action = action or "settings"
        if self.project_dir() is None:
            probs.append(("project", "Nie znaleziono projektu gry (project.godot)."))
            action = action or "settings"
        return Check(not probs, probs, action)

    def game_languages(self) -> list[str]:
        """Języki tłumaczeń w bieżącej konwersji (world/localization/index.json profilu lub bazy)."""
        plan = self.plan()
        if plan is None:
            return []
        for out in (plan.play_out, plan.base_out):
            j = read_json(Path(out) / "world" / "localization" / "index.json", None)
            if isinstance(j, dict):
                return [str(x) for x in j.get("languages", [])]
        return []

    def runtime_args(self, extra_user: list[str] | None = None) -> list[str]:
        plan = self.plan()
        p = self.profile
        pdata = self.paths.profile_data(p.id)
        settings = launch.write_runtime_settings(pdata / "runtime_settings.json", p.settings, p.id,
                                                 self.config["language"])
        saves = self.paths.saves(p.id)
        saves.mkdir(parents=True, exist_ok=True)
        project = pdata / "project"
        project.mkdir(parents=True, exist_ok=True)
        return launch.user_args(plan.play_out, plan.base_out, project, settings, p.id, saves, extra_user)

    def game_command(self, extra_user: list[str] | None = None) -> list[str]:
        return launch.game_command(self.godot(), self.project_dir(), self.runtime_args(extra_user),
                                   self.config["launch_args"])

    def editor_command(self, extra_user: list[str] | None = None) -> list[str]:
        return launch.editor_command(self.godot(), self.project_dir(), self.runtime_args(extra_user),
                                     self.config["launch_args"])

    def lock(self, kind: str) -> launch.InstanceLock:
        return launch.InstanceLock(self.paths.locks, kind, self.profile.id)
