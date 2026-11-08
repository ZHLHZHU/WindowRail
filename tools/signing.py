#!/usr/bin/env python3
"""Private local signing identity; intentionally outside the distributable app."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import secrets

project = Path(__file__).resolve().parents[1]
config_path = project / 'signing.local.json'
local_config = json.loads(config_path.read_text()) if config_path.exists() else {}
state = Path(os.environ.get('WINDOWRAIL_SIGNING_DIR', local_config.get('directory', Path.home() / 'Library/Application Support/WindowRail/Signing'))).expanduser().resolve()
keychain = state / 'WindowRail.keychain-db'
password_file = state / 'keychain-password'
fingerprint_file = state / 'certificate-sha1'
identifier = 'local.windowrail.app'

def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs).stdout.decode().strip()

def initialize():
    if state.exists():
        raise RuntimeError(f'Signing directory already exists: {state}. Restore its original identity; do not replace it.')
    state.mkdir(parents=True, mode=0o700)
    password = secrets.token_urlsafe(40)
    password_file.write_text(password)
    password_file.chmod(0o600)
    config = state / 'certificate.cnf'
    config.write_text('''[req]
distinguished_name=dn
prompt=no
x509_extensions=signing
[dn]
CN=WindowRail Local Signing
[signing]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
''')
    old_search = shlex.split(run('/usr/bin/security', 'list-keychains', '-d', 'user'))
    try:
        run('/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:3072', '-nodes', '-days', '3650', '-config', config, '-keyout', state/'private-key.pem', '-out', state/'certificate.pem')
        (state/'private-key.pem').chmod(0o600)
        # The password is passed via a protected file, never included in output.
        run('/usr/bin/openssl', 'pkcs12', '-export', '-inkey', state/'private-key.pem', '-in', state/'certificate.pem', '-out', state/'identity.p12', '-passout', f'file:{password_file}')
        (state/'identity.p12').chmod(0o600)
        run('/usr/bin/security', 'create-keychain', '-p', password, keychain)
        run('/usr/bin/security', 'set-keychain-settings', '-lut', '21600', keychain)
        run('/usr/bin/security', 'unlock-keychain', '-p', password, keychain)
        run('/usr/bin/security', 'import', state/'identity.p12', '-k', keychain, '-P', password, '-T', '/usr/bin/codesign')
        run('/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,codesign:', '-s', '-k', password, keychain)
        der = subprocess.run(['/usr/bin/openssl','x509','-in',str(state/'certificate.pem'),'-outform','DER'],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
        fingerprint_file.write_text(hashlib.sha1(der).hexdigest().upper() + '\n')
    finally:
        run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *old_search)
    # Keep the encrypted keychain and certificate; avoid loose duplicate private keys.
    (state/'private-key.pem').unlink()
    (state/'identity.p12').unlink()
    print(f'Created persistent WindowRail signing identity in {state}')

def sign(app):
    if not all(p.exists() for p in (keychain, password_file, fingerprint_file)):
        raise RuntimeError('Persistent signing identity is missing. Run tools/signing.py init once for initial setup, or restore the original signing directory. No ad-hoc fallback is allowed.')
    password = password_file.read_text().strip()
    fingerprint = fingerprint_file.read_text().strip()
    requirement = f'identifier "{identifier}" and certificate leaf = H"{fingerprint}"'
    run('/usr/bin/security', 'unlock-keychain', '-p', password, keychain)
    run('/usr/bin/codesign', '--force', '--sign', fingerprint, '--keychain', keychain, '--timestamp=none', '--identifier', identifier, '--requirements', '=designated => ' + requirement, app)
    run('/usr/bin/codesign', '--verify', '--strict', '-R', '= '+requirement, app)
    print('Signed with the persistent WindowRail identity (certificate pinned).')

try:
    if sys.argv[1:] == ['init']:
        initialize()
    elif len(sys.argv) == 3 and sys.argv[1] == 'sign':
        sign(Path(sys.argv[2]).resolve())
    else:
        raise RuntimeError('Usage: signing.py init | signing.py sign APP')
except subprocess.CalledProcessError as error:
    # Never print the command line: it may contain a keychain password.
    print('Signing operation failed: ' + error.stderr.decode(errors='replace').strip(), file=sys.stderr)
    sys.exit(1)
except (RuntimeError, OSError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
