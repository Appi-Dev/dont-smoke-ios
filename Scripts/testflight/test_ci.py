"""Offline safety tests. All identities are synthetic; no Apple requests are made."""
import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location('ci', Path(__file__).with_name('ci.py'))
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
ROW = {'email': 'synthetic@example.invalid', 'firstName': 'Synthetic', 'lastName': 'Fixture'}


class FakeAPI:
    def __init__(self, external='READY_FOR_BETA_SUBMISSION', existing=False):
        self.external = external
        self.tester = {'id': 'tester-fixture', 'attributes': {**ROW, 'state': 'NOT_INVITED'}} if existing else None
        self.members = []
        self.builds = []
        self.calls = []
        self.groups = []

    def all(self, path, params=None):
        self.calls.append(('GET', path, params))
        if path.endswith('/betaGroups'):
            return self.groups
        if path == '/v1/builds':
            return [{'id': 'build-fixture', 'attributes': {'processingState': 'VALID', 'version': '9000.1.1'}}]
        if path.endswith('/betaBuildLocalizations'):
            return []
        if path == '/v1/betaTesters':
            return [self.tester] if self.tester else []
        if path.endswith('/betaTesters'):
            return self.members
        if path.endswith('/builds'):
            return self.builds
        raise AssertionError(path)

    def request(self, method, path, body=None, params=None):
        self.calls.append((method, path, body))
        if path.endswith('/app'):
            return {'data': {'id': 'app-fixture'}}
        if path.endswith('/preReleaseVersion'):
            return {'data': {'attributes': {'version': ci.VERSION, 'platform': 'IOS'}}}
        if method == 'GET' and path == '/v1/betaTesters/tester-fixture':
            return {'data': self.tester}
        if path.endswith('/buildBetaDetail'):
            return {'data': {'id': 'detail-fixture', 'attributes': {'externalBuildState': self.external, 'autoNotifyEnabled': True}}}
        if method == 'POST' and path == '/v1/betaGroups':
            self.groups.append({'id': 'group-fixture', 'attributes': {**body['data']['attributes'], 'hasAccessToAllBuilds': False}})
        if path.endswith('/relationships/builds'):
            self.builds = body['data']
        elif path == '/v1/betaAppReviewSubmissions':
            self.external = 'WAITING_FOR_BETA_REVIEW'
        elif path == '/v1/betaTesters':
            self.tester = {'id': 'tester-fixture', 'attributes': {**body['data']['attributes'], 'state': 'NOT_INVITED'}}
            self.members.append(self.tester)
            return {'data': self.tester}
        elif path.endswith('/relationships/betaTesters'):
            self.members.append(self.tester)
        elif path == '/v1/betaTesterInvitations':
            self.tester['attributes']['state'] = 'INVITED'
        return {}


