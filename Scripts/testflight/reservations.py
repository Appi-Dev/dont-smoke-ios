#!/usr/bin/env python3
"""GitHub-backed reservations. Conditional writes prevent duplicate numbers."""
import base64
import copy
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

from ci import SafeError, require, allocate, save

BRANCH = 'codex/testflight-state-integer-21'
FILE = '.testflight/reservations.json'
TERMINAL = {'completed', 'skipped'}


class GitHub:
    def request(self, method, path, body=None):
        request = urllib.request.Request('https://api.github.com/repos/' + require('GITHUB_REPOSITORY') + path,
            method=method, data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization': 'Bearer ' + require('GH_TOKEN'),
                     'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json',
                     'X-GitHub-Api-Version': '2022-11-28'})
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
                data = response.read()
                return json.loads(data) if data else {}
        except urllib.error.HTTPError as error:
            if error.code in (404, 409, 422):
                raise Conflict(error.code) from None
            raise SafeError(f'GitHub request failed (HTTP {error.code}); response suppressed') from None
        except (urllib.error.URLError, TimeoutError):
            raise SafeError('GitHub connection failed; reconcile reservations before retrying') from None

    def load(self):
        try:
            item = self.request('GET', '/contents/' + FILE + '?ref=' + urllib.parse.quote(BRANCH, safe=''))
            ledger = json.loads(base64.b64decode(item['content']))
            if ledger.get('schema') != 1:
                raise SafeError('Unsupported reservation schema')
            return ledger, item['sha']
        except Conflict as error:
            if error.code != 404:
                raise
            raise SafeError('Reservation state is missing; restore it rather than resetting the counter') from None

    def initialise(self):
        try:
            self.request('GET', '/git/ref/heads/' + BRANCH)
            return
        except Conflict as error:
            if error.code != 404:
                raise
        if os.environ.get('TF_INITIALIZE_STATE') != 'true':
            raise SafeError('Reservation branch missing; for first setup only enable initialize_state, otherwise restore the state branch')
        # An orphan branch contains only the ledger, never source or credentials.
        ledger = {'schema': 1, 'reservations': []}
        blob = self.request('POST', '/git/blobs', {
            'content': base64.b64encode(json.dumps(ledger).encode()).decode(), 'encoding': 'base64'})
        tree = self.request('POST', '/git/trees', {'tree': [
            {'path': FILE, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']}]})
        commit = self.request('POST', '/git/commits', {
            'message': 'ci: initialise TestFlight reservation ledger', 'tree': tree['sha'], 'parents': []})
        try:
            self.request('POST', '/git/refs', {'ref': 'refs/heads/' + BRANCH, 'sha': commit['sha']})
        except Conflict as conflict:
            if conflict.code != 422:
                raise
            self.request('GET', '/git/ref/heads/' + BRANCH)

    def change(self, mutation):
        for attempt in range(12):
            ledger, sha = self.load()
            result = mutation(ledger)
            body = {'message': 'ci: update TestFlight reservation state', 'branch': BRANCH,
                    'content': base64.b64encode(json.dumps(ledger).encode()).decode()}
            if sha:
                body['sha'] = sha
            try:
                self.request('PUT', '/contents/' + FILE, body)
                return result
            except Conflict as error:
                if error.code not in (409, 422):
                    raise
                time.sleep(min(5, 0.2 * (attempt + 1)))
        raise SafeError('Reservation contention exceeded retries; no number was confirmed')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Conflict(Exception):
    def __init__(self, code):
        self.code = code


def identity():
    return require('GITHUB_RUN_ID') + '.' + require('GITHUB_RUN_ATTEMPT')


def reserve(ledger, existing, reservation_id, run_id, attempt, sha):
    rows = ledger['reservations']
    for row in rows:
        if row['id'] == reservation_id:
            if row['sha'] != sha:
                raise SafeError('Reservation source revision mismatch')
            return copy.deepcopy(row)
    build = allocate(existing, [row['build'] for row in rows])
    row = {'id': reservation_id, 'build': build, 'version': '9.0.0', 'run_id': run_id,
           'attempt': attempt, 'sha': sha, 'status': 'building'}
    rows.append(row)
    return copy.deepcopy(row)


def transition(ledger, reservation_id, status):
    row = next((x for x in ledger['reservations'] if x['id'] == reservation_id), None)
    if not row:
        raise SafeError('Reservation not found')
    allowed = {'building': {'ready', 'skipped'}, 'ready': {'uploading', 'skipped'},
               'uploading': {'completed', 'blocked'}, 'blocked': set(),
               'completed': set(), 'skipped': set()}
    if status == row['status']:
        if status == 'uploading':
            raise SafeError('This reservation already entered upload; reconcile it instead of uploading again')
        return copy.deepcopy(row)
    if status not in allowed.get(row['status'], set()):
        raise SafeError('Refused invalid reservation transition')
    if status == 'uploading' and not is_turn(ledger, reservation_id):
        raise SafeError('A lower reserved build must be resolved before upload')
    row['status'] = status
    return copy.deepcopy(row)


def is_turn(ledger, reservation_id):
    pending = [r for r in ledger['reservations'] if r['status'] not in TERMINAL]
    return bool(pending) and min(pending, key=lambda r: int(r['build']))['id'] == reservation_id


def update(status):
    row = GitHub().change(lambda ledger: transition(ledger, identity(), status))
    save(reservation_status=row['status'], build=row['build'], reservation_id=row['id'])
    return row


def gate(seconds=14400):
    api = GitHub()
    deadline = time.monotonic() + seconds
    interval = 15
    while time.monotonic() < deadline:
        ledger, _ = api.load()
        current = next((x for x in ledger['reservations'] if x['id'] == identity()), None)
        if not current or current['status'] != 'ready':
            raise SafeError('Only a ready reservation can enter the submission queue')
        if is_turn(ledger, identity()):
            save(queue='submission turn granted')
            print('Submission turn granted')
            return
        earlier = [r for r in ledger['reservations'] if int(r['build']) < int(current['build'])
                   and r['status'] not in TERMINAL]
        for row in sorted(earlier, key=lambda r: int(r['build']))[:1]:
            if row['status'] == 'blocked':
                raise SafeError('Submission queue blocked by an uncertain earlier upload; use queue recovery after checking Apple')
            attempt = api.request('GET', f'/actions/runs/{row["run_id"]}/attempts/{row["attempt"]}')
            if row['status'] == 'uploading' and attempt['status'] == 'completed':
                raise SafeError('Submission queue blocked by an unfinished upload reservation; use queue recovery after checking Apple')
            if row['status'] != 'uploading' and attempt['status'] == 'completed':
                # Only skip a build that never entered the upload stage.
                def skip_stale(state, identifier=row['id']):
                    actual = next(r for r in state['reservations'] if r['id'] == identifier)
                    if actual['status'] in ('building', 'ready'):
                        transition(state, identifier, 'skipped')
                api.change(skip_stale)
        time.sleep(interval)
        interval = min(300, interval * 2)
    raise SafeError('Submission queue wait timed out; this reservation has not uploaded')


def recover():
    if require('TF_RECOVERY_CONFIRMED') != 'true':
        raise SafeError('Recovery requires explicit confirmation that Apple state was checked')
    identifier = require('TF_RECOVERY_ID')
    resolution = require('TF_RECOVERY_RESOLUTION')
    if resolution not in TERMINAL:
        raise SafeError('Recovery resolution must be completed or skipped')
    def apply(ledger):
        row = next((r for r in ledger['reservations'] if r['id'] == identifier), None)
        if not row or row['status'] not in ('uploading', 'blocked'):
            raise SafeError('Recovery is limited to an uncertain upload reservation')
        attempt = GitHub().request('GET', f'/actions/runs/{row["run_id"]}/attempts/{row["attempt"]}')
        if attempt['status'] != 'completed':
            raise SafeError('Finish or cancel the originating workflow before recovery')
        row['status'] = resolution
        row['recovered_by_run'] = require('GITHUB_RUN_ID')
        return copy.deepcopy(row)
    row = GitHub().change(apply)
    save(reservation_status=row['status'], build=row['build'], reservation_id=row['id'], queue='manually recovered')
    print('Reservation recovery recorded; future ready runs may proceed')


if __name__ == '__main__':
    import sys
    try:
        command = sys.argv[1]
        if command == 'gate':
            gate()
        elif command == 'recover':
            recover()
        else:
            update(command)
    except Exception as error:
        message = str(error) if isinstance(error, SafeError) else 'Reservation operation failed; details suppressed'
        save(failure=message, queue='not completed')
        print('ERROR: ' + message, file=sys.stderr)
        sys.exit(1)
