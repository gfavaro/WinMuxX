import copy
import tempfile
import unittest
from pathlib import Path
from script.install_fork import APP, Installer, NativeOperations, SessionLocked


class Operations:
    def __init__(self):
        self.calls = []
        self.fail = None
        self.is_locked = False
        self.installed = {'build': '1', 'identity': 'certificate', 'bundle_id': 'test'}
        self.candidate = dict(self.installed, build='2')
        self.state = dict(windows=[{'window-id': 1, 'workspace': 'a'}], workspaces=[],
                          focus=[], focused_window=[], monitors=[])
        self.after = None
        self.config_changed = False
        self.topology_changed = False
        self.lock_after_launch = False

    def call(self, name):
        self.calls.append(name)
        if self.fail == name:
            raise RuntimeError(name)

    def locked(self): return self.is_locked
    def topology(self): return ['changed'] if self.topology_changed else ['display']
    def metadata(self, app):
        self.call('metadata')
        return copy.deepcopy(self.installed if app == APP else self.candidate)
    def config(self): return {'path': 'config', 'sha256': 'changed' if self.config_changed else 'same'}
    def snapshot(self):
        self.call('snapshot')
        return copy.deepcopy(self.state)
    def archive(self, path): self.call('archive')
    def stop(self): self.call('stop')
    def replace(self, source):
        self.call('replace')
        self.installed = copy.deepcopy(self.candidate)
    def launch(self):
        self.call('launch')
        if self.after: self.state = self.after
        self.is_locked = self.lock_after_launch
    def rollback(self, archive, expected):
        self.call('rollback')
        self.installed = expected
    def restore(self, before, current): self.call('restore')
    def sleep(self): pass


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.ops = Operations()
        self.installer = Installer(self.ops, Path(self.directory.name) / 'report.json')

    def install(self, **kwargs): return self.installer.install(Path('/candidate'), **kwargs)

    def testSuccessAndOrder(self):
        self.assertEqual(self.install()['status'], 'validated')
        calls = self.ops.calls
        self.assertLess(calls.index('archive'), calls.index('stop'))
        self.assertLess(calls.index('stop'), calls.index('replace'))
        self.assertLess(calls.index('replace'), calls.index('launch'))
        self.assertIn('restore', calls)
        self.assertTrue(Path(self.installer.report['archive']).is_absolute())

    def testDryRunDoesNotMutate(self):
        self.assertEqual(self.install(dry_run=True)['status'], 'dry_run_passed')
        self.assertFalse(set(self.ops.calls) & {'archive', 'stop', 'replace', 'launch', 'restore'})

    def testPreflightFailuresNeverStop(self):
        for failure in ('metadata', 'archive'):
            with self.subTest(failure=failure):
                self.ops.fail = failure
                with self.assertRaises(RuntimeError): self.install()
                self.assertNotIn('stop', self.ops.calls)
        self.ops.fail = None
        self.ops.candidate['identity'] = 'other'
        with self.assertRaises(RuntimeError): self.install()
        self.assertNotIn('stop', self.ops.calls)

    def testStopFailureNeverReplaces(self):
        self.ops.fail = 'stop'
        with self.assertRaises(RuntimeError): self.install()
        self.assertNotIn('replace', self.ops.calls)
        self.assertNotIn('rollback', self.ops.calls)

    def testLaunchFailureRollsBack(self):
        self.ops.fail = 'launch'
        self.assertEqual(self.install()['status'], 'rolled_back')
        self.assertEqual(self.ops.installed['build'], '1')

    def testLockedSessionNeverInstalls(self):
        self.ops.is_locked = True
        self.assertEqual(self.install()['status'], 'blocked_locked')
        self.assertEqual(self.ops.calls, [])

    def testLockDuringStartupCanResumeWithoutFocusReplay(self):
        self.ops.lock_after_launch = True
        self.assertEqual(self.install()['status'], 'installed_pending_validation')
        self.ops.is_locked = False
        result = self.installer.verify()
        self.assertEqual(result['status'], 'validated')
        self.assertNotIn('reason', result)
        self.assertNotIn('restore', self.ops.calls)

    def testMovedWindowRequiresReview(self):
        self.ops.after = copy.deepcopy(self.ops.state)
        self.ops.after['windows'][0]['workspace'] = 'b'
        self.assertEqual(self.install()['status'], 'needs_review')
        self.assertNotIn('restore', self.ops.calls)

    def testNewAndClosedWindowsAreReported(self):
        self.ops.after = copy.deepcopy(self.ops.state)
        self.ops.after['windows'] = [{'window-id': 2, 'workspace': 'b'}]
        result = self.install()
        self.assertEqual(result['status'], 'validated')
        self.assertEqual(result['differences'], {'closed': ['1'], 'opened': ['2'], 'moved': {}})

    def testResumeRejectsChangedBuildTopologyAndConfig(self):
        self.install()
        self.ops.calls.clear()
        self.ops.installed['build'] = '3'
        self.assertEqual(self.installer.verify()['reason'], 'installed_build_changed')
        self.ops.installed['build'] = '2'
        self.ops.topology_changed = True
        self.assertEqual(self.installer.verify()['reason'], 'display_topology_changed')
        self.ops.topology_changed = False
        self.ops.config_changed = True
        self.assertEqual(self.installer.verify()['reason'], 'config_changed')
        self.assertNotIn('restore', self.ops.calls)

    def testResumeCLIErrorDoesNotRollback(self):
        self.install()
        self.ops.calls.clear()
        self.ops.fail = 'snapshot'
        self.assertEqual(self.installer.verify()['status'], 'needs_review')
        self.assertNotIn('rollback', self.ops.calls)

    def testRollbackFailureIsVisible(self):
        self.ops.fail = 'launch'
        def fail_rollback(*args): raise RuntimeError('rollback failed')
        self.ops.rollback = fail_rollback
        result = self.install()
        self.assertEqual(result['status'], 'rollback_failed')
        self.assertIn('rollback_error', result)

    def testLockDuringRestorationRemainsPending(self):
        def lock(*args): raise SessionLocked()
        self.ops.restore = lock
        self.assertEqual(self.install()['status'], 'installed_pending_validation')

    def testDesktopChangeAfterBackupNeverStopsApp(self):
        original = self.ops.archive
        def archive(path):
            original(path)
            self.ops.state['focus'] = [{'workspace': 'other'}]
        self.ops.archive = archive
        self.assertEqual(self.install()['reason'], 'state_changed_before_shutdown')
        self.assertNotIn('stop', self.ops.calls)

    def testFocusChangesDuringStartupAreNotOverwritten(self):
        original = self.ops.snapshot
        def snapshot():
            state = original()
            if 'launch' in self.ops.calls:
                state['focus'] = [{'workspace': str(self.ops.calls.count('snapshot'))}]
            return state
        self.ops.snapshot = snapshot
        self.assertEqual(self.install()['reason'], 'focus_changed_during_validation')
        self.assertNotIn('restore', self.ops.calls)

    def testStartupFocusThatSettlesBackIsRestoredNormally(self):
        original = self.ops.snapshot
        def snapshot():
            state = original()
            if 'launch' in self.ops.calls and self.ops.calls.count('snapshot') == 3:
                state['focus'] = [{'workspace': 'transient'}]
            return state
        self.ops.snapshot = snapshot
        self.assertEqual(self.install()['status'], 'validated')
        self.assertIn('restore', self.ops.calls)

    def testReportsCannotLiveInApplications(self):
        with self.assertRaises(ValueError): Installer(self.ops, Path('/Applications/report.json'))


class NativeOperationsTest(unittest.TestCase):
    def testRelaunchKeepsTheRunningConfig(self):
        ops = NativeOperations()
        calls = []
        ops.run = lambda *args: calls.append(args)
        ops.launch()
        ops.config_path = '/config/native.toml'
        ops.launch()
        self.assertEqual(calls, [('open', APP), ('open', APP, '--args', '--config-path', '/config/native.toml')])


if __name__ == '__main__': unittest.main()
