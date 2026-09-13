"""Offline reservation, parallel submission, and encrypted transfer safety tests."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

# Match script imports without depending on unittest's discovery path setup.
sys.path.insert(0, str(Path(__file__).parent))
import ci
import reservations as queue


class ParallelTests(unittest.TestCase):
    def ledger(self):
        return {'schema': 1, 'reservations': []}

    def add(self, ledger, identifier, existing=None):
        return queue.reserve(ledger, existing or [], identifier, identifier.split('.')[0],
                             identifier.split('.')[1], 'a' * 40)

    def test_reservations_are_unique_before_apple_knows_builds(self):
        state = self.ledger()
        self.assertEqual(self.add(state, '1.1')['build'], '21')
        self.assertEqual(self.add(state, '2.1')['build'], '22')
        self.assertEqual(self.add(state, '3.1')['build'], '23')
        self.assertEqual(len(state['reservations']), 3)

    def test_generated_group_names_are_reserved_atomically(self):
        state = self.ledger()
        configuration = {'app': 'fixture', 'group_id': '', 'group_name': '',
                         'version': ci.VERSION, 'configured_testers': 1}
        for run, build in (('1', '21'), ('2', '22')):
            row = queue.reserve(state, [], run + '.1', run, '1', 'a' * 40, configuration)
            self.assertEqual(row['metadata']['group_name'], f'9.0.0 ({build})')
            self.assertEqual(row['metadata']['group_id'], '')

    def test_reserved_metadata_is_loaded_without_job_outputs(self):
        state = self.ledger()
        configuration = {'app': 'fixture', 'group_id': 'fixture-group', 'group_name': 'External QA',
                         'version': ci.VERSION, 'configured_testers': 1}
        queue.reserve(state, [], '1.1', '1', '1', 'a' * 40, configuration)
        api = queue.GitHub()
        env = {'GITHUB_RUN_ID': '1', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_SHA': 'a' * 40,
               'TF_METADATA': ''}
        with tempfile.TemporaryDirectory() as directory, patch.object(ci, 'ROOT', Path(directory)), patch.dict(os.environ, env), patch.object(queue, 'GitHub', return_value=api), patch.object(api, 'load', return_value=(state, 'sha')):
            ci.initialise_build()
            self.assertEqual(ci.read_state()['build'], '21')
            self.assertEqual(ci.read_state()['source_sha'], 'a' * 40)

    def test_missing_legacy_metadata_fails_with_recovery_guidance(self):
        state = self.ledger()
        self.add(state, '1.1')
        api = queue.GitHub()
        with patch.dict(os.environ, {'GITHUB_RUN_ID': '1', 'GITHUB_RUN_ATTEMPT': '1'}), patch.object(queue, 'GitHub', return_value=api), patch.object(api, 'load', return_value=(state, 'sha')):
            with self.assertRaises(ci.SafeError) as caught:
                ci.reserved_metadata()
            self.assertIn('dispatch a new run', str(caught.exception))

    def test_reserved_metadata_rejects_other_source_revisions(self):
        state = self.ledger()
        configuration = {'app': 'fixture', 'group_id': 'fixture-group', 'group_name': 'External QA',
                         'version': ci.VERSION, 'configured_testers': 1}
        queue.reserve(state, [], '1.1', '1', '1', 'a' * 40, configuration)
        api = queue.GitHub()
        with patch.dict(os.environ, {'GITHUB_RUN_ID': '1', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_SHA': 'b' * 40}), patch.object(queue, 'GitHub', return_value=api), patch.object(api, 'load', return_value=(state, 'sha')):
            with self.assertRaises(ci.SafeError):
                ci.reserved_metadata()

    def test_retry_does_not_duplicate_but_new_attempt_reserves_new_number(self):
        state = self.ledger()
        first = self.add(state, '1.1')
        self.assertEqual(self.add(state, '1.1'), first)
        self.assertEqual(len(state['reservations']), 1)
        self.assertEqual(self.add(state, '1.2')['build'], '22')

    def test_requested_integer_sequence_is_independent_of_dotted_uploads(self):
        state = self.ledger()
        self.assertEqual(self.add(state, '1.1', ['20', '9000.1.2'])['build'], '21')
        self.assertEqual(self.add(state, '2.1', ['20'])['build'], '22')

    def test_other_reservation_states_never_prevent_upload(self):
        for status in ('building', 'ready', 'uploading', 'blocked', 'completed', 'skipped'):
            with self.subTest(status=status):
                state = self.ledger()
                self.add(state, '1.1')
                self.add(state, '2.1')
                state['reservations'][0]['status'] = status
                queue.transition(state, '2.1', 'ready')
                self.assertEqual(queue.transition(state, '2.1', 'uploading')['status'], 'uploading')
                self.assertEqual(state['reservations'][0]['status'], status)

    def test_upload_claim_cannot_be_replayed(self):
        state = self.ledger()
        self.add(state, '1.1')
        queue.transition(state, '1.1', 'ready')
        queue.transition(state, '1.1', 'uploading')
        with self.assertRaises(ci.SafeError):
            queue.transition(state, '1.1', 'uploading')

    def test_recovery_refuses_a_still_running_originating_attempt(self):
        state = self.ledger()
        self.add(state, '1.1')
        queue.transition(state, '1.1', 'ready')
        queue.transition(state, '1.1', 'uploading')
        api = queue.GitHub()
        env = {'TF_RECOVERY_CONFIRMED': 'true', 'TF_RECOVERY_ID': '1.1',
               'TF_RECOVERY_RESOLUTION': 'completed', 'GITHUB_RUN_ID': 'recovery'}
        with patch.dict(os.environ, env), patch.object(queue, 'GitHub', return_value=api), patch.object(api, 'change', side_effect=lambda f: f(state)), patch.object(api, 'request', return_value={'status': 'in_progress'}):
            with self.assertRaises(ci.SafeError):
                queue.recover()
        self.assertEqual(state['reservations'][0]['status'], 'uploading')

    def test_recovery_advances_only_after_originating_attempt_has_finished(self):
        state = self.ledger()
        self.add(state, '1.1')
        self.add(state, '2.1')
        queue.transition(state, '1.1', 'ready')
        queue.transition(state, '1.1', 'uploading')
        api = queue.GitHub()
        env = {'TF_RECOVERY_CONFIRMED': 'true', 'TF_RECOVERY_ID': '1.1',
               'TF_RECOVERY_RESOLUTION': 'completed', 'GITHUB_RUN_ID': 'recovery'}
        with patch.dict(os.environ, env), patch.object(queue, 'GitHub', return_value=api), patch.object(api, 'change', side_effect=lambda f: f(state)), patch.object(api, 'request', return_value={'status': 'completed'}), patch.object(queue, 'save'):
            queue.recover()
        self.assertEqual(state['reservations'][1]['status'], 'building')
        self.assertEqual(state['reservations'][0]['recovered_by_run'], 'recovery')

    def test_failed_build_skips_but_number_is_never_reused(self):
        state = self.ledger()
        self.add(state, '1.1')
        queue.transition(state, '1.1', 'skipped')
        row = self.add(state, '2.1')
        self.assertEqual(row['build'], '22')
        self.assertEqual(state['reservations'][1]['status'], 'building')

    def test_uncertain_upload_cannot_be_automatically_skipped(self):
        state = self.ledger()
        self.add(state, '1.1')
        self.add(state, '2.1')
        queue.transition(state, '1.1', 'ready')
        queue.transition(state, '1.1', 'uploading')
        queue.transition(state, '1.1', 'blocked')
        with self.assertRaises(ci.SafeError):
            queue.transition(state, '1.1', 'skipped')
        queue.transition(state, '2.1', 'ready')
        queue.transition(state, '2.1', 'uploading')

    def test_compare_and_swap_retries_against_updated_remote_ledger(self):
        state = self.ledger()
        api = queue.GitHub()
        fresh = self.ledger()
        self.add(fresh, 'other.1')
        loads = [(state, 'old-sha'), (fresh, 'new-sha')]
        bodies = []
        def request(method, path, body):
            bodies.append(body)
            if len(bodies) == 1:
                raise queue.Conflict(409)
            return {}
        with patch.object(api, 'load', side_effect=loads), patch.object(api, 'request', side_effect=request), patch.object(queue.time, 'sleep'):
            result = api.change(lambda ledger: self.add(ledger, '2.1'))
        self.assertEqual(result['build'], '22')
        self.assertEqual(bodies[1]['sha'], 'new-sha')

    def test_missing_branch_requires_explicit_first_setup(self):
        api = queue.GitHub()
        with patch.dict(os.environ, {'TF_INITIALIZE_STATE': 'false'}), patch.object(api, 'request', side_effect=queue.Conflict(404)) as request:
            with self.assertRaises(ci.SafeError):
                api.initialise()
        self.assertEqual(request.call_count, 1)

    def test_missing_ledger_never_silently_resets_counter(self):
        api = queue.GitHub()
        with patch.object(api, 'request', side_effect=queue.Conflict(404)):
            with self.assertRaises(ci.SafeError):
                api.load()

    def test_recovery_requires_apple_confirmation(self):
        with patch.dict(os.environ, {'TF_RECOVERY_CONFIRMED': 'false'}):
            with self.assertRaises(ci.SafeError):
                queue.recover()

    def test_encrypted_transfer_round_trip_tampering_and_revision_mismatch(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(ci, 'ROOT', Path(directory)), patch.dict(os.environ, {
            'KEYCHAIN_PASSWORD': 'synthetic-test-password', 'ASC_PRIVATE_KEY': 'synthetic-key'}):
            metadata = {'app': 'fixture', 'group_id': 'fixture-group', 'group_name': 'External QA',
                        'build': '21', 'version': '9.0.0', 'configured_testers': 1,
                        'reservation_id': '1.1', 'source_sha': 'a' * 40, 'preparation': 'passed'}
            ipa = Path(directory) / 'fixture.ipa'
            ipa.write_bytes(b'synthetic-ipa')
            ci.save(**metadata, archive='succeeded', export='succeeded', ipa=str(ipa))
            ci.package()
            bundle = (ci.ROOT / 'ipa.bundle').read_bytes()
            self.assertNotIn(b'synthetic-ipa', bundle)
            self.assertNotIn(b'synthetic-key', bundle)
            with patch.object(ci, 'reserved_metadata', return_value=metadata):
                ci.restore()
                self.assertEqual((ci.ROOT / 'app.ipa').read_bytes(), b'synthetic-ipa')
                (ci.ROOT / 'ipa.bundle').write_bytes(bundle[:-1] + bytes([bundle[-1] ^ 1]))
                with self.assertRaises(ci.SafeError):
                    ci.restore()
            (ci.ROOT / 'ipa.bundle').write_bytes(bundle)
            with patch.object(ci, 'reserved_metadata', return_value={**metadata, 'source_sha': 'b' * 40}):
                with self.assertRaises(ci.SafeError):
                    ci.restore()


if __name__ == '__main__':
    unittest.main()
