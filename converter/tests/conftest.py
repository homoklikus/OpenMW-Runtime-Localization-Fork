import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


@pytest.fixture(scope="session")
def synth_data(tmp_path_factory):
    from mwconv.synthetic_world import write_world
    d = tmp_path_factory.mktemp("synth") / "Data Files"
    info = write_world(d)
    info["dir"] = d
    return info
