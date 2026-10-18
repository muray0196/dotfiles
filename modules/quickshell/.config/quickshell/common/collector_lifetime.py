"""Stop continuous collectors when the widget closes their output pipe."""

import os
import select
import signal
import stat
import sys
import threading


def stop_on_stdout_close() -> None:
    """Call after installing SIGTERM handling; regular file output is unchanged."""
    stdout = sys.stdout.fileno()
    if not stat.S_ISFIFO(os.fstat(stdout).st_mode):
        return
    descriptor = os.dup(stdout)

    def watch() -> None:
        try:
            poller = select.poll()
            poller.register(descriptor, select.POLLERR | select.POLLHUP)
            # Block in the kernel, including while the sensor/exporter is silent.
            poller.poll()
            os.kill(os.getpid(), signal.SIGTERM)
        finally:
            os.close(descriptor)

    threading.Thread(target=watch, name="collector-output", daemon=True).start()
