"""herdr/config.toml: every custom key binding is unique (#2461).

`herdr config check` validates syntax but not key collisions, so a duplicate
`key =` would silently shadow another binding.
"""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[2] / "herdr/config.toml"


def test_herdr_key_bindings_are_unique() -> None:
    keys = re.findall(r'^key\s*=\s*"([^"]+)"', CONFIG.read_text(encoding="utf-8"), re.M)
    assert "prefix+ctrl+s" in keys
    dupes = [k for k, n in Counter(keys).items() if n > 1]
    assert dupes == []
