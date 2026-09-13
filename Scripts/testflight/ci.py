#!/usr/bin/env python3
"""External TestFlight CI. No third-party dependencies; never log API payloads."""
import base64
import datetime as dt
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import plistlib
import uuid

BUNDLE = 'com.arpitdixit.dontsmoke'
TEAM = 'FCX2BY8WSZ'
VERSION = '9.0.0'
ROOT = Path(os.environ.get('TF_DIR', str(Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'testflight-poc')))
BASE = 'https://api.appstoreconnect.apple.com'


class SafeError(Exception):
    """Only deliberately sanitized messages may be printed."""


def require(name):
    value = os.environ.get(name, '')
    if not value.strip():
        raise SafeError(f'Missing required configuration: {name}')
    return value


def run(args, *, data=None, timeout=120, combined=False):
    # Do not echo commands, stdout or stderr: tools may include secrets or PII.
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, check=False)
    if result.returncode:
        raise SafeError(f'{Path(args[0]).name} failed (exit {result.returncode}); raw output suppressed')
    return result.stdout + result.stderr if combined else result.stdout


def save(**values):
    state = read_state()
    state.update(values)
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    (ROOT / 'state.json').write_text(json.dumps(state))


def read_state():
    path = ROOT / 'state.json'
    return json.loads(path.read_text()) if path.exists() else {}


def testers():
    try:
        rows = json.loads(require('TESTFLIGHT_TESTERS_JSON'))
        if not isinstance(rows, list) or not 1 <= len(rows) <= 10000:
            raise ValueError()
        unique = {}
        for row in rows:
            if not isinstance(row, dict) or set(row) - {'email', 'firstName', 'lastName'}:
                raise ValueError()
            if not all(isinstance(row.get(k), str) and row[k].strip()
                       for k in ('email', 'firstName', 'lastName')):
                raise ValueError()
            if not re.fullmatch(r'[^\s@,]+@[^\s@,]+\.[^\s@,]+', row['email']):
                raise ValueError()
            if any(any(ord(c) < 32 for c in v) for v in row.values()):
                raise ValueError()
            unique[row['email'].casefold()] = row
        return list(unique.values())
    except (ValueError, TypeError):
        raise SafeError('Invalid TESTFLIGHT_TESTERS_JSON; values suppressed') from None


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=')


def raw_signature(der):
    # OpenSSL ES256 signatures are DER; JWT requires fixed-width R || S.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise SafeError('Invalid signing response')
    pos, parts = 2, []
    for _ in range(2):
        if der[pos] != 2:
            raise SafeError('Invalid signing response')
        size = der[pos + 1]
        value = der[pos + 2:pos + 2 + size].lstrip(b'\0')
        if not 1 <= len(value) <= 32:
            raise SafeError('Invalid signing response')
        parts.append(value.rjust(32, b'\0'))
        pos += 2 + size
    if pos != len(der):
        raise SafeError('Invalid signing response')
    return b''.join(parts)


