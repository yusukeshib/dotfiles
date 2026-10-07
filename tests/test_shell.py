"""Isolated tests for shell helpers; never source the full user startup config."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INIT = (ROOT / "home/.config/zsh/init.zsh").read_text()
CACHE_FUNCTION = "_cached_eval() {" + INIT.split("_cached_eval() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
UTILS = ROOT / "home/.config/zsh/utils.zsh"


class ShellTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-shell-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / "bin"; self.bin.mkdir()
        self.cache = self.home / "cache"; self.cache.mkdir()
        self.env = {
            "HOME": str(self.home), "PATH": str(self.bin) + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "ZSH_CACHE_DIR": str(self.cache), "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Test", "GIT_COMMITTER_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid", "GIT_COMMITTER_EMAIL": "test@example.invalid",
        }

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n"); path.chmod(0o755)
        return path

    def zsh(self, script):
        return subprocess.run(["/bin/zsh", "-df", "-c", script], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def cached(self, arg="arg"):
        return self.zsh(CACHE_FUNCTION + "\n_cached_eval example producer " + shlex.quote(arg) + '\nrc=$?\nprint -r -- "$result"\nexit $rc')

    def test_cache_hit_does_not_regenerate(self):
        self.stub("producer", 'echo hit >> "$HOME/count"\nprintf "typeset -g result=one\\n"')
        for _ in range(2):
            result = self.cached(); self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "one")
        self.assertEqual((self.home / "count").read_text().splitlines(), ["hit"])

    def test_cache_invalidates_older_relinked_producer(self):
        one = self.stub("one", 'printf "typeset -g result=one\\n"')
        two = self.stub("two", 'printf "typeset -g result=two\\n"')
        producer = self.bin / "producer"; producer.symlink_to(one)
        self.assertEqual(self.cached().stdout.strip(), "one")
        os.utime(two, (946684800, 946684800))
        producer.unlink(); producer.symlink_to(two)
        result = self.cached()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "two")

    def test_cache_invalidates_changed_arguments(self):
        self.stub("producer", 'printf "typeset -g result=%s\\n" "$1"')
        self.assertEqual(self.cached("one").stdout.strip(), "one")
        result = self.cached("two")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "two")

    def test_cache_failure_does_not_publish_partial_script(self):
        self.stub("producer", 'if [ "$1" = fail ]; then echo broken; exit 1; fi\nprintf "typeset -g result=one\\n"')
        self.assertEqual(self.cached().returncode, 0)
        previous = (self.cache / "example.zsh").read_bytes()
        self.assertNotEqual(self.cached("fail").returncode, 0)
        self.assertEqual((self.cache / "example.zsh").read_bytes(), previous)
        self.assertEqual(self.cached().stdout.strip(), "one")

    def gunwip(self, subject):
        self.stub("git", 'if [ "$1" = rev-list ]; then printf "%s\\n" "$SUBJECT"; else printf "%s\\n" "$*" > "$HOME/reset"; fi')
        self.env["SUBJECT"] = subject
        alias = next(line for line in INIT.splitlines() if line.startswith("alias gunwip="))
        return self.zsh(alias + "\neval gunwip")

    def test_gunwip_recognizes_marker(self):
        result = self.gunwip("--wip-- [skip ci]")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "reset").read_text().strip(), "reset HEAD~1")

    def test_gunwip_does_not_reset_other_commits(self):
        self.gunwip("normal change")
        self.assertFalse((self.home / "reset").exists())

    def docker(self, inspect_body):
        self.stub("docker", 'case "$1" in\nps) printf "first\\nsecond\\n";;\ninspect) printf "%s\\n" "$@" > "$HOME/inspect-args"; ' + inspect_body + ';;\ncommit) printf "%s\\n" "$*" > "$HOME/commit";;\nesac')
        return self.zsh("source " + shlex.quote(str(UTILS)) + "\nupdate-mydev-image")

    def test_docker_inspect_error_is_reported(self):
        result = self.docker('echo "permission denied" >&2; exit 7')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docker inspect failed: permission denied", result.stderr)
        self.assertFalse((self.home / "commit").exists())

    def test_docker_empty_entrypoint_is_supported(self):
        result = self.docker('printf "first \\nsecond bash\\n"')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.home / "inspect-args").read_text().splitlines()
        self.assertIn("{{if .Config.Entrypoint}}", args[2])
        self.assertEqual(args[-2:], ["first", "second"])
        self.assertEqual((self.home / "commit").read_text().strip(), "commit second mydev:latest")

    def test_docker_no_matching_container_does_not_commit(self):
        result = self.docker('printf "first sh\\nsecond \\n"')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "commit").exists())

    def test_highlighting_loads_after_integrations(self):
        plugins = (ROOT / "home/.config/zsh/plugins.zsh").read_text()
        self.assertNotIn("_load_plugin zsh-users/zsh-syntax-highlighting", plugins)
        self.assertTrue(INIT.rstrip().endswith("_load_plugin zsh-users/zsh-syntax-highlighting"))


if __name__ == "__main__":
    unittest.main()
