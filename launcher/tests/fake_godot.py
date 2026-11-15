#!/usr/bin/env python3
"""Atrapa Godota do testów launchera: zapisuje argumenty do $FAKE_GODOT_LOG i kończy się kodem $FAKE_GODOT_EXIT."""
import json, os, sys, time
log = os.environ.get("FAKE_GODOT_LOG")
if log:
    with open(log, "a") as fh:
        fh.write(json.dumps(sys.argv[1:]) + "\n")
if "--version" in sys.argv:
    print("4.7.1.stable.fake")
    sys.exit(0)
time.sleep(float(os.environ.get("FAKE_GODOT_SLEEP", "0.3")))
print("fake godot: koniec")
sys.exit(int(os.environ.get("FAKE_GODOT_EXIT", "0")))
