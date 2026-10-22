import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sketchybar_state", Path(__file__).parent / "examples/sketchybar_state.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


def fixture(instance="one", revision=1):
    return {"schemaVersion": 1, "instanceId": instance, "revision": revision, "state": {
        "mode": {"name": "leader", "initial": "L", "resolvedColor": "#5E9EFF"},
        "runtime": {"enabled": True, "suspended": False},
        "focus": {"workspaceId": "workspace-1"},
        "workspaces": [{"id": "workspace-1", "displayName": "Work $(whoami) `x`"}]}}


class SketchybarStateTest(unittest.TestCase):
    @patch.object(adapter.subprocess, "run")
    def test_initial_repeat_stale_and_restart(self, run):
        client = adapter.Adapter()
        client.update(fixture())
        self.assertEqual(run.call_count, 2)
        self.assertIn("label=Work $(whoami) `x`", run.call_args_list[0].args[0])
        self.assertNotIn("shell", run.call_args_list[0].kwargs)
        client.update(fixture())
        client.update(fixture(revision=0))
        client.update(fixture(revision=2))
        self.assertEqual(run.call_count, 2)
        client.update(fixture(instance="two", revision=0))
        self.assertEqual(run.call_count, 4)

    def test_unknown_fields_missing_focus_and_suspend(self):
        event = fixture()
        event["extra"] = "ignored"
        event["state"]["runtime"]["suspended"] = True
        event["state"]["focus"] = {}
        items = adapter.items_for_state(event)
        self.assertEqual(items["winmux.mode"]["drawing"], "off")
        self.assertEqual(items["winmux.workspace"]["label"], "—")
        event["schemaVersion"] = 2
        with self.assertRaises(ValueError):
            adapter.items_for_state(event)

    @patch.object(adapter.subprocess, "run", side_effect=OSError("unavailable"))
    def test_failed_render_does_not_advance_revision(self, run):
        client = adapter.Adapter()
        with self.assertRaises(OSError):
            client.update(fixture())
        self.assertEqual(client.revision, -1)
