import sys

from .bootstrap import ensure_paths

ensure_paths()
from .app import main  # noqa: E402

sys.exit(main())
