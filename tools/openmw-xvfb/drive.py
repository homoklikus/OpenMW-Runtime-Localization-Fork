"""Sterowanie programem na ekranie X (np. OpenMW na Xvfb) przez rozszerzenie XTest i zrzuty ekranu (ImageMagick
`import`). Kroki: sleep:S, key:NAZWA (keysym X, np. Escape, Return, a), click:X,Y, type:TEKST, shot:NAZWA.
Wymaga python-xlib. Zrzuty zawierają obraz gry – trzymaj je lokalnie, poza repozytorium."""

import os
import subprocess
import sys
import time

from Xlib import X, XK, display
from Xlib.ext import xtest


def main(argv):
    disp = display.Display(os.environ["DISPLAY"])
    out = argv[0]
    os.makedirs(out, exist_ok=True)
    t0 = time.time()

    def key(name):
        kc = disp.keysym_to_keycode(XK.string_to_keysym(name))
        xtest.fake_input(disp, X.KeyPress, kc)
        disp.sync()
        time.sleep(0.05)
        xtest.fake_input(disp, X.KeyRelease, kc)
        disp.sync()

    def click(x, y):
        xtest.fake_input(disp, X.MotionNotify, x=x, y=y)
        disp.sync()
        time.sleep(0.2)
        xtest.fake_input(disp, X.ButtonPress, 1)
        disp.sync()
        time.sleep(0.08)
        xtest.fake_input(disp, X.ButtonRelease, 1)
        disp.sync()

    for step in argv[1:]:
        kind, _, arg = step.partition(":")
        if kind == "sleep":
            time.sleep(float(arg))
        elif kind == "key":
            key(arg)
        elif kind == "click":
            click(*map(int, arg.split(",")))
        elif kind == "type":
            for ch in arg:
                key("space" if ch == " " else ch)
        elif kind == "shot":
            subprocess.run(["import", "-display", os.environ["DISPLAY"], "-window", "root",
                            os.path.join(out, arg + ".png")], check=False)
            print("zrzut", arg, round(time.time() - t0, 1), flush=True)
        else:
            raise SystemExit(f"nieznany krok: {step}")


if __name__ == "__main__":
    main(sys.argv[1:])
