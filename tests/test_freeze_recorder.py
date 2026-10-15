import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess
import uuid


MODULE_PATH = Path(__file__).resolve().parents[1] / "services/freeze-recorder/recorder.py"
spec = importlib.util.spec_from_file_location("freeze_recorder", MODULE_PATH)
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)


class FreezeRecorderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def records(self, directory):
        files = sorted(directory.glob("events.jsonl.*"), reverse=True)
        files.append(directory / "events.jsonl")
        return [json.loads(line) for path in files for line in path.read_text().splitlines()]

    def test_rotation_keeps_latest_complete_records_within_limit(self):
        sink = recorder.EventLog(self.root, max_bytes=512, files=3)
        for number in range(30):
            sink.write("sample", number=number, payload="x" * 100)
        sink.close()
        paths = list(self.root.glob("events.jsonl*"))
        self.assertEqual(len(paths), 3)
        self.assertTrue(all(p.stat().st_size <= 512 for p in paths))
        numbers = [r["number"] for r in self.records(self.root)]
        self.assertEqual(numbers, list(range(numbers[0], 30)))

    def test_runtime_logs_survive_source_loss_and_follow_new_inodes(self):
        runtime = self.root / "run"
        source = runtime / "quickshell/by-id/instance/log.log"
        source.parent.mkdir(parents=True)
        source.write_text("loaded\n")
        directory = self.root / "saved"
        sink = recorder.EventLog(directory)
        logs = recorder.RuntimeLogs(runtime, sink)
        logs.poll()
        with source.open("a") as stream:
            stream.write("clock failure\n")
        logs.poll()
        source.rename(source.with_suffix(".old"))
        source.write_text("replacement\n")
        logs.poll()
        source.write_text("short\n")
        logs.poll()
        source.unlink()
        logs.poll()
        sink.close()
        events = self.records(directory)
        self.assertEqual([r["text"] for r in events if r["event"] == "desktop_log"],
                         ["loaded\n", "clock failure\n", "replacement\n", "short\n"])
        self.assertEqual(events[-1]["event"], "log_disappeared")

    def test_restart_discards_only_incomplete_trailing_record(self):
        path = self.root / "events.jsonl"
        path.write_bytes(b'{"event":"saved"}\n{"event":"interrupted')
        sink = recorder.EventLog(self.root)
        sink.write("restarted")
        sink.close()
        self.assertEqual([r["event"] for r in self.records(self.root)], ["saved", "restarted"])

    def test_stalled_compositor_times_out_and_recovers(self):
        runtime = self.root / "run"
        lock = runtime / "hypr/instance/hyprland.lock"
        lock.parent.mkdir(parents=True)
        lock.touch()
        sink = recorder.EventLog(self.root / "saved")
        follower = recorder.HyprlandRollingLogs(runtime, sink)
        follower.command = "/mock/hyprctl"
        result = subprocess.CompletedProcess([], 0, "fresh diagnostic", "")
        with patch.object(recorder.subprocess, "run", side_effect=[
            subprocess.TimeoutExpired("hyprctl", 1), result, result
        ]) as run:
            follower.poll()
            follower.poll()
            follower.poll()
            self.assertEqual(run.call_args.kwargs["timeout"], 1)
        sink.close()
        events = self.records(self.root / "saved")
        self.assertEqual([r["status"] for r in events], ["timeout", 0])
        self.assertEqual(events[1]["text"], "fresh diagnostic")

    def test_noisy_source_records_skipped_bytes(self):
        runtime = self.root / "run"
        source = runtime / "hypr/instance/hyprland.log"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"x" * (300 * 1024))
        sink = recorder.EventLog(self.root / "saved")
        recorder.RuntimeLogs(runtime, sink).poll()
        sink.close()
        events = self.records(self.root / "saved")
        self.assertEqual(events[0]["event"], "log_gap")
        self.assertEqual(events[0]["skipped_bytes"], 44 * 1024)
        self.assertEqual(len(events[1]["text"]), 256 * 1024)

    def test_retention_preserves_current_and_unowned_directories(self):
        owned = []
        for _ in range(6):
            directory = self.root / f"boot-{uuid.uuid4()}"
            directory.mkdir()
            (directory / "owner").write_text("freeze-recorder-v1\n")
            owned.append(directory)
        unrelated = self.root / f"boot-{uuid.uuid4()}"
        unrelated.mkdir()
        (unrelated / "report.md").write_text("keep")
        recorder.prune_boots(self.root, owned[0], keep=4)
        self.assertTrue(owned[0].exists())
        self.assertEqual(sum(p.exists() for p in owned), 4)
        self.assertTrue((unrelated / "report.md").exists())

    def write_process(self, pid, start, comm="qs", state="S", ticks=10):
        directory = self.root / str(pid)
        directory.mkdir(exist_ok=True)
        # From state (field 3) through rss (field 24).
        fields = [state, "1"] + ["0"] * 20
        fields[11], fields[12] = str(ticks), "2"
        fields[17], fields[19] = "1", str(start)
        fields[20], fields[21] = "40960", "10"
        (directory / "stat").write_text(f"{pid} ({comm}) " + " ".join(fields))
        (directory / "cmdline").write_text("qs\0-c\0clock\0")
        (directory / "wchan").write_text("futex_wait")
        return directory

    def test_pid_reuse_and_disappearance_are_not_confused_with_same_process(self):
        process = self.write_process(123, 100)
        sampler = recorder.Sampler(self.root)
        first = sampler.sample()
        self.assertEqual(first["processes"][0]["label"], "qs:clock")
        self.write_process(123, 200, ticks=90)
        second = sampler.sample()
        self.assertEqual({(c["kind"], c["start_ticks"]) for c in second["process_changes"]},
                         {("appeared", 200), ("disappeared", 100)})
        self.assertEqual(second["processes"][0]["cpu_delta_ticks"], 0)
        (process / "stat").unlink()
        third = sampler.sample()
        self.assertEqual(third["process_changes"][0]["kind"], "disappeared")

    def test_proc_stat_handles_parentheses_and_unreadable_wait_channels(self):
        process = self.write_process(234, 1234, comm="worker (disk)", state="D")
        parsed = recorder.process_stat(process)
        self.assertEqual(parsed["comm"], "worker (disk)")
        self.assertEqual(parsed["state"], "D")
        self.assertEqual(parsed["start_ticks"], 1234)
        (process / "wchan").write_text("0")
        self.assertIsNone(recorder.wait_channel(process / "wchan"))
        self.assertIsNone(recorder.wait_channel(process / "missing"))


if __name__ == "__main__":
    unittest.main()
