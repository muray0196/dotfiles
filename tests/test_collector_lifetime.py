#!/usr/bin/env python3
"""Exercise collector shutdown with real pipes and no Bluetooth or network I/O."""

from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest


WIDGETS = Path(__file__).resolve().parents[1] / "modules/quickshell/.config/quickshell"
HARNESS = r"""
import asyncio
from pathlib import Path
import sys
import types

root, kind, mode, ready, stopped = sys.argv[1:]
ready, stopped = Path(ready), Path(stopped)
if kind == "sensor":
    sys.path.insert(0, str(Path(root) / "clock/scripts"))
    import switchbot_meter as collector

    class Scanner:
        def __init__(self, callback):
            self.callback = callback

        async def __aenter__(self):
            ready.touch()
            if mode == "emitting":
                asyncio.get_running_loop().call_soon(self.callback, None, None)
            return self

        async def __aexit__(self, *args):
            stopped.touch()

    sys.modules["bleak"] = types.SimpleNamespace(BleakScanner=Scanner)
    collector.decode_advertisement = lambda *_: {
        "address": "TEST", "temperature": 20, "humidity": 40, "timestamp": 1
    }
    result = asyncio.run(collector.scan(None, False, 1))
else:
    sys.path.insert(0, str(Path(root) / "performance/scripts"))
    import remote_metrics as collector
    collector.load_config = lambda _: ("http://example.invalid", "test")
    collector.normalize = lambda value: value

    def fetch(*args):
        ready.touch()
        if mode == "silent":
            raise OSError("simulated unavailable exporter")
        return {"schema_version": 2}, None

    collector.fetch_snapshot = fetch
    result = collector.stream(Path("unused"), 0.05, 0.05, False)
    stopped.touch()
raise SystemExit(result)
"""


class CollectorLifetimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def launch(self, kind, mode, stdout=subprocess.PIPE):
        ready = self.directory / f"{kind}-{mode}.ready"
        stopped = self.directory / f"{kind}-{mode}.stopped"
        process = subprocess.Popen(
            [sys.executable, "-B", "-c", HARNESS, str(WIDGETS), kind, mode,
             str(ready), str(stopped)],
            stdout=stdout, stderr=subprocess.PIPE,
        )
        self.addCleanup(self.close_process, process)
        deadline = time.monotonic() + 3
        while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(ready.exists(), "collector did not start")
        return process, stopped

    @staticmethod
    def close_process(process):
        if process.poll() is None:
            process.kill()
        process.wait(timeout=3)
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()

    def assert_stopped(self, process, stopped):
        try:
            code = process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            raise AssertionError("collector kept running after shutdown") from None
        self.assertEqual(code, 0, process.stderr.read().decode())
        self.assertTrue(stopped.exists(), "collector skipped normal cleanup")

    def test_output_loss_stops_collectors_even_without_readings(self):
        for kind in ("sensor", "remote"):
            for mode in ("silent", "emitting"):
                with self.subTest(kind=kind, mode=mode):
                    process, stopped = self.launch(kind, mode)
                    if mode == "emitting":
                        self.assertTrue(select.select([process.stdout], [], [], 3)[0])
                        self.assertTrue(process.stdout.readline().strip())
                    process.stdout.close()
                    self.assert_stopped(process, stopped)

    def test_connected_collectors_keep_streaming_until_terminated(self):
        for kind in ("sensor", "remote"):
            with self.subTest(kind=kind):
                process, stopped = self.launch(kind, "emitting")
                self.assertTrue(select.select([process.stdout], [], [], 3)[0])
                self.assertTrue(process.stdout.readline().strip())
                time.sleep(0.1)
                self.assertIsNone(process.poll())
                process.terminate()
                self.assert_stopped(process, stopped)

    def test_regular_file_output_does_not_stop_collectors(self):
        for kind in ("sensor", "remote"):
            with self.subTest(kind=kind), (self.directory / f"{kind}.jsonl").open("wb") as output:
                process, stopped = self.launch(kind, "emitting", stdout=output)
                time.sleep(0.1)
                self.assertIsNone(process.poll())
                process.terminate()
                self.assert_stopped(process, stopped)


if __name__ == "__main__":
    unittest.main()
