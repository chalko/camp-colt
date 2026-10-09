#!/usr/bin/env python3
"""
tests/test_signal_mail_watch.py
Comprehensive Verification Suite for commands/signal_mail_watch.sh

Validates:
1. Deterministic Bash + JQ Execution (Zero-LLM footprint, single .sh file).
2. Graduated Priority Thresholds & Detection:
   - P0: >0m (immediate)
   - P1: >15m
   - P2: >1h
   - P3: >8h
   - P4: >24h
3. State Ledger & Cooldown Idempotency (prevents duplicate nudges within 15m).
4. Offline Recipient Safety (gracefully skips nudging offline targets).
5. Automated Failure Escalation Trap (Command Directive cc-wisp-0yzzy):
   - Subject formatted as: '[P1] ALERT: signal_mail_watch.sh Execution Failure (Line $LINENO, Code $EXIT_CODE)'
   - Stamps bead priority with P1 ('bd update <id> -p P1')
   - Dispatches with '--notify' to s6-signal.
"""

import unittest
import os
import sys
import json
import tempfile
import shutil
import datetime
import subprocess

SCRIPT_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "commands", "signal_mail_watch.sh"))


class TestSignalMailWatchScript(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="watch_test_")
        self.bin_dir = os.path.join(self.test_dir, "bin")
        os.makedirs(self.bin_dir, exist_ok=True)
        self.mock_log = os.path.join(self.test_dir, "mock_calls.log")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _setup_mock_gc(self, sessions_data, beads_data, mail_send_id="msg-err-42"):
        """Create a mock gc binary in bin_dir."""
        sessions_file = os.path.join(self.test_dir, "sessions.json")
        with open(sessions_file, "w") as f:
            json.dump(sessions_data, f)

        beads_file = os.path.join(self.test_dir, "beads.json")
        with open(beads_file, "w") as f:
            json.dump(beads_data, f)

        mock_gc = os.path.join(self.bin_dir, "gc")
        with open(mock_gc, "w") as f:
            f.write(f"""#!/bin/sh
echo "GC_CALL: $*" >> "{self.mock_log}"
if [ "$1" = "session" ] && [ "$2" = "list" ]; then
    cat "{sessions_file}"
    exit 0
fi
if [ "$1" = "bd" ] && [ "$2" = "list" ]; then
    cat "{beads_file}"
    exit 0
fi
if [ "$1" = "session" ] && [ "$2" = "nudge" ]; then
    echo "NUDGED: $*" >> "{self.mock_log}"
    exit 0
fi
if [ "$1" = "mail" ] && [ "$2" = "send" ]; then
    echo '{{"id":"{mail_send_id}","ok":true}}'
    exit 0
fi
if [ "$1" = "bd" ] && [ "$2" = "update" ]; then
    exit 0
fi
exit 0
""")
        os.chmod(mock_gc, 0o755)

    def _run_script(self, extra_args=None, extra_env=None):
        env = os.environ.copy()
        env["PATH"] = f"{self.bin_dir}:{env.get('PATH', '')}"
        env["GC_CITY"] = self.test_dir
        if extra_env:
            env.update(extra_env)

        cmd = [SCRIPT_PATH]
        if extra_args:
            cmd.extend(extra_args)

        return subprocess.run(cmd, env=env, capture_output=True, text=True)

    def test_single_file_integrity(self):
        """Assert only signal_mail_watch.sh exists (no companion .py file)."""
        py_companion = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "commands", "signal_mail_watch.py"))
        self.assertFalse(os.path.exists(py_companion), "commands/signal_mail_watch.py must NOT exist; single .sh file required")
        self.assertTrue(os.path.exists(SCRIPT_PATH), "commands/signal_mail_watch.sh must exist")
        self.assertTrue(os.access(SCRIPT_PATH, os.X_OK), "commands/signal_mail_watch.sh must be executable")

    def test_threshold_gating_and_priority_detection(self):
        """Assert P0-P4 graduated thresholds and priority detection."""
        now = datetime.datetime.now(datetime.timezone.utc)

        def make_bead(bead_id, priority, title, age_seconds, assignee="mayor"):
            created = now - datetime.timedelta(seconds=age_seconds)
            return {
                "id": bead_id,
                "title": title,
                "assignee": assignee,
                "sender": "cos",
                "priority": priority,
                "created_at": created.strftime("%Y-%m-%dT%H:%M:%SZ"),
            }

        # P0: Age 15 seconds -> Breached
        p0_bead = make_bead("msg-p0", 0, "Urgent task", 15)
        # P1: Age 10 minutes (600s) -> Not breached (< 900s)
        p1_young = make_bead("msg-p1-young", 1, "Review", 600)
        # P1: Age 16 minutes (960s) -> Breached (>= 900s)
        p1_old = make_bead("msg-p1-old", 1, "Review", 960)
        # P2: Age 50 minutes (3000s) -> Not breached (< 3600s)
        p2_young = make_bead("msg-p2-young", 2, "Status", 3000)
        # P2: Age 65 minutes (3900s) -> Breached (>= 3600s)
        p2_old = make_bead("msg-p2-old", 2, "Status", 3900)
        # P3: Age 7 hours -> Not breached (< 8h)
        p3_young = make_bead("msg-p3-young", None, "[P3] Backlog ticket with word priority", 7 * 3600)
        # P3: Age 9 hours -> Breached (>= 8h)
        p3_old = make_bead("msg-p3-old", None, "[P3] Backlog ticket with word priority", 9 * 3600)
        # P4: Age 20 hours -> Not breached (< 24h)
        p4_young = make_bead("msg-p4-young", None, "[P4] Informational FYI", 20 * 3600)
        # P4: Age 25 hours -> Breached (>= 24h)
        p4_old = make_bead("msg-p4-old", None, "[P4] Informational FYI", 25 * 3600)

        beads = [
            p0_bead,
            p1_young, p1_old,
            p2_young, p2_old,
            p3_young, p3_old,
            p4_young, p4_old
        ]

        sessions = {
            "sessions": [
                {"id": "session-mayor-01", "alias": "mayor", "state": "active", "closed": False}
            ]
        }

        self._setup_mock_gc(sessions, beads)
        res = self._run_script()
        self.assertEqual(res.returncode, 0, f"Script failed: {res.stderr}")

        with open(self.mock_log, "r") as f:
            logs = f.read()

        # Exactly the 5 breached beads must have been nudged:
        # msg-p0, msg-p1-old, msg-p2-old, msg-p3-old, msg-p4-old
        self.assertIn("msg-p0", logs)
        self.assertIn("msg-p1-old", logs)
        self.assertIn("msg-p2-old", logs)
        self.assertIn("msg-p3-old", logs)
        self.assertIn("msg-p4-old", logs)

        # Unbreached beads must NOT have been nudged:
        self.assertNotIn("msg-p1-young", logs)
        self.assertNotIn("msg-p2-young", logs)
        self.assertNotIn("msg-p3-young", logs)
        self.assertNotIn("msg-p4-young", logs)

    def test_cooldown_and_idempotency(self):
        """Assert nudges are not sent repeatedly within the 15-minute cooldown window."""
        now = datetime.datetime.now(datetime.timezone.utc)
        bead = {
            "id": "msg-breached-test",
            "title": "Breached task",
            "assignee": "mayor",
            "sender": "cos",
            "priority": 0,
            "created_at": (now - datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        sessions = {
            "sessions": [
                {"id": "session-mayor-01", "alias": "mayor", "state": "active", "closed": False}
            ]
        }

        self._setup_mock_gc(sessions, [bead])

        # Run 1: Nudge should fire
        res1 = self._run_script()
        self.assertEqual(res1.returncode, 0)
        with open(self.mock_log, "r") as f:
            log1 = f.read()
        self.assertIn("NUDGED: session nudge session-mayor-01", log1)

        # Clear log and run immediately again: Cooldown should prevent second nudge
        os.remove(self.mock_log)
        res2 = self._run_script()
        self.assertEqual(res2.returncode, 0)
        with open(self.mock_log, "r") as f:
            log2 = f.read()
        self.assertNotIn("NUDGED:", log2)

        # Simulate cooldown expiration by setting last_nudged to 16 minutes ago in state ledger
        ledger_path = os.path.join(self.test_dir, ".gc", "runtime", "watch", "signal_mail_watch_state.json")
        with open(ledger_path, "r") as f:
            state = json.load(f)
        state["nudges"]["msg-breached-test"] = int((now - datetime.timedelta(minutes=16)).timestamp())
        with open(ledger_path, "w") as f:
            json.dump(state, f)

        # Run 3: Nudge should fire again after cooldown
        os.remove(self.mock_log)
        res3 = self._run_script()
        self.assertEqual(res3.returncode, 0)
        with open(self.mock_log, "r") as f:
            log3 = f.read()
        self.assertIn("NUDGED: session nudge session-mayor-01", log3)

    def test_offline_recipient_safe(self):
        """Assert offline recipient does not cause failure or crash."""
        now = datetime.datetime.now(datetime.timezone.utc)
        bead = {
            "id": "msg-offline-worker",
            "title": "Offline task",
            "assignee": "offline-worker",
            "sender": "cos",
            "priority": 0,
            "created_at": (now - datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        sessions = {
            "sessions": [
                {"id": "session-mayor-01", "alias": "mayor", "state": "active", "closed": False}
            ]
        }
        self._setup_mock_gc(sessions, [bead])
        res = self._run_script()
        self.assertEqual(res.returncode, 0)
        with open(self.mock_log, "r") as f:
            logs = f.read()
        self.assertNotIn("NUDGED:", logs)

    def test_error_trap_and_p1_alert(self):
        """
        Verify Command Directive cc-wisp-0yzzy:
        When commands/signal_mail_watch.sh traps an execution failure:
        1. Subject line formatting: '[P1] ALERT: signal_mail_watch.sh Execution Failure (Line $LINENO, Code $EXIT_CODE)'
        2. Bead Priority stamped with P1: 'bd update <id> -p P1'
        3. Dispatched with '--notify' to s6-signal.
        """
        sessions = {"sessions": []}
        beads = []
        self._setup_mock_gc(sessions, beads, mail_send_id="msg-watch-failure-99")

        # Force a failure in the script by passing an invalid argument
        res = self._run_script(extra_args=["--invalid-flag-that-fails-execution"])
        self.assertNotEqual(res.returncode, 0, "Script should exit non-zero on failure")

        with open(self.mock_log, "r") as f:
            logs = f.read()

        # Directive verification:
        self.assertIn("mail send s6-signal", logs)
        self.assertIn("--notify", logs)
        self.assertIn("[P1] ALERT: signal_mail_watch.sh Execution Failure", logs)
        self.assertIn("bd update msg-watch-failure-99 -p P1", logs)


if __name__ == "__main__":
    unittest.main()
