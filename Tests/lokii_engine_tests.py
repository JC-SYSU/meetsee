#!/usr/bin/env python3
"""Managed engine contract: explicit private scope, events, no global Lokii."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest

BINARY = Path(sys.argv.pop(1)).resolve()


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='meetsee-engine-test-')
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.scope = self.root / 'scope'
        self.scope.mkdir()
        self.cache = self.root / 'private-cache'
        self.cache.mkdir()
        self.global_config = self.home / '.config/lokii'
        self.global_config.mkdir(parents=True)
        self.poison = '[index]\nindex_paths=["/"]\nmax_results=1\n'
        (self.global_config / 'config.toml').write_text(self.poison)
        (self.global_config / 'index.cache').write_bytes(b'UNRELATED_OFFICIAL_CACHE')
        (self.scope / '项目 Report.txt').touch()
        (self.scope / 'README').touch()
        (self.scope / '.hidden').touch()
        (self.scope / 'node_modules').mkdir()
        (self.scope / 'node_modules' / 'retained.txt').touch()
        self.env = {'HOME': str(self.home), 'XDG_CONFIG_HOME': str(self.home / '.config'),
                    'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8', 'TMPDIR': str(self.root)}
        self.processes = []
        self.serial = 0

    def tearDown(self):
        for p in self.processes:
            if p.poll() is None:
                p.kill()
            p.wait(timeout=5)
            p.stdin.close()
            p.stdout.close()
            p.stderr.close()
        self.temp.cleanup()

    def start(self, sandbox=False):
        cmd = [str(BINARY), '--stdio']
        if sandbox:
            # Deny the actual official paths, quarantined data, and developer sources.
            # The test binary lives in an independent staged App, outside the source tree.
            blocked = ['/Applications/Lokii.app', '/usr/local/bin/lokii',
                       str(Path.home() / '.config/lokii'),
                       '/tmp/meetsee-lokii-quarantine-ga2a10s2',
                       '/tmp/meetsee-lokii-quarantine-ga2a10s2',
                       '/tmp/meetsee-lokii-source.GTYEO5',
                       '/tmp/meetsee-lokii-source.GTYEO5',
                       str(Path(__file__).resolve().parents[1])]
            profile = '(version 1)(allow default)' + ''.join(
                '(deny file-read* (subpath ' + json.dumps(path) + '))' for path in blocked)
            cmd = ['/usr/bin/sandbox-exec', '-p', profile] + cmd
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=self.env, cwd=self.root, bufsize=0)
        self.processes.append(p)
        return p

    def line(self, p):
        data = bytearray()
        while not data.endswith(b'\n'):
            self.assertTrue(select.select([p.stdout], [], [], 15)[0], 'response timeout')
            c = p.stdout.read(1)
            self.assertTrue(c, 'unexpected engine EOF')
            data += c
        value = json.loads(data)
        return self.line(p) if value.get('event') else value

    def request(self, p, op, **fields):
        self.serial += 1
        p.stdin.write((json.dumps(dict(protocol=1, id=self.serial, op=op, **fields)) + '\n').encode())
        result = self.line(p)
        while result.get('event'):
            result = self.line(p)
        self.assertEqual(result['id'], self.serial)
        self.assertEqual(result['protocol'], 1)
        return result

    def initialize(self, p, **overrides):
        config = dict(roots=[str(self.scope)], excludedPaths=[], includeHidden=False,
                      maxResults=5000, cacheDirectory=str(self.cache))
        config.update(overrides)
        result = self.request(p, 'initialize', config=config)
        if result['ok']:
            import time
            end = time.monotonic() + 15
            while time.monotonic() < end:
                state = self.request(p, 'status')['data']
                if state['scopeSynchronized'] or state['phase'] == 'failed':
                    if state['phase'] == 'failed':
                        self.fail(str(state))
                    break
                time.sleep(0.05)
            else:
                self.fail('initialization did not settle: ' + str(state))
        return result

    def test_handshake_has_no_implicit_scan(self):
        p = self.start()
        r = self.request(p, 'hello')
        self.assertTrue(r['ok'])
        self.assertTrue(r['data']['coreVersion'].startswith('0.1.9'))
        self.assertTrue(r['data']['capabilities']['liveUpdates'])
        self.assertEqual(self.request(p, 'status')['data']['phase'], 'awaitingConfiguration')
        self.assertFalse((self.cache / 'index.cache').exists())
        self.assertFalse(self.request(p, 'search', query='项目', limit=20)['ok'])
        p.stdin.close()
        self.assertEqual(p.wait(timeout=5), 0)

    def test_snapshot_search_cache_and_shutdown(self):
        p = self.start()
        self.assertTrue(self.initialize(p)['ok'])
        data = self.request(p, 'status')['data']
        self.assertEqual(data['phase'], 'ready')
        self.assertTrue(data['queryable'])
        for query, name in [('项目 report', '项目 Report.txt'), ('README', 'README'),
                            ('retained', 'retained.txt')]:
            r = self.request(p, 'search', query=query, limit=20)
            self.assertTrue(r['ok'])
            self.assertIn(name, [e['name'] for e in r['data']['results']])
        self.assertEqual(self.request(p, 'search', query='.hidden', limit=20)['data']['results'], [])
        self.assertGreater((self.cache / 'index.cache').stat().st_size, 0)
        self.assertEqual((self.global_config / 'config.toml').read_text(), self.poison)
        self.assertEqual((self.global_config / 'index.cache').read_bytes(), b'UNRELATED_OFFICIAL_CACHE')
        self.assertFalse((self.global_config / 'query.sock').exists())
        self.assertTrue(self.request(p, 'shutdown')['ok'])
        self.assertEqual(p.wait(timeout=5), 0)

    def test_no_source_or_official_install_required(self):
        p = self.start(sandbox=True)
        self.assertTrue(self.initialize(p)['ok'])
        self.assertTrue(self.request(p, 'search', query='Report', limit=5)['data']['results'])
        self.assertTrue(self.request(p, 'shutdown')['ok'])
        self.assertEqual(p.wait(timeout=5), 0)

    def test_bad_protocol_input_and_unknown_fields(self):
        p = self.start()
        p.stdin.write(b'{bad json}\n')
        self.assertFalse(self.line(p)['ok'])
        p.stdin.write(b'{"protocol":99,"id":42,"op":"hello"}\n')
        r = self.line(p)
        self.assertFalse(r['ok'])
        self.assertEqual(r['id'], 42)
        self.assertFalse(self.request(p, 'initialize', config={'roots': []})['ok'])
        self.assertFalse(self.request(p, 'hello', unexpected=True)['ok'])
        self.assertEqual(self.request(p, 'status')['data']['phase'], 'awaitingConfiguration')

    def test_scope_and_limit_validation(self):
        p = self.start()
        self.assertFalse(self.initialize(p, roots=['~'])['ok'])
        self.assertFalse(self.initialize(p, roots=['/nonexistent-meetsee-fixture'])['ok'])
        self.assertFalse(self.initialize(p, cacheDirectory=str(self.scope))['ok'])
        self.assertFalse(self.initialize(p, maxResults=0)['ok'])
        self.assertTrue(self.initialize(p, includeHidden=True)['ok'])
        self.assertTrue(self.request(p, 'search', query='.hidden', limit=20)['data']['results'])
        self.assertFalse(self.request(p, 'search', query='x', limit=5001)['ok'])
        self.assertFalse(self.initialize(p)['ok'], 'cannot silently rescan initialized engine')

    def test_empty_scope_is_valid(self):
        p = self.start()
        self.assertTrue(self.initialize(p, roots=[])['ok'])
        data = self.request(p, 'status')['data']
        self.assertTrue(data['queryable'])
        self.assertEqual(data['count'], 0)
        self.assertEqual(self.request(p, 'search', query='anything', limit=20)['data']['results'], [])

    def test_exclusion_and_private_cache_inside_scope(self):
        p = self.start()
        private = self.scope / 'engine-private'
        private.mkdir()
        (private / 'SHOULD_NOT_INDEX.txt').touch()
        excluded = self.scope / 'node_modules'
        self.assertTrue(self.initialize(p, excludedPaths=[str(excluded)],
                                        cacheDirectory=str(private))['ok'])
        for query in ['retained', 'SHOULD_NOT_INDEX', 'index.cache']:
            self.assertEqual(self.request(p, 'search', query=query, limit=20)['data']['results'], [])
        self.assertTrue(self.request(p, 'search', query='Report', limit=20)['data']['results'])

    def test_cache_errors_do_not_publish_ready_index(self):
        p = self.start()
        victim = self.root / 'unrelated.txt'
        victim.write_text('KEEP')
        (self.cache / 'index.tmp').symlink_to(victim)
        self.assertFalse(self.initialize(p)['ok'])
        self.assertEqual(victim.read_text(), 'KEEP')
        self.assertFalse(self.request(p, 'status')['data']['queryable'])

    def test_live_add_move_delete_and_hot_offline_replay(self):
        import time
        p = self.start()
        self.initialize(p)
        item = self.scope / 'LIVE-新增.txt'
        item.touch()
        def await_hits(query, expected):
            end = time.monotonic() + 10
            while time.monotonic() < end:
                hits = self.request(p, 'search', query=query, limit=20)['data']['results']
                if bool(hits) == expected:
                    return
                time.sleep(0.1)
            self.fail('file changes did not converge: ' + query)
        await_hits('LIVE-新增', True)
        moved = self.scope / 'LIVE-移动.txt'
        item.rename(moved)
        await_hits('LIVE-新增', False)
        await_hits('LIVE-移动', True)
        moved.unlink()
        await_hits('LIVE-移动', False)
        self.assertTrue(self.request(p, 'shutdown')['data']['graceful'])
        p.wait(timeout=5)
        (self.scope / 'OFFLINE-变化.txt').touch()
        p = self.start()
        self.initialize(p)
        self.assertEqual(self.request(p, 'status')['data']['startup'], 'hotCache')
        await_hits('OFFLINE-变化', True)

    def test_cache_ownership_and_rebuild(self):
        p = self.start()
        self.initialize(p, listen=False)
        second = self.start()
        self.assertFalse(self.initialize(second)['ok'])
        self.assertFalse(self.request(p, 'status')['data']['liveUpdates'])
        (self.scope / 'MANUAL-刷新.txt').touch()
        self.assertFalse(self.request(p, 'search', query='MANUAL-刷新', limit=5)['data']['results'])
        self.assertTrue(self.request(p, 'rebuild')['ok'])
        import time
        end = time.monotonic() + 10
        while time.monotonic() < end:
            if self.request(p, 'status')['data']['scopeSynchronized']:
                break
            time.sleep(0.1)
        self.assertTrue(self.request(p, 'search', query='MANUAL-刷新', limit=5)['data']['results'])

    def test_scope_narrowing_reuses_cache_and_widening_rescans(self):
        p = self.start()
        self.initialize(p)
        self.request(p, 'shutdown'); p.wait(timeout=5)
        p = self.start()
        self.initialize(p, excludedPaths=[str(self.scope / 'node_modules')])
        self.assertEqual(self.request(p, 'status')['data']['startup'], 'narrowedCache')
        self.assertFalse(self.request(p, 'search', query='retained', limit=5)['data']['results'])
        self.request(p, 'shutdown'); p.wait(timeout=5)
        p = self.start()
        self.initialize(p)
        self.assertEqual(self.request(p, 'status')['data']['startup'], 'coldScan')
        self.assertTrue(self.request(p, 'search', query='retained', limit=5)['data']['results'])

    def test_oversized_line_terminates_without_scan(self):
        p = self.start()
        p.stdin.write(b'x' * (65536 + 1) + b'\n')
        self.assertFalse(self.line(p)['ok'])
        self.assertNotEqual(p.wait(timeout=5), 0)
        self.assertFalse((self.cache / 'index.cache').exists())

    def test_version_without_configuration(self):
        result = subprocess.run([str(BINARY), '--version'], capture_output=True, text=True,
                                env=self.env, cwd=self.root, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn('lokii-core 0.1.9', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
