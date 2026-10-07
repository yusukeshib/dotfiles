"""Non-mutating dots regression tests; every command uses an isolated HOME/repo.

Run with: python3 -m unittest discover -s tests -v
Set DOTS_TEST_BASH to test another Bash (default: /bin/bash).
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "bin" / "dots"
BASH = os.environ.get("DOTS_TEST_BASH", "/bin/bash")


class DotsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dots-test-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "live"
        self.repo = self.base / "repo"
        self.home.mkdir()
        (self.repo / "home").mkdir(parents=True)
        (self.repo / "bin").mkdir()
        shutil.copy2(SOURCE, self.repo / "bin/dots")
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(HOME=str(self.home), GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.repo), *args], env=self.env,
            check=True, capture_output=True, text=True,
        )

    def managed(self, rel="a", content="repository"):
        src = self.repo / "home" / rel
        src.parent.mkdir(parents=True, exist_ok=True)
        src.write_text(content)
        self.git("--literal-pathspecs", "add", "--", "home/" + rel)
        return src

    def live(self, rel="a", content="live"):
        dst = self.home / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(content)
        return dst

    def run_dots(self, *args, success=True):
        result = subprocess.run(
            [BASH, str(self.repo / "bin/dots"), *args], env=self.env,
            capture_output=True, text=True, timeout=10,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def stub(self, command, body):
        directory = self.base / "stubs"
        directory.mkdir(exist_ok=True)
        path = directory / command
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
        self.env["PATH"] = str(directory) + ":" + os.environ["PATH"]

    def fail_install_mv(self):
        real_mv = shutil.which("mv")
        self.stub("mv", f'case "$1" in */link|*/copy) exit 23;; esac\nexec "{real_mv}" "$@"')

    def backups(self, rel="a"):
        return list(self.home.glob(rel + ".predots-*/original"))

    def test_link_and_status_and_idempotence(self):
        src = self.managed()
        self.run_dots("link")
        self.assertEqual((self.home / "a").readlink(), src)
        self.run_dots("link")
        self.run_dots("status")
        self.assertEqual(self.backups(), [])

    def test_dry_run_does_not_change_live_content(self):
        self.managed(); dst = self.live()
        self.run_dots("link", "--dry-run")
        self.assertFalse(dst.is_symlink())
        self.assertEqual(dst.read_text(), "live")
        self.assertEqual(self.backups(), [])

    def test_link_preserves_drift(self):
        self.managed(); self.live()
        self.run_dots("link")
        self.assertEqual([p.read_text() for p in self.backups()], ["live"])

    def test_link_preserves_directory_conflict(self):
        self.managed(); self.live("a/secret", "keep")
        self.run_dots("link")
        self.assertEqual((self.backups()[0] / "secret").read_text(), "keep")

    def test_link_replaces_wrong_symlink_to_directory(self):
        src = self.managed(); other = self.base / "other"; other.mkdir()
        (self.home / "a").symlink_to(other)
        self.run_dots("link")
        self.assertEqual((self.home / "a").readlink(), src)
        self.assertEqual(list(other.iterdir()), [])
        self.assertEqual(self.backups()[0].readlink(), other)

    def test_repeated_backups_preserve_all_versions(self):
        self.managed(); self.live(content="first")
        self.stub("date", "printf fixed")
        self.run_dots("link")
        (self.home / "a").unlink(); self.live(content="second")
        self.run_dots("link")
        self.assertEqual(sorted(p.read_text() for p in self.backups()), ["first", "second"])

    def test_relink_automatic(self):
        src = self.managed(); self.live()
        self.run_dots("relink")
        self.assertEqual(src.read_text(), "live")
        self.assertTrue((self.home / "a").is_symlink())

    def test_relink_explicit_absolute(self):
        src = self.managed(); dst = self.live()
        self.run_dots("relink", str(dst))
        self.assertEqual(src.read_text(), "live")

    def test_relink_no_drift(self):
        self.managed(); self.run_dots("link"); self.run_dots("relink")

    def test_relink_ln_failure_keeps_both_originals(self):
        src = self.managed(); dst = self.live()
        self.stub("ln", "exit 23")
        self.run_dots("relink", "a", success=False)
        self.assertEqual(dst.read_text(), "live")
        self.assertEqual(src.read_text(), "repository")
        self.assertFalse(dst.is_symlink())

    def test_relink_mv_failure_restores_both_originals(self):
        src = self.managed(); dst = self.live()
        self.fail_install_mv()
        self.run_dots("relink", "a", success=False)
        self.assertEqual(dst.read_text(), "live")
        self.assertEqual(src.read_text(), "repository")

    def test_link_ln_failure_keeps_live_file(self):
        self.managed(); dst = self.live()
        self.stub("ln", "exit 23")
        self.run_dots("link", success=False)
        self.assertEqual(dst.read_text(), "live")

    def test_link_mv_failure_restores_live_file(self):
        self.managed(); dst = self.live()
        self.fail_install_mv()
        self.run_dots("link", success=False)
        self.assertEqual(dst.read_text(), "live")

    def test_adopt_fresh_file_stages_it(self):
        dst = self.live("nested/a")
        self.run_dots("adopt", str(dst))
        self.assertTrue(dst.is_symlink())
        self.assertEqual(dst.read_text(), "live")
        self.git("ls-files", "--error-unmatch", "home/nested/a")

    def test_adopt_existing_repo_file_is_rejected(self):
        src = self.managed(); dst = self.live()
        self.run_dots("adopt", "a", success=False)
        self.assertEqual(src.read_text(), "repository")
        self.assertEqual(dst.read_text(), "live")
        self.assertFalse(dst.is_symlink())

    def test_adopt_directory_is_rejected(self):
        secret = self.live("directory/secret")
        self.run_dots("adopt", "directory", success=False)
        self.assertEqual(secret.read_text(), "live")
        self.assertFalse((self.repo / "home/directory").exists())

    def test_traversal_is_rejected_for_all_mutations(self):
        victim = self.base / "victim"; victim.write_text("outside")
        for command in ("adopt", "relink", "unlink"):
            with self.subTest(command=command):
                self.run_dots(command, "../victim", success=False)
                self.assertFalse(victim.is_symlink())
                self.assertEqual(victim.read_text(), "outside")

    def test_absolute_outside_home_is_rejected(self):
        victim = self.base / "victim"; victim.write_text("outside")
        self.run_dots("adopt", str(victim), success=False)
        self.assertFalse(victim.is_symlink())

    def test_symlink_parent_is_rejected(self):
        outside = self.base / "outside"; outside.mkdir(); (outside / "a").write_text("outside")
        (self.home / "alias").symlink_to(outside)
        self.run_dots("adopt", "alias/a", success=False)
        self.assertFalse((outside / "a").is_symlink())

    def test_adopt_ln_failure_restores_live_file(self):
        dst = self.live(); self.stub("ln", "exit 23")
        self.run_dots("adopt", "a", success=False)
        self.assertEqual(dst.read_text(), "live")
        self.assertFalse((self.repo / "home/a").exists())

    def test_adopt_ignored_file_is_rejected(self):
        (self.repo / ".gitignore").write_text("home/a\n")
        dst = self.live()
        self.run_dots("adopt", "a", success=False)
        self.assertFalse(dst.is_symlink())
        self.assertEqual(dst.read_text(), "live")

    def test_unlink_creates_independent_copy(self):
        src = self.managed(); self.run_dots("link")
        self.run_dots("unlink", "a")
        dst = self.home / "a"
        self.assertFalse(dst.is_symlink())
        dst.write_text("changed")
        self.assertEqual(src.read_text(), "repository")

    def test_unlink_mv_failure_restores_symlink(self):
        src = self.managed(); self.run_dots("link")
        self.fail_install_mv()
        self.run_dots("unlink", "a", success=False)
        self.assertEqual((self.home / "a").readlink(), src)

    def test_unmanaged_unlink_is_rejected(self):
        target = self.base / "target"; target.write_text("outside")
        dst = self.home / "a"; dst.symlink_to(target)
        self.run_dots("unlink", "a", success=False)
        self.assertEqual(dst.readlink(), target)

    def test_unmanaged_relink_is_rejected(self):
        dst = self.live()
        self.run_dots("relink", "a", success=False)
        self.assertEqual(dst.read_text(), "live")
        self.assertFalse((self.repo / "home/a").exists())

    def test_missing_source_is_not_reported_healthy(self):
        src = self.managed(); self.run_dots("link"); src.unlink()
        self.run_dots("status", success=False)
        self.run_dots("link", success=False)

    def test_special_filenames(self):
        for rel in ("space name", "日本語", "line\nbreak", "trailing\n", ":(glob)*"):
            self.managed(rel)
        self.run_dots("link")
        self.run_dots("status")
        for rel in ("space name", "日本語", "line\nbreak", "trailing\n", ":(glob)*"):
            self.run_dots("unlink", rel)
            (self.home / rel).write_text("live")
        self.run_dots("relink")
        self.run_dots("status")

    def test_failed_git_enumeration_stops_before_mutation(self):
        self.managed(); dst = self.live()
        real_git = shutil.which("git")
        self.stub("git", f'case " $* " in *" ls-files "*) exit 23;; esac\nexec "{real_git}" "$@"')
        self.run_dots("link", success=False)
        self.run_dots("status", success=False)
        self.assertEqual(dst.read_text(), "live")
        self.assertFalse(dst.is_symlink())

    def test_missing_git_repository_is_rejected(self):
        self.managed(); shutil.rmtree(self.repo / ".git")
        self.run_dots("status", success=False)

    def test_adopt_missing_managed_source_is_rejected(self):
        src = self.managed(); src.unlink(); dst = self.live()
        self.run_dots("adopt", "a", success=False)
        self.assertFalse(dst.is_symlink())
        self.assertFalse(src.exists())

    def test_relink_copy_failure_keeps_originals(self):
        src = self.managed(); dst = self.live(); self.stub("cp", "exit 23")
        self.run_dots("relink", "a", success=False)
        self.assertEqual(src.read_text(), "repository")
        self.assertEqual(dst.read_text(), "live")

    def test_unlink_copy_failure_keeps_symlink(self):
        src = self.managed(); self.run_dots("link"); self.stub("cp", "exit 23")
        self.run_dots("unlink", "a", success=False)
        self.assertEqual((self.home / "a").readlink(), src)

    def test_adopt_git_add_failure_restores_live_file(self):
        dst = self.live(); real_git = shutil.which("git")
        self.stub("git", f'case " $* " in *" add "*) exit 23;; esac\nexec "{real_git}" "$@"')
        self.run_dots("adopt", "a", success=False)
        self.assertFalse(dst.is_symlink())
        self.assertEqual(dst.read_text(), "live")
        self.assertFalse((self.repo / "home/a").exists())

    def test_relink_and_unlink_preserve_file_mode(self):
        src = self.managed(); dst = self.live(); dst.chmod(0o700)
        self.run_dots("relink", "a")
        self.assertEqual(src.stat().st_mode & 0o777, 0o700)
        self.run_dots("unlink", "a")
        self.assertEqual(dst.stat().st_mode & 0o777, 0o700)

    def test_bad_arguments_are_rejected(self):
        for args in (("link", "--typo"), ("status", "extra"), ("adopt",), ("unlink",), ("adopt", "a", "b")):
            with self.subTest(args=args):
                self.run_dots(*args, success=False)


if __name__ == "__main__":
    unittest.main()
