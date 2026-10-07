"""Bounded fixtures for executable examples and workflow gates in skills.

This does not evaluate whether a model will follow the skill instructions.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class SkillTests(unittest.TestCase):
    def test_staged_only_change_cannot_pass_committed_diff_gates(self):
        with tempfile.TemporaryDirectory(prefix="skill-git-") as tmp:
            env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
            env.update(HOME=tmp, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1",
                       GIT_AUTHOR_NAME="Test", GIT_COMMITTER_NAME="Test",
                       GIT_AUTHOR_EMAIL="test@example.invalid", GIT_COMMITTER_EMAIL="test@example.invalid")

            def git(*args, check=True):
                return subprocess.run(["git", "-C", tmp, *args], env=env, check=check,
                                      capture_output=True, text=True, timeout=10)

            git("init", "-q", "-b", "main")
            git("commit", "-qm", "base", "--allow-empty")
            git("checkout", "-qb", "feature")
            (Path(tmp) / "formatted.txt").write_text("already formatted\n")
            git("add", "formatted.txt")
            self.assertEqual(git("diff", "--cached", "--quiet", check=False).returncode, 1)
            self.assertEqual(git("diff", "--quiet", "main...HEAD", check=False).returncode, 0)
            git("commit", "-qm", "test: commit intended change")
            self.assertEqual(git("diff", "--cached", "--quiet", check=False).returncode, 0)
            self.assertEqual(git("diff", "--quiet", "main...HEAD", check=False).returncode, 1)
            self.assertEqual(git("diff", "--name-only", "main...HEAD").stdout.strip(), "formatted.txt")


if __name__ == "__main__":
    unittest.main()
