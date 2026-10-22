#!/usr/bin/env python3
"""Optional adapter. Create items `winmux.workspace` and `winmux.mode` first.

Run one instance: python3 sketchybar_state.py --winmuxx /path/to/winmuxx
Uses SketchyBar's documented --set interface:
https://felixkratz.github.io/SketchyBar/config/items
No shell evaluation, periodic state queries or third-party Python dependencies.
"""
import argparse
import json
import re
import subprocess
import sys
import time


def items_for_state(envelope):
    if envelope.get("schemaVersion") != 1:
        raise ValueError("unsupported WinMuxX state schema")
    state = envelope.get("state", {})
    mode = state.get("mode", {})
    runtime = state.get("runtime", {})
    enabled = runtime.get("enabled", False) and not runtime.get("suspended", False)
    active = enabled and mode.get("name") not in (None, "main")
    workspace_id = state.get("focus", {}).get("workspaceId")
    workspace = next((w for w in state.get("workspaces", []) if w.get("id") == workspace_id), {})
    color = mode.get("resolvedColor", "")
    color = "0xff" + color[1:] if re.fullmatch(r"#[0-9A-Fa-f]{6}", color or "") else "0xffffffff"
    return {
        "winmux.workspace": {"label": str(workspace.get("displayName", "—"))},
        "winmux.mode": {"label": str(mode.get("initial") or "?") if active else "",
                        "label.color": color, "drawing": "on" if active else "off"},
    }


class Adapter:
    def __init__(self, executable="sketchybar"):
        self.executable = executable
        self.instance = None
        self.revision = -1
        self.previous = {}

    def update(self, envelope):
        instance = envelope.get("instanceId")
        revision = envelope.get("revision")
        if not isinstance(instance, str) or not isinstance(revision, int):
            raise ValueError("missing state identity/revision")
        if instance == self.instance and revision <= self.revision:
            return
        desired = items_for_state(envelope)
        if instance != self.instance:
            self.previous = {}
        for item, properties in desired.items():
            if properties != self.previous.get(item):
                subprocess.run([self.executable, "--set", item] +
                               [f"{key}={value}" for key, value in properties.items()],
                               check=True, timeout=3)
        self.instance, self.revision, self.previous = instance, revision, desired


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--winmuxx", default="winmuxx")
    parser.add_argument("--sketchybar", default="sketchybar")
    args = parser.parse_args()
    adapter = Adapter(args.sketchybar)
    backoff = 0.25
    try:
        while True:
            child = None
            try:
                child = subprocess.Popen([args.winmuxx, "subscribe", "state-changed"],
                                         stdout=subprocess.PIPE, text=True)
                # A reconnect receives an initial snapshot even at the same revision.
                adapter.instance, adapter.revision, adapter.previous = None, -1, {}
                for line in child.stdout:
                    adapter.update(json.loads(line))
                    backoff = 0.25
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                print(f"winmuxx adapter: {error}", file=sys.stderr)
            finally:
                if child is not None:
                    if child.poll() is None:
                        child.terminate()
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
                    if child.stdout:
                        child.stdout.close()
            time.sleep(backoff)
            backoff = min(10, backoff * 2)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
