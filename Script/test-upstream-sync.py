#!/usr/bin/env python3
"""Exercise tag selection and rebase failure boundaries in disposable Git repositories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM_URL = 'https://github.com/Lakr233/libghostty-spm.git'


class SyncTests(unittest.TestCase):
    def run_git(self, *args, cwd=None):
        return subprocess.check_output(['git', *args], cwd=cwd or self.repo, env=self.env, text=True).strip()

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        self.run_git('add', '.')
        self.run_git('commit', '-qm', message)
        return self.run_git('rev-parse', 'HEAD')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.env = {**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                    'GIT_AUTHOR_NAME': 'Test', 'GIT_AUTHOR_EMAIL': 'test@example.invalid',
                    'GIT_COMMITTER_NAME': 'Test', 'GIT_COMMITTER_EMAIL': 'test@example.invalid',
                    'GIT_EDITOR': 'true', 'RUNNER_TEMP': str(self.base),
                    'GITHUB_OUTPUT': str(self.base / 'output')}
        self.run_git('init', '-q', '-b', 'main')
        self.write('.root', '')
        self.write('Ghostty.ref', 'a' * 40 + '\n')
        self.write('Ghostty.build', '1\n')
        self.write('source.swift', 'baseline\n')
        self.manifest = 'name: "Base"\n' + '\n' * 10 + 'url: "https://github.com/Lakr233/libghostty-spm/releases/download/upstream.aaaaaaaaaaaa/GhosttyKit.xcframework.zip",\nchecksum: "' + 'a' * 64 + '"\n'
        self.write('Package.swift', self.manifest)
        self.commit('base')
        self.run_git('tag', '1.0.1')
        self.upstream = self.base / 'upstream.git'
        self.origin = self.base / 'origin.git'
        self.run_git('clone', '-q', '--bare', str(self.repo), str(self.upstream))
        self.run_git('clone', '-q', '--bare', str(self.repo), str(self.origin))
        self.run_git('remote', 'add', 'origin', str(self.origin))
        self.run_git('config', f'url.{self.upstream}.insteadOf', UPSTREAM_URL)
        self.run_git('switch', '-qc', 'termind')
        for name in ('prepare-upstream-sync.sh', 'merge-release-manifest.py'):
            self.write('Script/' + name, (ROOT / 'Script' / name).read_text())
        self.write('Script/check-licenses.sh', '#!/bin/sh\nexit 0\n')
        (self.repo / 'Script/check-licenses.sh').chmod(0o755)
        self.write('Package.swift', self.manifest.replace('Lakr233', 'AkinoKaede').replace('"' + 'a' * 64, '"' + 'b' * 64))
        self.write('Ghostty.build', '4\n')
        self.old = self.commit('fork')
        self.run_git('push', '-q', 'origin', 'termind')

    def tag_upstream(self, change, tag='1.0.2'):
        self.run_git('switch', '-q', 'main')
        change()
        revision = self.commit('upstream')
        self.run_git('tag', tag)
        self.run_git('push', '-q', str(self.upstream), 'main', 'refs/tags/' + tag)
        self.run_git('switch', '-q', 'termind')
        # Avoid locally created fixture tags masking accidental tag imports.
        self.run_git('tag', '-d', tag)
        return revision

    def prepare(self, success=True):
        result = subprocess.run(['zsh', 'Script/prepare-upstream-sync.sh'], cwd=self.repo,
                                env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.run_git('rev-parse', 'termind', cwd=self.origin), self.old)
        return (self.base / 'output').read_text() if (self.base / 'output').exists() else ''

    def test_ahead_of_tag_ignores_untagged_main(self):
        self.run_git('switch', '-q', 'main')
        self.write('untagged.swift', 'not released\n')
        self.commit('untagged')
        self.run_git('push', '-q', str(self.upstream), 'main')
        self.run_git('switch', '-q', 'termind')
        self.assertIn('changed=false', self.prepare())
        self.assertEqual(self.run_git('rev-parse', 'HEAD'), self.old)
        self.assertFalse((self.repo / 'untagged.swift').exists())

    def test_manifest_metadata_conflict_preserves_upstream_structure(self):
        new = self.tag_upstream(lambda: self.write('Package.swift', self.manifest.replace('Base', 'Upstream').replace('"' + 'a' * 64, '"' + 'c' * 64)))
        self.assertIn('changed=true', self.prepare())
        self.run_git('merge-base', '--is-ancestor', new, 'HEAD')
        manifest = (self.repo / 'Package.swift').read_text()
        self.assertIn('name: "Upstream"', manifest)
        self.assertIn('AkinoKaede', manifest)
        self.assertNotIn('__CHECKSUM__', manifest)
        self.assertEqual((self.repo / 'Ghostty.build').read_text(), '4\n')
        self.assertNotIn('1.0.2', self.run_git('tag', '--list').splitlines())

    def test_structural_manifest_conflict_requires_review(self):
        self.write('Package.swift', (self.repo / 'Package.swift').read_text().replace('Base', 'Fork'))
        self.old = self.commit('fork package name')
        self.run_git('push', '-q', 'origin', 'termind')
        self.tag_upstream(lambda: self.write('Package.swift', self.manifest.replace('Base', 'Upstream')))
        self.assertNotIn('changed=true', self.prepare(success=False))
        self.assertIn('Package.swift', self.run_git('diff', '--name-only', '--diff-filter=U'))

    def test_native_changes_choose_unused_asset_revision(self):
        self.run_git('tag', 'upstream.aaaaaaaaaaaa-7')
        self.run_git('push', '-q', 'origin', 'refs/tags/upstream.aaaaaaaaaaaa-7')
        self.tag_upstream(lambda: self.write('Patches/native.sh', 'new native patch\n'))
        self.prepare()
        self.assertEqual((self.repo / 'Ghostty.build').read_text(), '8\n')

    def test_source_conflict_stops_before_promotion(self):
        self.write('source.swift', 'fork change\n')
        self.old = self.commit('fork source')
        self.run_git('push', '-q', 'origin', 'termind')
        self.tag_upstream(lambda: self.write('source.swift', 'upstream change\n'))
        self.assertNotIn('changed=true', self.prepare(success=False))
        self.assertIn('source.swift', self.run_git('diff', '--name-only', '--diff-filter=U'))


if __name__ == '__main__':
    unittest.main()
