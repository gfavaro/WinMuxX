#!/usr/bin/env python3
"""Install a signed local WinMuxX build with an auditable, resumable report."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import shutil
import subprocess
import tempfile
import time
import uuid
import zipfile

APP = Path('/Applications/WinMuxX.app')


class SessionLocked(RuntimeError):
    pass


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(report, indent=2) + '\n')
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def differences(before, after):
    old = {str(w['window-id']): w['workspace'] for w in before['windows']}
    new = {str(w['window-id']): w['workspace'] for w in after['windows']}
    return {'moved': {key: [old[key], new[key]] for key in old.keys() & new.keys() if old[key] != new[key]},
            'closed': sorted(old.keys() - new.keys()), 'opened': sorted(new.keys() - old.keys())}


class NativeOperations:
    def run(self, *args):
        return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.PIPE, timeout=30)

    def locked(self):
        return '"CGSSessionScreenIsLocked"=Yes' in self.run('ioreg', '-n', 'Root', '-d1')

    def topology(self):
        # Independent of the app being upgraded, including when its CLI is unavailable.
        return json.loads(self.run('system_profiler', 'SPDisplaysDataType', '-json'))

    def metadata(self, app):
        self.run('codesign', '--verify', '--deep', '--strict', app)
        with (app / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / 'certificate'
            self.run('codesign', '-d', '--extract-certificates', prefix, app)
            leaf = Path(str(prefix) + '0')
            if not leaf.exists():
                raise RuntimeError('A persistent signing certificate is required')
            identity = hashlib.sha256(leaf.read_bytes()).hexdigest()
        if info['CFBundleIdentifier'] != 'com.gfavaro.winmuxx':
            raise RuntimeError('Unexpected bundle identifier')
        return {'build': info['CFBundleVersion'], 'identity': identity, 'bundle_id': info['CFBundleIdentifier']}

    def cli(self, *args):
        return self.run(APP / 'Contents/MacOS/winmuxx-cli', *args)

    def config(self):
        doctor = self.cli('doctor')
        if 'accessibility: granted' not in doctor or 'screen capture: granted' not in doctor:
            raise RuntimeError('Required permissions are unavailable')
        path = next((line.split('loaded:', 1)[1].strip() for line in doctor.splitlines() if 'loaded:' in line), None)
        if not path:
            raise RuntimeError('Could not resolve active config path')
        self.cli('reload-config', '--dry-run', '--no-gui')
        return {'path': path, 'sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest()}

    def snapshot(self):
        def query(*args):
            try:
                return json.loads(self.cli(*args, '--json'))
            except subprocess.CalledProcessError:
                if args[:2] == ('list-windows', '--focused'):
                    return []
                raise
        return {'windows': query('list-windows', '--all', '--format', '%{window-id} %{workspace}'),
                'workspaces': query('list-workspaces', '--all', '--format', '%{workspace} %{monitor-id} %{workspace-is-visible}'),
                'focus': query('list-workspaces', '--focused'),
                'focused_window': query('list-windows', '--focused', '--format', '%{window-id}'),
                'monitors': query('list-monitors')}

    def archive(self, target):
        if target.exists():
            raise RuntimeError('Rollback archive already exists')
        self.run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', APP, target)
        with zipfile.ZipFile(target) as archive:
            if archive.testzip() is not None or 'WinMuxX.app/Contents/Info.plist' not in archive.namelist():
                raise RuntimeError('Invalid rollback archive')

    def stop(self):
        result = subprocess.run(['pgrep', '-x', 'WinMuxX'], capture_output=True, text=True)
        pids = [int(pid) for pid in result.stdout.split()]
        for pid in pids:
            os.kill(pid, signal.SIGTERM)
        for _ in range(100):
            if not any(self.alive(pid) for pid in pids):
                return
            time.sleep(.1)
        raise RuntimeError('App did not terminate within ten seconds')

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def replace(self, source):
        with tempfile.TemporaryDirectory(dir=APP.parent, prefix='.winmuxx-install-') as directory:
            staged = Path(directory) / APP.name
            self.run('ditto', source, staged)
            self.metadata(staged)
            if self.locked():
                raise SessionLocked('Session locked before replacement')
            shutil.rmtree(APP)
            staged.replace(APP)
        self.metadata(APP)

    def launch(self):
        self.run('open', APP)

    def rollback(self, archive, expected):
        with tempfile.TemporaryDirectory() as directory:
            self.run('ditto', '-x', '-k', archive, directory)
            source = Path(directory) / 'WinMuxX.app'
            if self.metadata(source) != expected:
                raise RuntimeError('Rollback archive identity/build mismatch')
            self.stop()
            self.replace(source)
            self.launch()

    def restore(self, before, current):
        if before['monitors'] != current['monitors']:
            raise RuntimeError('Monitor topology changed; automatic layout restoration skipped')
        def command(*args):
            if self.locked():
                raise SessionLocked('Session locked during restoration')
            self.cli(*args)
        current_names = {w['workspace'] for w in current['workspaces']}
        # Restore each monitor's former visible workspace; internal names remain stable across labels.
        for workspace in before['workspaces']:
            if workspace['workspace-is-visible'] and workspace['workspace'] in current_names:
                present = next(w for w in current['workspaces'] if w['workspace'] == workspace['workspace'])
                if present['monitor-id'] != workspace['monitor-id']:
                    command('move-workspace-to-monitor', str(workspace['monitor-id']), '--workspace', workspace['workspace'])
                if not present['workspace-is-visible']:
                    command('workspace', '--name', workspace['workspace'])
        if before['focus'] != current['focus'] and before['focus'] and before['focus'][0]['workspace'] in current_names:
            command('workspace', '--name', before['focus'][0]['workspace'])
        surviving = {w['window-id'] for w in current['windows']}
        if before['focused_window'] != current['focused_window'] and before['focused_window'] and before['focused_window'][0]['window-id'] in surviving:
            command('focus', '--window-id', str(before['focused_window'][0]['window-id']))

    def sleep(self):
        time.sleep(.2)


class Installer:
    def __init__(self, operations, report_path):
        if report_path.resolve().is_relative_to(Path('/Applications')):
            raise ValueError('Reports and backups must be outside /Applications')
        self.ops, self.path = operations, report_path
        self.report = {}

    def status(self, status, **details):
        self.report.update(status=status, **details)
        write_report(self.path, self.report)
        return self.report

    def install(self, source, dry_run=False):
        if self.ops.locked():
            return self.status('blocked_locked')
        previous, candidate = self.ops.metadata(APP), self.ops.metadata(source)
        if previous['identity'] != candidate['identity']:
            raise RuntimeError('Signing identity differs from installed app')
        if not dry_run and int(candidate['build']) <= int(previous['build']):
            raise RuntimeError('Choose a fresh, increasing build number')
        self.report.update(previous=previous, candidate=candidate, config=self.ops.config(),
                           before=self.ops.snapshot(), topology=self.ops.topology(), source=str(source))
        if dry_run:
            return self.status('dry_run_passed')
        archive = self.path.parent / ('WinMuxX-rollback-' + uuid.uuid4().hex + '.zip')
        self.ops.archive(archive)
        self.status('backed_up', archive=str(archive))
        if self.ops.locked():
            return self.status('blocked_locked')
        fresh = self.ops.snapshot()
        if fresh != self.report['before'] or self.ops.config() != self.report['config'] or self.ops.topology() != self.report['topology']:
            return self.status('needs_review', reason='state_changed_before_shutdown')
        self.ops.stop()  # Failure here must never replace or roll back the running app.
        try:
            self.ops.replace(source)
            self.ops.launch()
        except Exception as error:
            return self.failed_install(error)
        return self.verify(restore=True)

    def failed_install(self, error):
        if not self.ops.locked() and self.ops.topology() == self.report['topology']:
            try:
                self.ops.rollback(Path(self.report['archive']), self.report['previous'])
                return self.status('rolled_back', error=str(error))
            except Exception as rollback_error:
                return self.status('rollback_failed', error=str(error), rollback_error=str(rollback_error))
        return self.status('installed_pending_validation', error=str(error))

    def verify(self, restore=False):
        if self.ops.locked():
            return self.status('installed_pending_validation', reason='session_locked')
        if self.ops.metadata(APP) != self.report['candidate']:
            return self.status('needs_review', reason='installed_build_changed')
        last_error = None
        current = None
        initial_focus = None
        focus_changed = False
        ready_samples = 0
        for _ in range(150):
            if self.ops.locked():
                return self.status('installed_pending_validation', reason='session_locked')
            try:
                current = self.ops.snapshot()
                focus = (current['focus'], current['focused_window'])
                if initial_focus is None:
                    initial_focus = focus
                elif focus != initial_focus:
                    focus_changed = True
                delta = differences(self.report['before'], current)
                # Require discovery before accepting missing windows as closed.
                if not self.report['before']['windows'] or current['windows']:
                    if not delta['moved'] and not delta['closed']:
                        ready_samples += 1
                        if ready_samples >= 3:
                            break
                    else:
                        ready_samples = 0
            except Exception as error:
                last_error = str(error)
            self.ops.sleep()
        if current is None:
            if restore:
                return self.failed_install(last_error or 'CLI startup timed out')
            return self.status('needs_review', reason='CLI unavailable', error=last_error)
        if self.ops.topology() != self.report['topology']:
            return self.status('needs_review', reason='display_topology_changed', after=current)
        if self.ops.config() != self.report['config']:
            return self.status('needs_review', reason='config_changed', after=current)
        delta = differences(self.report['before'], current)
        if delta['moved'] or (self.report['before']['windows'] and not current['windows']):
            return self.status('needs_review', reason='window_assignments', differences=delta, after=current)
        if self.ops.locked():
            return self.status('installed_pending_validation', reason='session_locked')
        if restore and not focus_changed:
            try:
                self.ops.restore(self.report['before'], current)
            except SessionLocked:
                return self.status('installed_pending_validation', reason='session_locked')
            current = self.ops.snapshot()
            delta = differences(self.report['before'], current)
            if delta['moved']:
                return self.status('needs_review', reason='restoration_changed_assignments', after=current, differences=delta)
        elif focus_changed:
            return self.status('needs_review', reason='focus_changed_during_validation', after=current)
        if restore:
            surviving = {w['window-id'] for w in current['windows']}
            expected_focus = self.report['before']['focused_window']
            if expected_focus and expected_focus[0]['window-id'] in surviving and current['focused_window'] != expected_focus:
                return self.status('needs_review', reason='focus_not_restored', after=current)
        # Resume deliberately observes current user focus; it never replays stale focus commands.
        return self.status('validated', after=current, differences=delta,
                           presentation_restored=restore, resumed_without_focus_changes=not restore)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--dry-run', action='store_true')
    modes.add_argument('--install', action='store_true')
    modes.add_argument('--resume', type=Path)
    modes.add_argument('--rollback', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report_path = args.resume or args.rollback or args.report or Path('.release') / ('install-' + uuid.uuid4().hex + '.json')
    installer = Installer(NativeOperations(), report_path)
    try:
        if args.resume or args.rollback:
            installer.report = json.loads(report_path.read_text())
            if args.resume:
                result = installer.verify()
            elif installer.ops.locked():
                result = installer.status('rollback_pending_unlock')
            else:
                installer.ops.rollback(Path(installer.report['archive']), installer.report['previous'])
                result = installer.status('rolled_back')
        else:
            if not args.app:
                parser.error('--app is required for install/dry-run')
            result = installer.install(args.app.resolve(), args.dry_run)
        print(json.dumps({'status': result['status'], 'report': str(report_path)}))
        return 0 if result['status'] in {'validated', 'dry_run_passed'} else 2
    except Exception as error:
        installer.status('failed', error=str(error))
        print(json.dumps({'status': 'failed', 'error': str(error), 'report': str(report_path)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
