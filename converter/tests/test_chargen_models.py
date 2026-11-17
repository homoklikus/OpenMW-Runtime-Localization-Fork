"""Tworzenie postaci: konwersja części ciała wszystkich grywalnych ras (okno rasy, postać gracza po wyborze),
nie tylko ras NPC z wybranych komórek."""

from types import SimpleNamespace

from mwconv.pipeline import _actor_models


class _Vfs:
    def resolve_mesh(self, m):
        return "meshes/" + m.lower().replace("\\", "/")

    def exists(self, k):
        return False


def test_playable_race_parts_included():
    ref = SimpleNamespace(ref=SimpleNamespace(base="villager"))
    world = SimpleNamespace(
        cells={"c": SimpleNamespace(refs={"r1": ref})},
        records={
            "NPC_": {"villager": {"race": "Dark Elf", "head": "b_de_head", "hair": "b_de_hair"}},
            "RACE": {"dark elf": {"playable": True}, "orc": {"playable": True}, "dremora": {"playable": False}},
            "BODY": {
                "b_de_head": {"race": "Dark Elf", "model": "b\\de_head.nif", "mesh_type": 0},
                "b_de_hair": {"race": "Dark Elf", "model": "b\\de_hair.nif", "mesh_type": 0},
                "b_orc_head": {"race": "Orc", "model": "b\\orc_head.nif", "mesh_type": 0},
                "b_orc_hair": {"race": "Orc", "model": "b\\orc_hair.nif", "mesh_type": 0},
                "b_dremora": {"race": "Dremora", "model": "b\\dremora.nif", "mesh_type": 0},
                "a_orc_armor": {"race": "Orc", "model": "a\\orc_armor.nif", "mesh_type": 2},
            },
        })
    out = _actor_models(world, ["c"], _Vfs())
    assert {"meshes/b/orc_head.nif", "meshes/b/orc_hair.nif", "meshes/b/de_head.nif"} <= out
    assert "meshes/b/dremora.nif" not in out and "meshes/a/orc_armor.nif" not in out


def test_no_actors_no_race_parts():
    world = SimpleNamespace(cells={"c": SimpleNamespace(refs={})},
                            records={"NPC_": {}, "RACE": {"orc": {"playable": True}},
                                     "BODY": {"b_orc_head": {"race": "Orc", "model": "b\\orc_head.nif", "mesh_type": 0}}})
    assert _actor_models(world, ["c"], _Vfs()) == set()
