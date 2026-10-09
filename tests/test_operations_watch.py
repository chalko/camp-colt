#!/usr/bin/env python3
"""
tests/test_operations_watch.py
Comprehensive Verification Suite for commands/operations_watch.sh

Validates:
1. Deterministic Bash + JQ Execution (Zero-LLM footprint, single .sh file).
2. Multi-Rig JSON Queries (city, gascity, suitcase-ai) and Active Session Mapping.
3. Operations Watch Summary Markdown Generation (.gc/runtime/watch/operations_watch_summary.md).
4. State Ledger & Stagnation Detection Engine:
   - 1-2 Stagnant Intervals (15-30m): Targeted session nudge to worker/assignee.
   - 4 Stagnant Intervals (>=60m): [P1 ESCALATION] to Chief of Staff (cos).
   - CoS Zero-Noise Invariant: Zero mail to CoS on normal progress (< 4 stalls).
5. Automated Failure Escalation Trap:
   - Dual-alerts s6-signal and s3-operations on failure.
   - Subject formatted as: '[P1] ALERT: operations_watch.sh Execution Failure (Line $LINENO, Code $EXIT_CODE)'
   - Stamps bead priority with P1 ('bd update <id> -p P1').
   - Dispatches with '--notify'.
"""

import unittest
import os
import sys
import json
import tempfile
import shutil
import datetime
import subprocess

SCRIPT_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "commands", "operations_watch.sh"))


