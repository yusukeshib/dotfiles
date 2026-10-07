"""Read-only syntax/parse checks for tracked configs, with isolated HOME/XDG.

Run: python3 tests/check_configs.py
Requires Python 3.11+, bash, zsh, ruby, node, installed pi (jiti), and nvim.
These checks do not establish external plugin/API/schema compatibility.
"""

from collections import Counter
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def main():
    files = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"]).decode().split("\0")
    counts = Counter()
    lua_files = []
    ts_files = []
    with tempfile.TemporaryDirectory(prefix="dotfiles-config-check-") as tmp:
        env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "NVIM_"))}
        env.update(HOME=tmp, ZDOTDIR=tmp, XDG_CONFIG_HOME=tmp + "/config",
                   XDG_DATA_HOME=tmp + "/data", XDG_STATE_HOME=tmp + "/state",
                   XDG_CACHE_HOME=tmp + "/cache", GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")

        def check(command, path):
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=15)
            if result.returncode:
                # Avoid dumping configuration contents into logs on parser errors.
                raise RuntimeError(f"{command[0]} validation failed: {path}")

        for rel in filter(None, files):
            path = ROOT / rel
            suffix = path.suffix
            if suffix == ".json":
                json.loads(path.read_text()); counts["JSON"] += 1
            elif suffix == ".toml":
                tomllib.loads(path.read_text()); counts["TOML"] += 1
            elif suffix == ".plist":
                plistlib.loads(path.read_bytes()); counts["plist"] += 1
            elif suffix == ".lua":
                lua_files.append(str(path))
            elif suffix == ".ts":
                ts_files.append(str(path))
            elif suffix == ".zsh" or path.name in (".zshenv", ".zshrc"):
                check(["/bin/zsh", "-n", str(path)], rel); counts["zsh syntax"] += 1
            elif suffix == ".sh" or rel == "bin/dots":
                interpreter = "/bin/sh" if path.read_text().startswith("#!/bin/sh\n") else "/bin/bash"
                check([interpreter, "-n", str(path)], rel); counts["shell syntax"] += 1
            elif path.name == "Brewfile":
                check(["ruby", "-c", str(path)], rel); counts["Ruby syntax"] += 1
            elif rel in ("home/.gitconfig", "home/.config/git/gitconfig_darwin"):
                check(["git", "config", "--file", str(path), "--list"], rel); counts["Git config"] += 1
        if ts_files:
            check(["node", str(ROOT / "tests/jiti.cjs"), *ts_files], "TypeScript configs")
            counts["TypeScript syntax"] = len(ts_files)
        if lua_files:
            nvim = shutil.which("nvim")
            if nvim is None:
                raise RuntimeError("nvim is required for Lua syntax checks")
            script = Path(tmp) / "syntax.lua"
            script.write_text("local paths = vim.json.decode([==[" + json.dumps(lua_files) + "]==])\n"
                              "for _, path in ipairs(paths) do assert(loadfile(path)) end\n")
            check([nvim, "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)], "Lua configs")
            counts["Lua syntax"] = len(lua_files)
    for kind, count in sorted(counts.items()):
        print(f"PASS {kind}: {count}")
    print(f"PASS total checks: {sum(counts.values())}; no runtime/schema validation implied")


if __name__ == "__main__":
    main()
