#!/usr/bin/env python3
"""Measure matched native settings-window idle scenarios; never touches installed apps."""
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time

ROOT = Path("~/Documents/MultiShift/macos-ui-audit")
USAGE = "<TMP>/multi-ui-audit-usage"


def main():
    baseline = Path("<TMP>/multi-ui-before-idle-switcher/MultiSwitcher.app")
    if not baseline.exists():
        shutil.copytree("<TMP>/multi-ui-baseline-switcher-final/MultiSwitcher.app", baseline)
        shutil.copy2("<TMP>/multi-ui-baseline-switcher-final/swiftpm/arm64-apple-macosx/release/MultiSwitcher",
                     baseline / "Contents/MacOS/MultiSwitcher")
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(baseline)], check=True)
    targets = {
        "before-multishift": "<TMP>/multi-ui-baseline-shift/MultiShift.app/Contents/MacOS/MultiShift",
        "after-multishift": "<TMP>/multi-ui-reviewed-shift/MultiShift.app/Contents/MacOS/MultiShift",
        "before-multiswitcher": str(baseline / "Contents/MacOS/MultiSwitcher"),
        "after-multiswitcher": "<TMP>/multi-ui-review-switcher/MultiSwitcher.app/Contents/MacOS/MultiSwitcher",
    }
    processes, logs = {}, []
    raw = []
    try:
        for name, binary in targets.items():
            data_root = ROOT / "runtime" / ("idle-" + name)
            data_root.mkdir(parents=True, exist_ok=True)
            log = (ROOT / "logs" / ("idle-" + name + ".log")).open("w")
            logs.append(log)
            environment = os.environ | {"MULTI_ECOSYSTEM_REVIEW": str(data_root), "MULTI_ECOSYSTEM_INTERACTIVE": "1"}
            processes[name] = subprocess.Popen([binary], env=environment, stdout=log, stderr=subprocess.STDOUT)
        time.sleep(8)
        start = time.monotonic()
        for sample in range(121):
            rows = subprocess.check_output([USAGE, *[str(p.pid) for p in processes.values()]], text=True)
            counters = [json.loads(line) for line in rows.splitlines()]
            elapsed = time.monotonic() - start
            for (name, _), counter in zip(processes.items(), counters):
                raw.append({"name": name, "elapsed_s": elapsed, **counter})
            if sample < 120:
                time.sleep(max(0, start + sample + 1 - time.monotonic()))
        summaries = {}
        for name in targets:
            samples = [row for row in raw if row["name"] == name]
            first, last = samples[0], samples[-1]
            elapsed = last["elapsed_s"] - first["elapsed_s"]
            cpu = []
            for a, b in zip(samples, samples[1:]):
                cpu.append(((b["user_ns"] + b["system_ns"]) - (a["user_ns"] + a["system_ns"])) / 1e9 / (b["elapsed_s"] - a["elapsed_s"]) * 100)
            summaries[name] = {"duration_s": elapsed, "samples": len(samples),
                "cpu_one_core_mean_pct": statistics.mean(cpu), "cpu_one_core_p95_pct": sorted(cpu)[int(len(cpu) * .95)],
                "rss_start_bytes": first["rss_bytes"], "rss_end_bytes": last["rss_bytes"],
                "rss_max_bytes": max(x["rss_bytes"] for x in samples),
                "idle_wakeups_per_s": (last["idle_wakeups"] - first["idle_wakeups"]) / elapsed,
                "interrupt_wakeups_per_s": (last["interrupt_wakeups"] - first["interrupt_wakeups"]) / elapsed}
        (ROOT / "performance-idle.json").write_text(json.dumps({
            "scenario": "native settings open, no interaction, visual-review mode (input monitoring excluded)",
            "binary_paths": targets, "warmup_s": 8, "counter_source": "proc_pid_rusage RUSAGE_INFO_V4",
            "baseline_instrumentation": "Switcher baseline adds only an interactive-window hold hook",
            "summary": summaries, "samples": raw}, indent=2) + "\n")
        print(json.dumps(summaries, indent=2))
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
