"""Exercise the real release gate using isolated fake build/network tools."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "Scripts" / "preflight.sh"

class PreflightTests(unittest.TestCase):
    def run_gate(self, mode, *args):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            desktop = root / "desktop"
            (desktop / "Scripts").mkdir(parents=True)
            (root / "backend").mkdir()
            shutil.copy(SCRIPT, desktop / "Scripts" / "preflight.sh")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            def executable(path, text):
                path.write_text("#!/bin/bash\n" + text)
                path.chmod(0o755)
            executable(bin_dir / "swift", '''echo "$1" >> "$CALL_LOG"
if [ "$1" = test ] && [ "$MODE" = test_failure ]; then echo "compiler crashed"; exit 1; fi
if [ "$1" = build ] && [ "$MODE" = build_failure ]; then exit 2; fi
exit 0
''')
            executable(bin_dir / "curl", 'exit 0\n')
            executable(bin_dir / "arch", 'echo test-session > "${@: -1}"\n')
            (desktop / ".build/debug").mkdir(parents=True)
            executable(desktop / ".build/debug/voiceledger-devtool", '''if [ "$1" = facts ]; then echo '{}' > "${@: -1}"; exit 0; fi
if [ "$MODE" = diff_failure ]; then exit 1; fi
exit 0
''')
            (desktop / "Regression").mkdir()
            baseline = desktop / "Regression/test-2026-07.json"
            if mode != "missing_baseline": baseline.write_text('{}')
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", MODE=mode,
                       CALL_LOG=str(root / "calls"), VL_REGRESSION_REALM="test", VL_REGRESSION_PERIODS="2026-07")
            result = subprocess.run(["bash", str(desktop / "Scripts/preflight.sh"), *args], env=env, capture_output=True, text=True)
            return result.returncode, (root / "calls").read_text().splitlines(), baseline.exists()

    def test_tests_run_once_and_fail_closed_without_failure_glyph(self):
        code, calls, _ = self.run_gate("test_failure")
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, ["test"])

    def test_build_failure_without_error_text_fails_closed(self):
        self.assertNotEqual(self.run_gate("build_failure")[0], 0)

    def test_missing_baseline_requires_explicit_acceptance(self):
        code, _, exists = self.run_gate("missing_baseline")
        self.assertNotEqual(code, 0)
        self.assertFalse(exists)
        self.assertEqual(self.run_gate("missing_baseline", "--accept-baseline")[0], 0)

    def test_diff_failure_is_not_silently_accepted(self):
        self.assertNotEqual(self.run_gate("diff_failure")[0], 0)

    def test_success_runs_tests_once(self):
        code, calls, _ = self.run_gate("success")
        self.assertEqual(code, 0)
        self.assertEqual(calls, ["test", "build"])

if __name__ == "__main__": unittest.main()
