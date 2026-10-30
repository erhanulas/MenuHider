#!/usr/bin/env python3
"""Build a universal MenuHider app and sign its GitHub/Sparkle update feed.

The EdDSA private key stays in the login Keychain; it is never copied to the repo.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version', help='Release version, e.g. 1.0.1')
    parser.add_argument('build', type=int, help='Always increasing build number, e.g. 101')
    parser.add_argument('--identity', default='-', help='Developer ID identity, or - for ad hoc')
    parser.add_argument('--notes', help='UTF-8 release notes file')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or args.build < 1:
        parser.error('Use a three-part version and a positive build number.')
    os.chdir(ROOT)
    derived = ROOT / 'build/ReleaseData'
    output = ROOT / 'dist' / ('v' + args.version)
    if output.exists():
        parser.error(f'Release directory already exists: {output}')
    run('xcodebuild', '-project', 'Hidden Bar.xcodeproj', '-scheme', 'Hidden Bar',
        '-configuration', 'Release-Direct', '-derivedDataPath', derived,
        'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO',
        'MARKETING_VERSION=' + args.version, 'CURRENT_PROJECT_VERSION=' + str(args.build), 'build')
    source = derived / 'Build/Products/Release-Direct/MenuHider.app'
    with (source / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    assert info['CFBundleIdentifier'] == 'com.erhanulas.menuhider'
    assert info['CFBundleShortVersionString'] == args.version
    assert info['CFBundleVersion'] == str(args.build)
    assert info['SUPublicEDKey'] and info['SURequireSignedFeed']
    output.mkdir(parents=True)
    # Stage outside iCloud folders: Finder metadata otherwise breaks signing.
    with tempfile.TemporaryDirectory(prefix='menuhider-release-') as directory:
        app = Path(directory) / 'MenuHider.app'
        run('ditto', '--norsrc', '--noextattr', source, app)
        for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
            subprocess.run(['xattr', '-dr', attribute, str(app)], capture_output=True)
        shutil.copyfile(ROOT / 'LICENSE', app / 'Contents/Resources/MenuHider-LICENSE.txt')
        notices = []
        for dependency in ('HotKey', 'Sparkle'):
            license_file = derived / 'SourcePackages/checkouts' / dependency / 'LICENSE'
            notices.append(dependency + '\n' + license_file.read_text())
        (app / 'Contents/Resources/ThirdPartyNotices.txt').write_text('\n\n'.join(notices))
        signing = ['codesign', '--force', '--deep', '--sign', args.identity,
                   '--preserve-metadata=entitlements']
        if args.identity != '-':
            signing.extend(['--options', 'runtime', '--timestamp'])
        run(*signing, app)
        run('codesign', '--verify', '--deep', '--strict', app)
        architectures = run('lipo', '-archs', app / 'Contents/MacOS/MenuHider', capture_output=True, text=True).stdout.split()
        assert {'arm64', 'x86_64'}.issubset(architectures), architectures
        archive = output / f'MenuHider-{args.version}.zip'
        run('ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr', app, archive)
    if args.notes:
        # Plain text is embedded in the feed, not served through another URL.
        shutil.copyfile(args.notes, output / f'MenuHider-{args.version}.txt')
    tools = derived / 'SourcePackages/artifacts/sparkle/Sparkle/bin'
    run(tools / 'generate_appcast', '--account', 'com.erhanulas.menuhider',
        '--download-url-prefix', f'https://github.com/erhanulas/MenuHider/releases/download/v{args.version}/',
        '--embed-release-notes', '--maximum-deltas', '0', output)
    (output / 'SHA256SUMS.txt').write_text(
        hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
    print(f'Release ready: {output}')

if __name__ == '__main__':
    main()