class TestOperationsWatchScript(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="ops_watch_test_")
        self.bin_dir = os.path.join(self.test_dir, "bin")
        os.makedirs(self.bin_dir, exist_ok=True)
        self.mock_log = os.path.join(self.test_dir, "mock_calls.log")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _setup_mock_gc(self, inbox_data=None, sessions_data=None, city_beads=None, gascity_beads=None, suitcase_beads=None, convoys_data=None, mail_send_id="msg-ops-err-01"):
        inbox_file = os.path.join(self.test_dir, "inbox.json")
        with open(inbox_file, "w") as f:
            json.dump(inbox_data or {"messages": []}, f)

        sessions_file = os.path.join(self.test_dir, "sessions.json")
        with open(sessions_file, "w") as f:
            json.dump(sessions_data or {"sessions": []}, f)

        convoys_file = os.path.join(self.test_dir, "convoys.json")
        with open(convoys_file, "w") as f:
            json.dump(convoys_data or {"convoys": []}, f)

        city_file = os.path.join(self.test_dir, "city_beads.json")
        with open(city_file, "w") as f:
            json.dump(city_beads or [], f)

        gascity_file = os.path.join(self.test_dir, "gascity_beads.json")
        with open(gascity_file, "w") as f:
            json.dump(gascity_beads or [], f)

        suitcase_file = os.path.join(self.test_dir, "suitcase_beads.json")
        with open(suitcase_file, "w") as f:
            json.dump(suitcase_beads or [], f)

        mock_gc = os.path.join(self.bin_dir, "gc")
        with open(mock_gc, "w") as f:
            f.write(f"""#!/bin/sh
echo "GC_CALL: $*" >> "{self.mock_log}"
if [ "$1" = "mail" ] && [ "$2" = "inbox" ]; then
    cat "{inbox_file}"
    exit 0
fi
if [ "$1" = "session" ] && [ "$2" = "list" ]; then
    cat "{sessions_file}"
    exit 0
fi
if [ "$1" = "convoy" ] && [ "$2" = "list" ]; then
    cat "{convoys_file}"
    exit 0
fi
if [ "$1" = "session" ] && [ "$2" = "nudge" ]; then
    echo "NUDGED: $*" >> "{self.mock_log}"
    exit 0
fi
if [ "$1" = "mail" ] && [ "$2" = "send" ]; then
    echo "MAIL_SENT: $*" >> "{self.mock_log}"
    echo '{{"id":"{mail_send_id}","ok":true}}'
    exit 0
fi
if [ "$1" = "bd" ] && [ "$2" = "update" ]; then
    echo "BD_UPDATE: $*" >> "{self.mock_log}"
    exit 0
fi
if [ "$1" = "bd" ]; then
    if [ "$2" = "--rig" ] && [ "$3" = "gascity" ]; then
        cat "{gascity_file}"
        exit 0
    elif [ "$2" = "--rig" ] && [ "$3" = "suitcase-ai" ]; then
        cat "{suitcase_file}"
        exit 0
    else
        cat "{city_file}"
        exit 0
    fi
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
        """Assert commands/operations_watch.sh exists, is executable, with zero companion py file."""
        self.assertTrue(os.path.exists(SCRIPT_PATH), "commands/operations_watch.sh must exist")
        self.assertTrue(os.access(SCRIPT_PATH, os.X_OK), "commands/operations_watch.sh must be executable")
        py_companion = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "commands", "operations_watch.py"))
        self.assertFalse(os.path.exists(py_companion), "commands/operations_watch.py must NOT exist; single .sh file required")

    def test_multi_rig_query_and_summary_output(self):
        """Assert multi-rig beads are queried and formatted into operations_watch_summary.md."""
        sessions = {
            "sessions": [
                {"id": "session-s3", "alias": "s3-operations", "state": "active", "closed": False}
            ]
        }
        city_beads = [
            {"id": "cc-task-1", "title": "City Task", "status": "in_progress", "issue_type": "task", "assignee": "s3-operations", "updated_at": "2026-10-09T04:00:00Z"}
        ]
        gascity_beads = [
            {"id": "gcs-task-2", "title": "GasCity Task", "status": "open", "issue_type": "feature", "assignee": "s6-signal", "updated_at": "2026-10-09T04:00:00Z"}
        ]
        suitcase_beads = [
            {"id": "sa-task-3", "title": "Suitcase Task", "status": "in_progress", "issue_type": "task", "assignee": "colt-sysadmin", "updated_at": "2026-10-09T04:00:00Z"}
        ]

        self._setup_mock_gc(sessions_data=sessions, city_beads=city_beads, gascity_beads=gascity_beads, suitcase_beads=suitcase_beads)
        res = self._run_script()
        self.assertEqual(res.returncode, 0, f"Script failed: {res.stderr}")

        summary_file = os.path.join(self.test_dir, ".gc", "runtime", "watch", "operations_watch_summary.md")
        self.assertTrue(os.path.exists(summary_file), "Summary markdown file must be created")

        with open(summary_file, "r") as f:
            summary = f.read()

        self.assertIn("Camp Colt Operations Watch Summary", summary)
        self.assertIn("Active Workstreams Tracked**: 3", summary)
        self.assertIn("`cc-task-1`", summary)
        self.assertIn("`gcs-task-2`", summary)
        self.assertIn("`sa-task-3`", summary)

        with open(self.mock_log, "r") as f:
            logs = f.read()

        # Officer review trigger nudge to s3-operations
        self.assertIn("NUDGED: session nudge s3-operations Operations Watch Patrol tick", logs)

    def test_stagnation_detection_and_cos_zero_noise(self):
        """
        Assert Stagnation Engine:
        - Ticks 1-2: targeted session nudge to worker/assignee.
        - Ticks 1-3: Zero mail to CoS (CoS Zero-Noise Invariant).
        - Tick 4: [P1 ESCALATION] sent to Chief of Staff (cos).
        """
        sessions = {
            "sessions": [
                {"id": "session-worker-01", "alias": "polecat-01", "state": "active", "closed": False},
                {"id": "session-s3", "alias": "s3-operations", "state": "active", "closed": False}
            ]
        }
        stagnant_bead = [
            {
                "id": "gcs-slow-01",
                "title": "Slow Task",
                "status": "in_progress",
                "issue_type": "task",
                "assignee": "polecat-01",
                "updated_at": "2026-10-09T04:00:00Z"
            }
        ]

        self._setup_mock_gc(sessions_data=sessions, gascity_beads=stagnant_bead)

        # Tick 1: First observation -> stagnant_ticks = 0 (Normal progress)
        res1 = self._run_script()
        self.assertEqual(res1.returncode, 0)
        with open(self.mock_log, "r") as f:
            log1 = f.read()
        self.assertNotIn("session nudge session-worker-01", log1)
        self.assertNotIn("mail send cos", log1)

        # Tick 2: Unchanged in_progress -> stagnant_ticks = 1 (15m). Nudge worker session.
        os.remove(self.mock_log)
        res2 = self._run_script()
        self.assertEqual(res2.returncode, 0)
        with open(self.mock_log, "r") as f:
            log2 = f.read()
        self.assertIn("session nudge session-worker-01", log2)
        # CoS Zero-Noise Invariant
        self.assertNotIn("mail send cos", log2)

        # Tick 3: Unchanged in_progress -> stagnant_ticks = 2 (30m). Nudge worker session.
        os.remove(self.mock_log)
        res3 = self._run_script()
        self.assertEqual(res3.returncode, 0)
        with open(self.mock_log, "r") as f:
            log3 = f.read()
        self.assertIn("session nudge session-worker-01", log3)
        # CoS Zero-Noise Invariant
        self.assertNotIn("mail send cos", log3)

        # Tick 4: Unchanged in_progress -> stagnant_ticks = 3 (45m).
        os.remove(self.mock_log)
        res4 = self._run_script()
        self.assertEqual(res4.returncode, 0)
        with open(self.mock_log, "r") as f:
            log4 = f.read()
        # CoS Zero-Noise Invariant still holds
        self.assertNotIn("mail send cos", log4)

        # Tick 5: Unchanged in_progress -> stagnant_ticks = 4 (>=60m). CRITICAL STAGNATION.
        os.remove(self.mock_log)
        res5 = self._run_script()
        self.assertEqual(res5.returncode, 0)
        with open(self.mock_log, "r") as f:
            log5 = f.read()

        # CoS Escalation triggered!
        self.assertIn("mail send cos --notify", log5)
        self.assertIn("[P1 ESCALATION] Workstream Stagnation: gcs-slow-01", log5)
        self.assertIn("bd update msg-ops-err-01 -p P1", log5)

    def test_automated_failure_trap(self):
        """
        Verify Automated Failure Trap (ERR):
        - On unhandled non-zero exit, dual-alerts s6-signal and s3-operations.
        - Formats subject line '[P1] ALERT: operations_watch.sh Execution Failure (Line $LINENO, Code $EXIT_CODE)'.
        - Stamps bead priority with P1.
        """
        self._setup_mock_gc(mail_send_id="msg-trap-99")

        res = self._run_script(extra_args=["--invalid-argument-triggers-trap"])
        self.assertNotEqual(res.returncode, 0, "Script must exit non-zero on failure")

        with open(self.mock_log, "r") as f:
            logs = f.read()

        # Dual alerts:
        self.assertIn("mail send s6-signal --notify", logs)
        self.assertIn("mail send s3-operations --notify", logs)
        self.assertIn("[P1] ALERT: operations_watch.sh Execution Failure", logs)
        self.assertIn("bd update msg-trap-99 -p P1", logs)

    def test_convoy_tracking_and_stagnation_escalation(self):
        """
        Verify Convoy & OPORD Tracking:
        - Active convoys and child beads are rendered into operations_watch_summary.md.
        - Convoy without progress over 4 ticks triggers [P1 ESCALATION] to CoS.
        """
        sessions = {
            "sessions": [
                {"id": "session-s3", "alias": "s3-operations", "state": "active", "closed": False},
                {"id": "session-worker", "alias": "worker-01", "template": "gascity/gc.run-operator", "state": "active", "closed": False}
            ]
        }
        convoys = {
            "convoys": [
                {
                    "id": "gcs-convoy-01",
                    "title": "Priority Campaign OPORD",
                    "status": "open",
                    "progress": {"closed": 0, "total": 2},
                    "fields": {"owner": "s3-operations"},
                    "child_ids": ["gcs-lead-01"]
                }
            ]
        }
        gascity_beads = [
            {
                "id": "gcs-lead-01",
                "title": "Lead Task",
                "status": "in_progress",
                "issue_type": "feature",
                "assignee": "worker-01",
                "updated_at": "2026-10-09T04:00:00Z"
            }
        ]

        self._setup_mock_gc(sessions_data=sessions, convoys_data=convoys, gascity_beads=gascity_beads)

        # Tick 1: Initial observation
        res1 = self._run_script()
        self.assertEqual(res1.returncode, 0)
        summary_file = os.path.join(self.test_dir, ".gc", "runtime", "watch", "operations_watch_summary.md")
        with open(summary_file, "r") as f:
            summary = f.read()
        self.assertIn("## Active Convoys & OPORDs", summary)
        self.assertIn("`gcs-convoy-01`", summary)
        self.assertIn("Priority Campaign OPORD", summary)
        self.assertIn("## Active Tactical Workers", summary)
        self.assertIn("`session-worker`", summary)

        # Ticks 2-4: unchanged
        for _ in range(3):
            os.remove(self.mock_log)
            res = self._run_script()
            self.assertEqual(res.returncode, 0)

        # Tick 5: 4 stagnant intervals -> CoS Escalation
        os.remove(self.mock_log)
        res5 = self._run_script()
        self.assertEqual(res5.returncode, 0)
        with open(self.mock_log, "r") as f:
            log5 = f.read()

        self.assertIn("mail send cos --notify", log5)
        self.assertIn("[P1 ESCALATION] Convoy Stagnation: gcs-convoy-01", log5)


if __name__ == "__main__":
    unittest.main()
