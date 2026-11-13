#!/usr/bin/env python3
"""Run each loading case in its own Dart process with time/RSS budgets.

RSS is sampled from the OS every 200 ms; it measures the whole process, not GPU
memory. The Dart result also includes the VM's process peak RSS. A budget stop
is recorded with the last available progress metrics and is not a completed run.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


def rss_bytes(process_id):
    result = subprocess.run(
        ["ps", "-o", "rss=", "-p", str(process_id)],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    return int(value) * 1024 if value else 0


def run_case(arguments, repository, lines, mode):
    command = [
        arguments.dart,
        str(repository / "tool/loading_benchmark.dart"),
        "--lines",
        str(lines),
        "--mode",
        mode,
        "--batch-size",
        str(arguments.batch_size),
    ]
    started = time.monotonic()
    peak_rss = 0
    stopped_for = None
    with tempfile.TemporaryDirectory(prefix="gcode_run_") as run_directory:
        stdout_path = Path(run_directory) / "stdout.jsonl"
        stderr_path = Path(run_directory) / "stderr.txt"
        environment = dict(os.environ, TMPDIR=run_directory)
        with stdout_path.open("w") as stdout, stderr_path.open("w") as stderr:
            process = subprocess.Popen(
                command,
                cwd=repository,
                env=environment,
                stdout=stdout,
                stderr=stderr,
                start_new_session=True,
            )
            try:
                while process.poll() is None:
                    peak_rss = max(peak_rss, rss_bytes(process.pid))
                    if peak_rss > arguments.rss_limit_mb * 1024 * 1024:
                        stopped_for = "memory_limit"
                    elif time.monotonic() - started > arguments.timeout_seconds:
                        stopped_for = "timeout"
                    if stopped_for:
                        break
                    time.sleep(0.2)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                process.wait()

        records = []
        for line in stdout_path.read_text().splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        final = records[-1] if records else {}
        status = stopped_for or final.get("status", "error")
        if status == "progress" or (process.returncode != 0 and not stopped_for):
            status = "error"
        result = {
            **final,
            "status": status,
            "mode": mode,
            "requestedLines": lines,
            "completed": status == "pass" and process.returncode == 0,
            "exitCode": process.returncode,
            "wallElapsedMs": (time.monotonic() - started) * 1000,
            "externallyObservedPeakRssBytes": peak_rss,
            "rssSampleIntervalMs": 200,
            "timeoutSeconds": arguments.timeout_seconds,
            "rssLimitBytes": arguments.rss_limit_mb * 1024 * 1024,
        }
        errors = stderr_path.read_text().strip()
        if errors:
            result["stderrTail"] = errors[-2000:]
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default=shutil.which("dart"))
    parser.add_argument("--lines", nargs="+", type=int, default=[10000, 100000, 1000000])
    parser.add_argument(
        "--modes",
        nargs="+",
        choices=["timing-only", "direct-snapshot", "background-snapshot"],
        default=["timing-only", "direct-snapshot", "background-snapshot"],
    )
    parser.add_argument("--batch-size", type=int, default=200)
    parser.add_argument("--timeout-seconds", type=float, default=60)
    parser.add_argument("--rss-limit-mb", type=int, default=1536)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    if not arguments.dart:
        parser.error("Dart executable not found; pass --dart")
    if (any(lines <= 0 for lines in arguments.lines)
            or arguments.batch_size <= 0
            or arguments.timeout_seconds <= 0
            or arguments.rss_limit_mb <= 0):
        parser.error("Line counts, batch size and resource budgets must be positive")
    repository = Path(__file__).resolve().parents[1]
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("w") as output:
        for lines in arguments.lines:
            for mode in arguments.modes:
                result = run_case(arguments, repository, lines, mode)
                record = json.dumps(result, separators=(",", ":"))
                output.write(record + "\n")
                output.flush()
                print(record, flush=True)


if __name__ == "__main__":
    main()
