#!/usr/bin/env python3
"""Opt-in signed Sparkle integration checks using disposable apps, never real accounts."""
import functools
import http.server
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = ROOT / '.build/artifacts/sparkle/Sparkle'
FRAMEWORKS = SPARKLE / 'Sparkle.xcframework/macos-arm64_x86_64'

def run(*args):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True, text=True).stdout

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

def main():
    with tempfile.TemporaryDirectory(prefix='codex-updater-test-') as folder:
        root = pathlib.Path(folder).resolve()
        binary = root / 'probe'
        run('swiftc', '-parse-as-library', ROOT / 'scripts/fixtures/UpdateProbe.swift', '-F', FRAMEWORKS,
            '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', '-o', binary)
        secret = root / 'test-only-key'
        key = run('swift', ROOT / 'scripts/fixtures/TestSigningKey.swift', secret).strip()
        for scenario in ['valid', 'changed-archive', 'changed-feed']:
            case = root / scenario; case.mkdir()
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(case)))
            server.daemon_threads = True
            threading.Thread(target=server.serve_forever, daemon=True).start()
            base = f'http://127.0.0.1:{server.server_port}/'
            app_id = 'org.codexaccounts.probe.' + uuid.uuid4().hex
            installed = case / 'installed'; installed.mkdir()
            future = case / 'future'; future.mkdir()
            def make_app(parent, version):
                app = parent / 'Update Probe.app'
                (app / 'Contents/MacOS').mkdir(parents=True)
                (app / 'Contents/Frameworks').mkdir()
                shutil.copy2(binary, app / 'Contents/MacOS/Probe')
                run('/usr/bin/ditto', FRAMEWORKS / 'Sparkle.framework', app / 'Contents/Frameworks/Sparkle.framework')
                info = dict(CFBundleExecutable='Probe', CFBundleName='Codex Accounts' if version == '1' else 'Codex Switcher', CFBundleIdentifier=app_id,
                            CFBundleDisplayName='Codex Accounts' if version == '1' else 'Codex Switcher',
                            CFBundlePackageType='APPL', CFBundleVersion=version, CFBundleShortVersionString=version+'.0',
                            LSMinimumSystemVersion='14.0', SUFeedURL=base+'feed.xml', SUPublicEDKey=key,
                            SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True, SUEnableAutomaticChecks=False,
                            NSAppTransportSecurity={'NSAllowsLocalNetworking':True,'NSAllowsArbitraryLoads':True})
                (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
                run('/usr/bin/codesign', '--force', '--deep', '--sign', '-', app)
                return app
            old_app = make_app(installed, '1')
            new_app = make_app(future, '2')
            archive = case / 'probe.zip'
            run('/usr/bin/ditto', '--norsrc', '--noextattr', '-c', '-k', '--keepParent', new_app, archive)
            signature = run(SPARKLE / 'bin/sign_update', '--ed-key-file', secret, '-p', archive).strip()
            feed = case / 'feed.xml'
            feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Update Probe</title>
<item><title>Probe 2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
<enclosure url="{base}probe.zip" sparkle:edSignature="{signature}" length="{archive.stat().st_size}" type="application/octet-stream" /></item></channel></rss>''')
            run(SPARKLE / 'bin/sign_update', '--ed-key-file', secret, feed)
            if scenario == 'changed-archive':
                data = bytearray(archive.read_bytes()); data[len(data)//2] ^= 1; archive.write_bytes(data)
            elif scenario == 'changed-feed':
                feed.write_text(feed.read_text().replace('<title>Probe 2</title>', '<title>Changed</title>'))
            output = case / 'process.txt'
            with output.open('w') as log:
                process = subprocess.Popen([str(old_app / 'Contents/MacOS/Probe')], stdout=log, stderr=log)
                marker = installed / 'probe-result.txt'
                deadline = time.monotonic() + 90
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.5)
                result = marker.read_text() if marker.exists() else 'timeout'
                version = plistlib.loads((old_app / 'Contents/Info.plist').read_bytes())['CFBundleVersion']
                display_name = plistlib.loads((old_app / 'Contents/Info.plist').read_bytes())['CFBundleDisplayName']
                expected = result == 'updated-and-relaunched' and version == '2' and display_name == 'Codex Switcher' and len(list(installed.glob('*.app'))) == 1 if scenario == 'valid' else result.startswith('rejected-') and version == '1'
                if process.poll() is None:
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)
                server.shutdown(); server.server_close()
                subprocess.run(['/usr/bin/defaults', 'delete', app_id], capture_output=True)
                if not expected:
                    print(output.read_text()[-6000:])
                    raise RuntimeError(f'{scenario}: {result}, version {version}')
                print(f'PASS {scenario}: {result}, installed version {version}', flush=True)

if __name__ == '__main__':
    main()