def token():
    now = int(time.time())
    header = {'alg': 'ES256', 'kid': require('ASC_KEY_ID'), 'typ': 'JWT'}
    payload = {'iss': require('ASC_ISSUER_ID'), 'iat': now - 30,
               'exp': now + 600, 'aud': 'appstoreconnect-v1'}
    message = b'.'.join(b64(json.dumps(x).encode()) for x in (header, payload))
    signature = run(['openssl', 'dgst', '-sha256', '-sign', str(ROOT / 'AuthKey.p8')], data=message)
    return (message + b'.' + b64(raw_signature(signature))).decode()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class API:
    def request(self, method, path, body=None, params=None):
        url = path if path.startswith('https://') else BASE + path
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != 'https' or parsed.netloc != 'api.appstoreconnect.apple.com':
            raise SafeError('Refused unexpected API host')
        if params:
            url += '?' + urllib.parse.urlencode(params)
        for attempt in range(5):
            req = urllib.request.Request(url, method=method,
                data=None if body is None else json.dumps(body).encode(),
                headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
            try:
                with urllib.request.build_opener(NoRedirect).open(req, timeout=60) as response:
                    data = response.read()
                    return json.loads(data) if data else {}
            except urllib.error.HTTPError as error:
                # Never include URL/query, response body, email, names, or tokens.
                if method == 'GET' and (error.code == 429 or error.code >= 500) and attempt < 4:
                    time.sleep(min(30, 2 ** attempt * 2))
                    continue
                raise SafeError(f'App Store Connect {method} failed (HTTP {error.code}); details suppressed') from None
            except (urllib.error.URLError, TimeoutError):
                if method == 'GET' and attempt < 4:
                    time.sleep(2 ** attempt)
                    continue
                # Mutations are not blindly retried: Apple may already have accepted them.
                raise SafeError('App Store Connect connection failed; reconcile remote state before retrying') from None
        raise SafeError('App Store Connect request exhausted retries')

    def all(self, path, params=None):
        result = []
        while path:
            page = self.request('GET', path, params=params)
            result.extend(page['data'])
            path, params = page.get('links', {}).get('next'), None
        return result


def linkage(kind, identifier):
    return {'type': kind, 'id': identifier}


def number_tuple(value):
    if not re.fullmatch(r'\d{1,4}(\.\d{1,2}){0,2}', value):
        raise SafeError('Existing build number has unsupported format; manual reconciliation required')
    parts = [int(p) for p in value.split('.')]
    return tuple(parts + [0] * (3 - len(parts)))


def allocate(existing, reserved=()):
    # Owner-requested integer sequence, independent of the earlier dotted
    # sequence. Apple still validates whether it accepts a lower build number.
    for value in existing:
        number_tuple(value)
    candidate = max([20] + [int(value) for value in reserved]) + 1
    uploaded = {number_tuple(value) for value in existing}
    while number_tuple(str(candidate)) in uploaded:
        candidate += 1
    if candidate > 9999:
        raise SafeError('Integer build number range exhausted')
    return str(candidate)


def prepare():
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(ROOT, 0o700)
    save(version=VERSION, preparation='started')
    group_name = require('TESTFLIGHT_GROUP_NAME')
    if len(group_name) > 100 or any(ord(c) < 32 for c in group_name) or '@' in group_name:
        raise SafeError('Use a group name without contact information or control characters')
    rows = testers()
    key_id = require('ASC_KEY_ID')
    if not re.fullmatch(r'[A-Za-z0-9]+', key_id):
        raise SafeError('Invalid ASC_KEY_ID format')
    uuid.UUID(require('ASC_ISSUER_ID'))
    (ROOT / 'AuthKey.p8').write_text(require('ASC_PRIVATE_KEY'))
    api = API()
    apps = api.all('/v1/apps', {'filter[bundleId]': BUNDLE})
    if len(apps) != 1:
        raise SafeError('Expected exactly one existing App Store Connect app for the repository bundle ID')
    app = apps[0]['id']
    groups = api.all(f'/v1/apps/{app}/betaGroups')
    matches = [g for g in groups if g['attributes']['name'] == group_name]
    if len(matches) != 1 or matches[0]['attributes']['isInternalGroup']:
        raise SafeError('Configure exactly one existing external TestFlight group for this app')
    builds = api.all('/v1/builds', {'filter[app]': app,
                    'filter[preReleaseVersion.version]': VERSION, 'limit': 200})
    existing = [b['attributes']['version'] for b in builds]
    if os.environ.get('GH_TOKEN'):
        from reservations import GitHub, identity, reserve
        github = GitHub()
        github.initialise()
        configuration = {'app': app, 'group_id': matches[0]['id'], 'group_name': group_name,
                         'version': VERSION, 'configured_testers': len(rows)}
        reservation = github.change(lambda ledger: reserve(ledger, existing, identity(),
            require('GITHUB_RUN_ID'), require('GITHUB_RUN_ATTEMPT'), require('GITHUB_SHA'), configuration))
        if reservation['status'] != 'building':
            raise SafeError('This attempt already has a reservation; rerun all jobs with a new attempt')
        build = reservation['build']
        save(reservation_id=reservation['id'], source_sha=reservation['sha'])
    else:
        raise SafeError('Persistent GitHub reservation credentials are required')
    save(app=app, group_id=matches[0]['id'], group_name=group_name, build=build,
         configured_testers=len(rows), preparation='passed')
    print(f'Configuration validated; marketing version {VERSION}, build {build}')


def reserved_metadata():
    from reservations import GitHub, identity
    ledger, _ = GitHub().load()
    row = next((r for r in ledger['reservations'] if r['id'] == identity()), None)
    if not row or not isinstance(row.get('metadata'), dict):
        raise SafeError('Reserved metadata is missing; dispatch a new run with the updated workflow')
    metadata = row['metadata']
    fields = {'app', 'group_id', 'group_name', 'build', 'version', 'configured_testers',
              'reservation_id', 'source_sha', 'preparation'}
    if set(metadata) != fields:
        raise SafeError('Reserved metadata has an unexpected schema')
    if (metadata['version'], metadata['source_sha'], metadata['reservation_id'], metadata['build']) != (
            VERSION, require('GITHUB_SHA'), identity(), row['build']):
        raise SafeError('Reserved metadata revision, version, attempt or build mismatch')
    return metadata


def initialise_build():
    metadata = reserved_metadata()
    save(**metadata)



def package():
    # Encrypt and authenticate only the IPA and sanitized build metadata.
    import hashlib
    import hmac
    import zipfile
    state = read_state()
    metadata = {k: state[k] for k in ('app', 'group_id', 'group_name', 'build', 'version',
        'configured_testers', 'reservation_id', 'source_sha', 'preparation', 'archive', 'export')}
    metadata['ipa_sha256'] = hashlib.sha256(Path(state['ipa']).read_bytes()).hexdigest()
    plain = ROOT / 'transfer.zip'
    with zipfile.ZipFile(plain, 'w', zipfile.ZIP_STORED) as archive:
        archive.writestr('metadata.json', json.dumps(metadata))
        archive.write(state['ipa'], 'app.ipa')
    require('KEYCHAIN_PASSWORD')
    cipher = ROOT / 'transfer.enc'
    run(['openssl', 'enc', '-aes-256-cbc', '-pbkdf2', '-iter', '200000', '-salt',
         '-pass', 'env:KEYCHAIN_PASSWORD', '-in', str(plain), '-out', str(cipher)], timeout=300)
    salt = os.urandom(32)
    key = hashlib.pbkdf2_hmac('sha256', require('KEYCHAIN_PASSWORD').encode(), salt, 200000)
    ciphertext = cipher.read_bytes()
    tag = hmac.new(key, b'TFIPA1' + salt + ciphertext, hashlib.sha256).digest()
    (ROOT / 'ipa.bundle').write_bytes(b'TFIPA1' + salt + tag + ciphertext)
    save(transfer='encrypted and authenticated')


def restore():
    import hashlib
    import hmac
    import zipfile
    expected = reserved_metadata()
    data = (ROOT / 'ipa.bundle').read_bytes()
    if len(data) < 86 or data[:6] != b'TFIPA1':
        raise SafeError('Invalid encrypted IPA bundle')
    salt, tag, ciphertext = data[6:38], data[38:70], data[70:]
    key = hashlib.pbkdf2_hmac('sha256', require('KEYCHAIN_PASSWORD').encode(), salt, 200000)
    if not hmac.compare_digest(tag, hmac.new(key, b'TFIPA1' + salt + ciphertext, hashlib.sha256).digest()):
        raise SafeError('IPA bundle authentication failed')
    (ROOT / 'transfer.enc').write_bytes(ciphertext)
    run(['openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2', '-iter', '200000',
         '-pass', 'env:KEYCHAIN_PASSWORD', '-in', str(ROOT / 'transfer.enc'),
         '-out', str(ROOT / 'transfer.zip')], timeout=300)
    with zipfile.ZipFile(ROOT / 'transfer.zip') as archive:
        if sorted(archive.namelist()) != ['app.ipa', 'metadata.json']:
            raise SafeError('Unexpected IPA bundle contents')
        metadata = json.loads(archive.read('metadata.json'))
        if set(metadata) != set(expected) | {'archive', 'export', 'ipa_sha256'} or any(metadata.get(k) != v for k, v in expected.items()):
            raise SafeError('IPA bundle differs from the reserved build metadata')
        ipa = archive.read('app.ipa')
        if hashlib.sha256(ipa).hexdigest() != metadata['ipa_sha256']:
            raise SafeError('IPA checksum verification failed')
        (ROOT / 'app.ipa').write_bytes(ipa)
    save(**metadata, ipa=str(ROOT / 'app.ipa'), transfer='verified and decrypted')
    (ROOT / 'AuthKey.p8').write_text(require('ASC_PRIVATE_KEY'))


def signing_profile(profile):
    ent = profile['Entitlements']
    if profile['TeamIdentifier'] != [TEAM] or ent.get('application-identifier') != f'{TEAM}.{BUNDLE}':
        raise SafeError('Provisioning profile does not match the repository team and explicit bundle ID')
    if ent.get('get-task-allow', False) or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices'):
        raise SafeError('Expected an App Store Connect distribution profile')
    if profile['ExpirationDate'].replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
        raise SafeError('Provisioning profile is expired')
    uuid.UUID(profile['UUID'])
    return profile['UUID']


def build():
    save(archive='started')
    state = read_state()
    keychain = ROOT / 'ci.keychain-db'
    password = require('KEYCHAIN_PASSWORD')
    cert = ROOT / 'distribution.p12'
    profile_path = ROOT / 'distribution.mobileprovision'
    cert.write_bytes(base64.b64decode(''.join(require('BUILD_CERTIFICATE_BASE64').split()), validate=True))
    profile_path.write_bytes(base64.b64decode(''.join(require('PROVISIONING_PROFILE_BASE64').split()), validate=True))
    profile = plistlib.loads(run(['security', 'cms', '-D', '-i', str(profile_path)]))
    profile_id = signing_profile(profile)
    install = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles' / (profile_id + '.mobileprovision')
    install.parent.mkdir(parents=True, exist_ok=True)
    if install.exists():
        raise SafeError('Refusing to overwrite an existing provisioning profile')
    save(installed_profile=str(install))
    shutil.copyfile(profile_path, install)
    run(['security', 'create-keychain', '-p', password, str(keychain)])
    run(['security', 'set-keychain-settings', '-lut', '21600', str(keychain)])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    run(['security', 'import', str(cert), '-P', require('P12_PASSWORD'), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain)])
    run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain)])
    original = run(['security', 'list-keychains', '-d', 'user']).decode()
    original_paths = re.findall(r'"([^"]+)"', original)
    save(original_keychains=original_paths)
    run(['security', 'list-keychains', '-d', 'user', '-s', str(keychain), *original_paths])
    identities = run(['security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)]).decode()
    identities = re.findall(r'([A-Fa-f0-9]{40}) "Apple Distribution[^"\n]*"', identities)
    if len(identities) != 1:
        raise SafeError('Expected exactly one valid Apple Distribution signing identity')
    identity = identities[0]
    # Ensure the imported signing identity is authorized by this exact profile.
    import hashlib
    fingerprints = {hashlib.sha1(c).hexdigest().upper() for c in profile['DeveloperCertificates']}
    if identity.upper() not in fingerprints:
        raise SafeError('Signing certificate is not included in the provisioning profile')
    options = {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
               'teamID': TEAM, 'signingCertificate': identity,
               'provisioningProfiles': {BUNDLE: profile_id},
               'manageAppVersionAndBuildNumber': False, 'testFlightInternalTestingOnly': False,
               'stripSwiftSymbols': True, 'uploadSymbols': True}
    export = ROOT / 'ExportOptions.plist'
    export.write_bytes(plistlib.dumps(options))
    archive = ROOT / 'DontSmoke.xcarchive'
    run(['xcodebuild', '-project', 'DontSmoke.xcodeproj', '-scheme', 'DontSmoke',
         '-configuration', 'Release', '-destination', 'generic/platform=iOS',
         '-derivedDataPath', str(ROOT / 'DerivedData'), '-archivePath', str(archive),
         f'MARKETING_VERSION={VERSION}', f'CURRENT_PROJECT_VERSION={state["build"]}',
         'CODE_SIGN_STYLE=Manual', f'CODE_SIGN_IDENTITY={identity}',
         f'DEVELOPMENT_TEAM={TEAM}', f'PROVISIONING_PROFILE_SPECIFIER={profile_id}',
         f'OTHER_CODE_SIGN_FLAGS=--keychain {keychain}', 'archive'], timeout=2400)
    save(archive='succeeded', export='started')
    run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
         '-exportOptionsPlist', str(export), '-exportPath', str(ROOT / 'export')], timeout=900)
    ipas = list((ROOT / 'export').glob('*.ipa'))
    if len(ipas) != 1:
        raise SafeError('Expected one exported IPA')
    import zipfile
    with zipfile.ZipFile(ipas[0]) as ipa:
        paths = [p for p in ipa.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', p)]
        if len(paths) != 1:
            raise SafeError('Unexpected IPA application layout')
        info = plistlib.loads(ipa.read(paths[0]))
    if (info['CFBundleIdentifier'], info['CFBundleShortVersionString'], info['CFBundleVersion']) != (BUNDLE, VERSION, state['build']):
        raise SafeError('Exported IPA bundle ID or version differs from the requested build')
    save(export='succeeded', ipa=str(ipas[0]))
    print('Signed archive and IPA export succeeded; exported version verified')


def upload():
    save(upload='started')
    keydir = ROOT / 'private_keys'
    keydir.mkdir(mode=0o700, exist_ok=True)
    shutil.copyfile(ROOT / 'AuthKey.p8', keydir / f'AuthKey_{require("ASC_KEY_ID")}.p8')
    os.environ['API_PRIVATE_KEYS_DIR'] = str(keydir)
    result = run(['xcrun', 'altool', '--upload-package', read_state()['ipa'],
         '--api-key', require('ASC_KEY_ID'), '--api-issuer', require('ASC_ISSUER_ID')], timeout=1800, combined=True)
    if b'UPLOAD SUCCEEDED' not in result and b'No errors uploading' not in result:
        save(upload='tool exited successfully; awaiting Apple build confirmation')
    else:
        save(upload='accepted; processing not yet confirmed')
    print('Upload tool completed; Apple processing will confirm the exact build')


def wait_build(api, state, seconds=5400):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        builds = api.all('/v1/builds', {'filter[app]': state['app'],
                 'filter[version]': state['build'], 'filter[preReleaseVersion.version]': VERSION})
        if len(builds) > 1:
            raise SafeError('Uploaded build lookup is ambiguous')
        if builds:
            build = builds[0]
            status = build['attributes']['processingState']
            if status == 'VALID':
                app = api.request('GET', f'/v1/builds/{build["id"]}/app')['data']
                release = api.request('GET', f'/v1/builds/{build["id"]}/preReleaseVersion')['data']['attributes']
                if (app['id'], release['version'], release['platform'], build['attributes']['version']) != (state['app'], VERSION, 'IOS', state['build']):
                    raise SafeError('Processed build does not match the exact app, platform, marketing version and build number')
                if build['attributes'].get('expired'):
                    raise SafeError('Uploaded build has expired')
                save(processing='VALID', build_id=build['id'], upload='accepted; processed build confirmed')
                return build['id']
            if status in ('FAILED', 'INVALID'):
                save(processing=status)
                raise SafeError('Apple processing failed')
        save(processing='waiting for Apple')
        time.sleep(30)
    save(processing='timed out; upload may still be processing')
    raise SafeError('Apple processing timed out; do not assume the upload failed')


def distribute():
    save(distribution='started')
    api, state = API(), read_state()
    build_id = wait_build(api, state)
    group_id = state['group_id']
    details = api.request('GET', f'/v1/builds/{build_id}/buildBetaDetail')['data']
    detail_id = details['id']
    api.request('PATCH', f'/v1/buildBetaDetails/{detail_id}', {'data': {
        **linkage('buildBetaDetails', detail_id), 'attributes': {'autoNotifyEnabled': True}}})
    # Build-specific testing instructions, not production App Store metadata.
    localizations = api.all(f'/v1/builds/{build_id}/betaBuildLocalizations')
    existing_locale = next((x for x in localizations if x['attributes']['locale'] == 'en-US'), None)
    if existing_locale:
        api.request('PATCH', f'/v1/betaBuildLocalizations/{existing_locale["id"]}', {'data': {
            **linkage('betaBuildLocalizations', existing_locale['id']),
            'attributes': {'whatsNew': 'Please test onboarding, quit progress, craving rescue, and reminders.'}}})
    else:
        api.request('POST', '/v1/betaBuildLocalizations', {'data': {
            'type': 'betaBuildLocalizations', 'attributes': {'locale': 'en-US',
            'whatsNew': 'Please test onboarding, quit progress, craving rescue, and reminders.'},
            'relationships': {'build': {'data': linkage('builds', build_id)}}}})
    external = details['attributes']['externalBuildState']
    if external == 'READY_FOR_BETA_SUBMISSION':
        api.request('POST', '/v1/betaAppReviewSubmissions', {'data': {
            'type': 'betaAppReviewSubmissions',
            'relationships': {'build': {'data': linkage('builds', build_id)}}}})
        external = 'BETA_REVIEW_REQUESTED'
    elif external in ('PROCESSING', 'PROCESSING_EXCEPTION', 'MISSING_EXPORT_COMPLIANCE', 'IN_BETA_TESTING', 'BETA_REJECTED', 'EXPIRED'):
        if external != 'IN_BETA_TESTING':
            save(beta_review='blocked; check App Store Connect')
            raise SafeError('External testing requires action in App Store Connect')
    elif external not in ('WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW', 'BETA_APPROVED', 'READY_FOR_BETA_TESTING'):
        raise SafeError('Unknown external testing state; check App Store Connect')
    save(beta_review=external)
    api.request('POST', f'/v1/betaGroups/{group_id}/relationships/builds',
                {'data': [linkage('builds', build_id)]})
    linked = api.all(f'/v1/betaGroups/{group_id}/builds')
    if not any(b['id'] == build_id for b in linked):
        raise SafeError('Group build assignment was not confirmed')
    save(group='build assignment confirmed')
    members = {t['id'] for t in api.all(f'/v1/betaGroups/{group_id}/betaTesters')}
    created, added, invited, existing_count = 0, 0, 0, 0
    save(testers_created=0, testers_existing=0, testers_added=0, invitations_requested=0)
    for row in testers():
        found = api.all('/v1/betaTesters', {'filter[email]': row['email']})
        if len(found) > 1:
            raise SafeError('Ambiguous tester lookup; identities suppressed')
        if found:
            tester = found[0]
            existing_count += 1
        else:
            tester = api.request('POST', '/v1/betaTesters', {'data': {
                'type': 'betaTesters', 'attributes': row,
                'relationships': {'betaGroups': {'data': [linkage('betaGroups', group_id)]}}}})['data']
            created += 1
            members.add(tester['id'])
            added += 1
        tester_id = tester['id']
        if tester_id not in members:
            api.request('POST', f'/v1/betaGroups/{group_id}/relationships/betaTesters',
                        {'data': [linkage('betaTesters', tester_id)]})
            added += 1
        save(testers_created=created, testers_existing=existing_count,
             testers_added=added, invitations_requested=invited)
        if external in ('BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'):
            tester = api.request('GET', f'/v1/betaTesters/{tester_id}')['data']
        if external in ('BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING') and tester['attributes'].get('state') == 'NOT_INVITED':
            api.request('POST', '/v1/betaTesterInvitations', {'data': {
                'type': 'betaTesterInvitations', 'relationships': {
                    'app': {'data': linkage('apps', state['app'])},
                    'betaTester': {'data': linkage('betaTesters', tester_id)}}}})
            invited += 1
        save(testers_created=created, testers_existing=existing_count,
             testers_added=added, invitations_requested=invited)
    confirmed = {t['id'] for t in api.all(f'/v1/betaGroups/{group_id}/betaTesters')}
    # Verify every configured tester rather than assuming writes succeeded.
    for row in testers():
        found = api.all('/v1/betaTesters', {'filter[email]': row['email']})
        if len(found) != 1 or found[0]['id'] not in confirmed:
            raise SafeError('Tester membership verification failed; identities suppressed')
    details = api.request('GET', f'/v1/builds/{build_id}/buildBetaDetail')['data']['attributes']
    final_state = details['externalBuildState']
    approved = final_state in ('BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING')
    if not approved and final_state not in ('READY_FOR_BETA_SUBMISSION', 'WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW'):
        raise SafeError('External testing state changed during distribution; check App Store Connect')
    result = 'configured; Apple approved' if approved else 'configured; pending Apple Beta App Review'
    if final_state == 'IN_BETA_TESTING':
        result = 'configured; IN_BETA_TESTING confirmed'
    save(distribution=result,
         invitations='Apple requests accepted; delivery and acceptance not verified' if approved else
                     'deferred until Beta App Review approval; automatic notification enabled',
         testers_verified=len(testers()), beta_review=details['externalBuildState'])
    print('External group and tester membership verified; see summary for Apple review status')


def summary():
    state = read_state()
    rows = [('Job', os.environ.get('TF_JOB_STATUS', 'unknown')),
            ('Marketing version', VERSION), ('Build number', state.get('build', 'not assigned'))]
    for label, key in [('Reservation', 'reservation_id'), ('Reservation status', 'reservation_status'), ('Submission queue', 'queue'), ('IPA transfer', 'transfer'), ('Preflight', 'preparation'), ('Archive', 'archive'), ('IPA export', 'export'),
                       ('Upload', 'upload'), ('Apple processing', 'processing'), ('External group', 'group_name'),
                       ('Group assignment', 'group'), ('Beta App Review', 'beta_review'),
                       ('Distribution', 'distribution'), ('Invitations', 'invitations'),
                       ('Configured testers (unique)', 'configured_testers'), ('Created', 'testers_created'),
                       ('Existing', 'testers_existing'), ('Added to group', 'testers_added'),
                       ('Memberships verified', 'testers_verified'), ('Explicit invitation requests', 'invitations_requested'),
                       ('Credential cleanup', 'cleanup'), ('Failure', 'failure')]:
        rows.append((label, state.get(key, 'not completed')))
    def escape(value):
        return html.escape(str(value)).replace('|', '&#124;').replace('\n', ' ')
    content = '## External TestFlight POC\n\n| Item | Result |\n|---|---|\n'
    content += ''.join(f'| {label} | {escape(value)} |\n' for label, value in rows)
    content += '\nNo production App Store release was submitted. Apple review approval, email delivery, and tester acceptance are separate from successful configuration.\n'
    with open(require('GITHUB_STEP_SUMMARY'), 'a') as output:
        output.write(content)


def cleanup():
    state = read_state()
    failed = False
    actions = []
    if 'original_keychains' in state:
        actions.append(lambda: run(['security', 'list-keychains', '-d', 'user', '-s', *state['original_keychains']]))
    keychain = ROOT / 'ci.keychain-db'
    if keychain.exists():
        actions.append(lambda: run(['security', 'delete-keychain', str(keychain)]))
    if state.get('installed_profile'):
        actions.append(lambda: Path(state['installed_profile']).unlink(missing_ok=True))
    # Retain only sanitized summary state until the next step writes the summary.
    for path in ROOT.iterdir() if ROOT.exists() else []:
        if path.name != 'state.json':
            actions.append(lambda path=path: shutil.rmtree(path) if path.is_dir() else path.unlink(missing_ok=True))
    for action in actions:
        try:
            action()
        except Exception:
            failed = True
    save(cleanup='failed; some temporary resources may remain' if failed else 'completed')
    if failed:
        raise SafeError('Temporary resource cleanup failed; raw details suppressed')
    print('Temporary credentials and build products removed')


if __name__ == '__main__':
    os.umask(0o077)
    commands = {f.__name__: f for f in (prepare, initialise_build, build, package, restore, upload, distribute, summary, cleanup)}
    try:
        commands[sys.argv[1]]()
    except Exception as error:
        message = str(error) if isinstance(error, SafeError) else 'Operation failed; sensitive diagnostic details suppressed'
        if sys.argv[1] not in ('cleanup', 'summary'):
            save(failure=message)
        print('ERROR: ' + sys.argv[1] + ': ' + message, file=sys.stderr)
        sys.exit(1)