class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = patch.object(ci, 'ROOT', Path(self.temp.name))
        self.root.start()
        self.env = patch.dict(os.environ, {'TESTFLIGHT_TESTERS_JSON': json.dumps([ROW]),
                     'GITHUB_STEP_SUMMARY': str(Path(self.temp.name) / 'summary.md')})
        self.env.start()
        ci.save(app='app-fixture', group_id='group-fixture', group_name='External QA', build='9000.1.1')

    def tearDown(self):
        self.env.stop()
        self.root.stop()
        self.temp.cleanup()

    def distribute(self, api):
        with patch.object(ci, 'API', return_value=api), contextlib.redirect_stdout(io.StringIO()):
            ci.distribute()

    def test_integer_build_numbers_increase_sequentially(self):
        self.assertEqual(ci.allocate([]), '21')
        reserved = []
        for expected in ('21', '22', '23'):
            result = ci.allocate(['20', '9000.1.2'], reserved)
            self.assertEqual(result, expected)
            reserved.append(result)
        self.assertEqual(ci.allocate(['21', '21.0', '22', '9001']), '23')
        self.assertEqual(ci.allocate([], ['23', '21', '22']), '24')
        with self.assertRaises(ci.SafeError):
            ci.allocate([], ['9999'])
        with self.assertRaises(ci.SafeError):
            ci.allocate(['invalid'])

    def test_testers_validate_and_deduplicate_without_logging_values(self):
        with patch.dict(os.environ, {'TESTFLIGHT_TESTERS_JSON': json.dumps([ROW, ROW])}):
            self.assertEqual(len(ci.testers()), 1)
        for bad in ('not-json', '{}', '[]', '[{"email":"sensitive"}]'):
            with patch.dict(os.environ, {'TESTFLIGHT_TESTERS_JSON': bad}), self.assertRaises(ci.SafeError) as error:
                ci.testers()
            self.assertNotIn('sensitive', str(error.exception))

    def test_processing_failure_and_timeout(self):
        api = FakeAPI()
        with patch.object(api, 'all', return_value=[{'id': 'fixture', 'attributes': {'processingState': 'INVALID'}}]):
            with self.assertRaises(ci.SafeError):
                ci.wait_build(api, ci.read_state())
        self.assertEqual(ci.read_state()['processing'], 'INVALID')
        with patch.object(ci.time, 'monotonic', side_effect=[0, 2]):
            with self.assertRaises(ci.SafeError):
                ci.wait_build(api, ci.read_state(), seconds=1)
        self.assertIn('timed out', ci.read_state()['processing'])

    def test_wrong_processed_build_is_rejected(self):
        api = FakeAPI()
        with patch.object(api, 'all', return_value=[{'id': 'fixture', 'attributes': {'processingState': 'VALID', 'version': 'wrong'}}]):
            with self.assertRaises(ci.SafeError):
                ci.wait_build(api, ci.read_state())

    def test_existing_invited_tester_does_not_get_duplicate_invitation(self):
        api = FakeAPI('IN_BETA_TESTING', existing=True)
        api.tester['attributes']['state'] = 'INVITED'
        api.members = [api.tester]
        self.distribute(api)
        self.assertEqual(ci.read_state()['invitations_requested'], 0)
        self.assertEqual(ci.read_state()['testers_added'], 0)

    def test_only_explicit_apple_error_codes_are_extracted(self):
        output = (b'ERROR ITMS-90382: private message\nERROR: 90034 private text\n'
                  b'ERROR: private upload failed (90161)\nITMS-90382\n'
                  b'email=12345@example.invalid build=90001 token=54321\n'
                  b'ITMS-123456 ERROR: 987654')
        self.assertEqual(ci.apple_error_codes(output), ['90034', '90161', '90382'])
        self.assertEqual(ci.apple_error_codes(b'private text 90382'), [])

    def test_upload_failure_reports_codes_and_keeps_payload_private(self):
        ci.save(ipa='fixture.ipa')
        (ci.ROOT / 'AuthKey.p8').write_text('synthetic-key')
        result = subprocess.CompletedProcess([], 1, b'ERROR ITMS-90382: private-email private-token',
                                             b'ERROR: private-path (90161)')
        with patch.dict(os.environ, {'ASC_KEY_ID': 'FIXTURE', 'ASC_ISSUER_ID': 'fixture'}), patch.object(ci.subprocess, 'run', return_value=result):
            with self.assertRaises(ci.SafeError) as caught:
                ci.upload()
        ci.summary()
        text = str(caught.exception) + (ci.ROOT / 'state.json').read_text() + (ci.ROOT / 'summary.md').read_text()
        self.assertIn('Apple error codes: 90161, 90382', text)
        for value in ('private-email', 'private-token', 'private-path', 'synthetic-key'):
            self.assertNotIn(value, text)
        self.assertIn('failed', ci.read_state()['upload'])

    def test_unrecognized_tool_error_stays_suppressed(self):
        result = subprocess.CompletedProcess([], 1, b'private data 90382', b'private stderr')
        with patch.object(ci.subprocess, 'run', return_value=result):
            with self.assertRaises(ci.SafeError) as caught:
                ci.run(['xcrun'], report_apple_codes=True)
        self.assertNotIn('90382', str(caught.exception))
        self.assertNotIn('private', str(caught.exception))

    def test_upload_timeout_does_not_expose_captured_output(self):
        ci.save(ipa='fixture.ipa')
        (ci.ROOT / 'AuthKey.p8').write_text('synthetic-key')
        error = subprocess.TimeoutExpired(['private-command'], 1800, output=b'private-output', stderr=b'private-stderr')
        with patch.dict(os.environ, {'ASC_KEY_ID': 'FIXTURE', 'ASC_ISSUER_ID': 'fixture'}), patch.object(ci.subprocess, 'run', side_effect=error):
            with self.assertRaises(ci.SafeError) as caught:
                ci.upload()
        self.assertNotIn('private-', str(caught.exception) + (ci.ROOT / 'state.json').read_text())
        self.assertIn('may have received', ci.read_state()['upload'])

    def test_unconfirmed_upload_is_not_reported_as_accepted(self):
        ci.save(ipa='fixture.ipa')
        (ci.ROOT / 'AuthKey.p8').write_text('synthetic-key')
        with patch.dict(os.environ, {'ASC_KEY_ID': 'FIXTURE', 'ASC_ISSUER_ID': 'fixture'}), patch.object(ci, 'run', return_value=b'Unconfirmed tool response'):
            ci.upload()
        self.assertNotIn('accepted', ci.read_state()['upload'])

    def test_processing_waits_until_valid(self):
        api = FakeAPI()
        results = [[], [{'id': 'fixture', 'attributes': {'processingState': 'PROCESSING'}}],
                   [{'id': 'fixture', 'attributes': {'processingState': 'VALID', 'version': '9000.1.1'}}]]
        with patch.object(api, 'all', side_effect=results), patch.object(ci.time, 'sleep') as sleep:
            self.assertEqual(ci.wait_build(api, ci.read_state()), 'fixture')
            self.assertEqual(sleep.call_count, 2)

    def test_pending_review_creates_testers_and_defers_invitations(self):
        api = FakeAPI()
        self.distribute(api)
        state = ci.read_state()
        self.assertEqual(state['testers_created'], 1)
        self.assertEqual(state['testers_verified'], 1)
        self.assertIn('pending', state['distribution'])
        self.assertEqual(state['invitations_requested'], 0)
        mutations = [p for method, p, _ in api.calls if method != 'GET']
        self.assertIn('/v1/betaAppReviewSubmissions', mutations)
        self.assertFalse(any('appStoreVersion' in p or 'reviewSubmissions' in p for p in mutations))
        self.assertLess(mutations.index('/v1/betaAppReviewSubmissions'),
                        mutations.index('/v1/betaGroups/group-fixture/relationships/builds'))

    def test_existing_tester_is_reused_and_invited_when_ready(self):
        api = FakeAPI('READY_FOR_BETA_TESTING', existing=True)
        self.distribute(api)
        state = ci.read_state()
        self.assertEqual(state['testers_created'], 0)
        self.assertEqual(state['testers_existing'], 1)
        self.assertEqual(state['invitations_requested'], 1)
        self.assertEqual(state['testers_verified'], 1)

    def test_build_group_is_created_with_generated_name(self):
        api = FakeAPI()
        self.distribute(api)
        self.assertEqual(api.groups[0]['attributes']['name'], '9.0.0 (9000.1.1)')
        self.assertFalse(api.groups[0]['attributes']['isInternalGroup'])
        self.assertFalse(api.groups[0]['attributes']['publicLinkEnabled'])
        self.assertEqual(ci.read_state()['group_creation'], 'created')

    def test_matching_build_group_is_reused(self):
        api = FakeAPI()
        api.groups = [{'id': 'group-fixture', 'attributes': {
            'name': '9.0.0 (9000.1.1)', 'isInternalGroup': False,
            'publicLinkEnabled': False, 'hasAccessToAllBuilds': False}}]
        self.distribute(api)
        self.assertEqual(ci.read_state()['group_creation'], 'reused')
        self.assertFalse(any(m == 'POST' and p == '/v1/betaGroups' for m, p, _ in api.calls))

    def test_nullable_external_group_flags_allow_tester_assignment(self):
        for public, all_builds in ((False, None), (None, False), (None, None)):
            with self.subTest(public=public, all_builds=all_builds):
                api = FakeAPI(existing=True)
                api.groups = [{'id': 'group-fixture', 'attributes': {
                    'name': '9.0.0 (9000.1.1)', 'isInternalGroup': False,
                    'publicLinkEnabled': public, 'hasAccessToAllBuilds': all_builds,
                    'publicLink': None, 'publicLinkId': None}}]
                self.distribute(api)
                self.assertEqual(ci.read_state()['testers_added'], 1)
                self.assertEqual(ci.read_state()['testers_verified'], 1)

    def test_missing_safety_flags_fail_closed(self):
        for field in ('isInternalGroup', 'publicLinkEnabled', 'hasAccessToAllBuilds'):
            with self.subTest(field=field):
                api = FakeAPI()
                attributes = {'name': '9.0.0 (9000.1.1)', 'isInternalGroup': False,
                              'publicLinkEnabled': False, 'hasAccessToAllBuilds': False}
                del attributes[field]
                api.groups = [{'id': 'group-fixture', 'attributes': attributes}]
                with self.assertRaises(ci.SafeError):
                    self.distribute(api)

    def test_unsafe_or_ambiguous_groups_are_refused(self):
        for updates in ({'isInternalGroup': True}, {'publicLinkEnabled': True},
                        {'hasAccessToAllBuilds': True}, {'duplicate': True}, {'other_build': True},
                        {'publicLinkEnabled': None, 'publicLink': 'synthetic-link'},
                        {'publicLinkEnabled': None, 'publicLinkId': 'synthetic-id'},
                        {'publicLinkEnabled': 'false'}, {'isInternalGroup': None}):
            with self.subTest(updates=updates):
                api = FakeAPI()
                group = {'id': 'group-fixture', 'attributes': {
                    'name': '9.0.0 (9000.1.1)', 'isInternalGroup': False,
                    'publicLinkEnabled': False, 'hasAccessToAllBuilds': False, **updates}}
                api.groups = [group, group] if updates.get('duplicate') else [group]
                api.builds = [{'id': 'other-build'}] if updates.get('other_build') else []
                with self.assertRaises(ci.SafeError):
                    self.distribute(api)

    def test_unconfirmed_group_creation_fails_without_assignment(self):
        api = FakeAPI()
        original = api.request
        def request(method, path, body=None, params=None):
            if method == 'POST' and path == '/v1/betaGroups':
                return {}
            return original(method, path, body, params)
        with patch.object(api, 'request', side_effect=request), patch.object(ci.time, 'sleep'):
            with self.assertRaises(ci.SafeError):
                self.distribute(api)
        self.assertFalse(any(p.endswith('/relationships/builds') for _, p, _ in api.calls))

    def test_group_creation_conflict_is_reconciled_without_retry(self):
        api = FakeAPI()
        original = api.request
        def request(method, path, body=None, params=None):
            result = original(method, path, body, params)
            if method == 'POST' and path == '/v1/betaGroups':
                raise ci.APIError(method, 409)
            return result
        with patch.object(api, 'request', side_effect=request):
            self.distribute(api)
        self.assertEqual(ci.read_state()['group_creation'], 'reused after conflict')
        self.assertEqual(sum(m == 'POST' and p == '/v1/betaGroups' for m, p, _ in api.calls), 1)

    def test_concurrent_tester_creation_is_reused_without_retry(self):
        api = FakeAPI('IN_BETA_TESTING')
        original = api.request
        def request(method, path, body=None, params=None):
            result = original(method, path, body, params)
            if method == 'POST' and path == '/v1/betaTesters':
                raise ci.APIError(method, 409)
            return result
        with patch.object(api, 'request', side_effect=request):
            self.distribute(api)
        self.assertEqual(ci.read_state()['testers_created'], 0)
        self.assertEqual(ci.read_state()['testers_existing'], 1)
        self.assertEqual(sum(m == 'POST' and p == '/v1/betaTesters' for m, p, _ in api.calls), 1)

    def test_creation_conflict_without_matching_tester_fails(self):
        api = FakeAPI()
        original = api.request
        def request(method, path, body=None, params=None):
            if method == 'POST' and path == '/v1/betaTesters':
                raise ci.APIError(method, 422)
            return original(method, path, body, params)
        with patch.object(api, 'request', side_effect=request), patch.object(ci.time, 'sleep'):
            with self.assertRaises(ci.APIError):
                self.distribute(api)

    def test_concurrent_membership_and_invitation_are_confirmed(self):
        api = FakeAPI('IN_BETA_TESTING', existing=True)
        original = api.request
        def request(method, path, body=None, params=None):
            result = original(method, path, body, params)
            if method == 'POST' and (path.endswith('/relationships/betaTesters') or path == '/v1/betaTesterInvitations'):
                raise ci.APIError(method, 409)
            return result
        with patch.object(api, 'request', side_effect=request):
            self.distribute(api)
        self.assertEqual(ci.read_state()['testers_verified'], 1)
        self.assertEqual(ci.read_state()['invitations_requested'], 0)

    def test_rejected_review_does_not_invite_testers(self):
        api = FakeAPI('BETA_REJECTED')
        with self.assertRaises(ci.SafeError):
            self.distribute(api)
        self.assertFalse(any(p == '/v1/betaTesters' and m == 'POST' for m, p, _ in api.calls))

    def test_summary_and_state_exclude_tester_identities(self):
        self.distribute(FakeAPI())
        ci.summary()
        text = (ci.ROOT / 'summary.md').read_text() + (ci.ROOT / 'state.json').read_text()
        for value in (*ROW.values(), 'tester-fixture'):
            self.assertNotIn(value, text)
        self.assertIn('9000.1.1', text)
        self.assertIn('No production App Store release', text)

    def test_http_error_never_exposes_payload_or_query(self):
        error = urllib.error.HTTPError('https://api.appstoreconnect.apple.com/v1/betaTesters?email=sensitive',
                    422, 'sensitive', {}, io.BytesIO(b'sensitive'))
        with patch.object(ci, 'token', return_value='secret-token'), patch.object(ci.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = error
            with self.assertRaises(ci.SafeError) as caught:
                ci.API().request('POST', '/v1/betaTesters', {'sensitive': 'payload'})
        self.assertNotIn('sensitive', str(caught.exception))
        self.assertNotIn('secret-token', str(caught.exception))
        self.assertEqual(opener.return_value.open.call_count, 1)

    def test_unexpected_pagination_host_is_rejected(self):
        with self.assertRaises(ci.SafeError):
            ci.API().request('GET', 'https://unexpected.invalid/private')

    def test_profile_rejects_wrong_bundle_team_expiry_and_development(self):
        valid = {'TeamIdentifier': [ci.TEAM], 'UUID': '11111111-1111-1111-1111-111111111111',
                 'ExpirationDate': dt.datetime.now() + dt.timedelta(days=1),
                 'Entitlements': {'application-identifier': f'{ci.TEAM}.{ci.BUNDLE}', 'get-task-allow': False}}
        self.assertEqual(ci.signing_profile(valid), valid['UUID'])
        for updates in ({'TeamIdentifier': ['wrong']}, {'ProvisionedDevices': ['fixture']},
                        {'ExpirationDate': dt.datetime(2000, 1, 1)},
                        {'Entitlements': {'application-identifier': 'wrong'}}, {'ProvisionsAllDevices': True}):
            with self.assertRaises(ci.SafeError):
                ci.signing_profile({**valid, **updates})

    def test_cleanup_continues_after_keychain_restore_failure(self):
        key = ci.ROOT / 'AuthKey.p8'
        key.write_text('synthetic-private-key')
        (ci.ROOT / 'ci.keychain-db').touch()
        ci.save(original_keychains=['fixture'])
        with patch.object(ci, 'run', side_effect=[ci.SafeError('restore failed'), b'']) as runner:
            with self.assertRaises(ci.SafeError):
                ci.cleanup()
        self.assertFalse(key.exists())
        self.assertEqual(runner.call_count, 2)
        self.assertIn('failed', ci.read_state()['cleanup'])

    def test_jwt_signature_round_trip_using_synthetic_key(self):
        subprocess.run(['openssl', 'ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', str(ci.ROOT / 'AuthKey.p8')],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with patch.dict(os.environ, {'ASC_KEY_ID': 'FIXTURE', 'ASC_ISSUER_ID': '11111111-1111-1111-1111-111111111111'}):
            jwt = ci.token()
        header, payload, signature = jwt.split('.')
        import base64
        raw = base64.urlsafe_b64decode(signature + '=' * (-len(signature) % 4))
        self.assertEqual(len(raw), 64)
        integers = []
        for part in (raw[:32], raw[32:]):
            value = part.lstrip(b'\0') or b'\0'
            if value[0] & 128:
                value = b'\0' + value
            integers.append(b'\x02' + bytes([len(value)]) + value)
        der = b''.join(integers)
        (ci.ROOT / 'sig.der').write_bytes(b'\x30' + bytes([len(der)]) + der)
        subprocess.run(['openssl', 'pkey', '-in', str(ci.ROOT / 'AuthKey.p8'), '-pubout', '-out', str(ci.ROOT / 'public.pem')],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(ci.ROOT / 'public.pem'), '-signature', str(ci.ROOT / 'sig.der')],
                                input=(header + '.' + payload).encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
