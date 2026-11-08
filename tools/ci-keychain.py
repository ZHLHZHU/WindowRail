#!/usr/bin/env python3
"""Import a CI-only signing identity. Never uses the developer's local identity."""
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys

def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().strip()

try:
    root = Path(os.environ['RUNNER_TEMP'])
    keychain = root / 'WindowRail-CI.keychain-db'
    certificate = root / 'WindowRail-CI.p12'
    search_backup = root / 'WindowRail-CI-search.json'
    if sys.argv[1:] == ['cleanup']:
        if search_backup.exists():
            run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *json.loads(search_backup.read_text()))
            search_backup.unlink()
        if keychain.exists():
            run('/usr/bin/security', 'delete-keychain', str(keychain))
        certificate.unlink(missing_ok=True)
    elif sys.argv[1:] == ['import']:
        identity = os.environ['APPLE_SIGNING_IDENTITY'].strip()
        if not re.fullmatch('[0-9a-fA-F]{40}', identity):
            raise ValueError('APPLE_SIGNING_IDENTITY must be the signing certificate SHA-1 fingerprint')
        mode = os.environ.get('WINDOWRAIL_RELEASE_SIGNING_MODE', 'pinned')
        if mode not in ('pinned', 'identity'):
            raise ValueError('Unsupported release signing mode')
        if mode == 'pinned':
            pinned = (Path(__file__).resolve().parents[1] / 'Resources/release-signing.sha1').read_text().strip()
            if identity.upper() != pinned.upper():
                raise ValueError('Release certificate does not match the committed fingerprint')
        password = secrets.token_urlsafe(40)
        certificate.write_bytes(base64.b64decode(''.join(os.environ['APPLE_CERTIFICATE_P12_BASE64'].split()), validate=True))
        certificate.chmod(0o600)
        old_search = shlex.split(run('/usr/bin/security', 'list-keychains', '-d', 'user'))
        search_backup.write_text(json.dumps(old_search))
        search_backup.chmod(0o600)
        try:
            run('/usr/bin/security', 'create-keychain', '-p', password, str(keychain))
            run('/usr/bin/security', 'set-keychain-settings', '-lut', '21600', str(keychain))
            run('/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain))
            run('/usr/bin/security', 'import', str(certificate), '-k', str(keychain), '-P', os.environ['APPLE_CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign')
            run('/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,codesign:', '-s', '-k', password, str(keychain))
            # codesign also resolves identities through the user's search list.
            # Keep this keychain available across Actions steps; cleanup restores it.
            run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', str(keychain), *old_search)
        except Exception:
            run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *old_search)
            raise
        finally:
            certificate.unlink(missing_ok=True)
        with open(os.environ['GITHUB_ENV'], 'a') as out:
            out.write(f'WINDOWRAIL_SIGNING_MODE={mode}\nWINDOWRAIL_SIGNING_IDENTITY={identity}\nWINDOWRAIL_KEYCHAIN={keychain}\n')
        print('CI signing identity imported.')
    else:
        raise ValueError('Usage: ci-keychain.py import|cleanup')
except subprocess.CalledProcessError as error:
    print('CI signing operation failed: ' + error.stderr.decode(errors='replace').strip(), file=sys.stderr)
    sys.exit(1)
except (KeyError, ValueError, OSError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
