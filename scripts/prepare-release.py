#!/usr/bin/env python3
"""Prepare signed update feeds from built archives; never export the signing key or upload files."""
import argparse
import base64
import datetime
import email.utils
import pathlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
ACCOUNT = 'org.codexaccounts.updates'
REPOSITORY = 'https://github.com/taogezhizun/codex-accounts-mac'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)

def signed(*args):
    return subprocess.run([str(SPARKLE / 'sign_update'), '--account', ACCOUNT, *map(str, args)],
                          check=True, capture_output=True, text=True).stdout.strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        parser.error('Use a release version like 0.3.0')
    feeds = ROOT / 'appcast'; feeds.mkdir(exist_ok=True)
    for arch in ['arm64', 'x86_64']:
        name = f'Codex-Accounts-macOS-{arch}.zip'
        archive = ROOT / 'dist' / f'v{args.version}' / arch / name
        with zipfile.ZipFile(archive) as z:
            info = plistlib.loads(z.read('Codex Accounts.app/Contents/Info.plist'))
            assert info['CFBundleIdentifier'] == 'org.codexaccounts.mac'
            assert info['CFBundleShortVersionString'] == args.version
            assert 'CodexAccountsPreviewMode' not in info
            assert info['SUVerifyUpdateBeforeExtraction'] and info['SURequireSignedFeed']
            assert len(base64.b64decode(info['SUPublicEDKey'])) == 32
            assert info['SUFeedURL'] == f'https://raw.githubusercontent.com/taogezhizun/codex-accounts-mac/main/appcast/{arch}.xml'
            assert not any(n.startswith('__MACOSX/') or n.endswith('.DS_Store') for n in z.namelist())
        signature = signed('-p', archive)
        signed('--verify', archive, signature)
        rss = ET.Element('rss', {'version':'2.0'})
        channel = ET.SubElement(rss, 'channel')
        ET.SubElement(channel, 'title').text = 'Codex Switcher for macOS'
        ET.SubElement(channel, 'link').text = REPOSITORY
        ET.SubElement(channel, 'description').text = 'Signed updates maintained by taogezhizun.'
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = f'Codex Switcher {args.version}'
        ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
        ET.SubElement(item, f'{{{NS}}}version').text = info['CFBundleVersion']
        ET.SubElement(item, f'{{{NS}}}shortVersionString').text = args.version
        ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
        ET.SubElement(item, 'link').text = f'{REPOSITORY}/releases/tag/v{args.version}'
        ET.SubElement(item, 'enclosure', {
            'url':f'{REPOSITORY}/releases/download/v{args.version}/{name}',
            f'{{{NS}}}edSignature':signature, 'length':str(archive.stat().st_size), 'type':'application/octet-stream'
        })
        feed = feeds / f'{arch}.xml'
        ET.indent(rss)
        ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
        signed(feed)
        signed('--verify', feed)
        print(f'Verified signed archive and feed: {arch}', flush=True)

if __name__ == '__main__':
    main()
