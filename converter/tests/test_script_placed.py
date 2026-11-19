"""Obiekty stawiane przez skrypty (PlaceAtPC/PlaceAtMe/PlaceItem/PlaceItemCell) trafiają do eksportu (objects.json,
modele) także bez referencji w przekonwertowanych komórkach – z rozwinięciem list LEVC/LEVI."""
from types import SimpleNamespace

from mwconv.pipeline import _script_placed


def _call(name, oid):
    return ["call", None, name, [["str", oid], ["num", 1.0], ["num", 128.0], ["num", 1.0]]]


def test_script_placed_objects_and_leveled_lists():
    world = SimpleNamespace(
        records={"SCPT": {"q1": {"body": [["if", ["bin", "==", ["num", 1], ["num", 1]], [_call("PlaceAtPC", "Dremora_Lord")]]]},
                          "q2": {"body": [_call("placeitemcell", "lev_item"), _call("placeatme", "lev_crea"),
                                          ["call", None, "additem", [["str", "only_added"], ["num", 1]]],
                                          _call("placeatpc", "missing_record")]}},
                 "LEVC": {"lev_crea": {"items": [{"id": "rat"}, {"id": "lev_crea"}]}},
                 "LEVI": {"lev_item": {"items": [{"id": "misc_x"}]}}},
        objects={"dremora_lord": {}, "rat": {}, "misc_x": {}, "only_added": {}})
    assert _script_placed(world) == {"dremora_lord", "rat", "misc_x"}
