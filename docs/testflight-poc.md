# External TestFlight POC

The manual build workflow is `.github/workflows/testflight-poc.yml`. It builds version **9.0.0**, exports an App Store Connect signed IPA, uploads it with Xcode’s `altool --upload-package`, waits for processing, and configures a separate external TestFlight group for each build and its configured testers. It never creates a production App Store version, submits production App Review, or releases an App Store version. The only review submission is **Beta App Review**. IPA creation runs in parallel; uploads and external distribution run independently.

## Repository inspection

- Project: `DontSmoke.xcodeproj`. Its internal workspace is Xcode project metadata, not a separate dependency workspace.
- App target and scheme: `DontSmoke`; application target ID `A00000000000000000000002`. A committed shared scheme was added because the original scheme was only automatically available locally.
- Bundle identifier: `com.arpitdixit.dontsmoke`.
- Team: `FCX2BY8WSZ`, read from the existing project; no profile name is assumed.
- Local Debug/Release signing: Automatic, Apple Development, empty provisioning profile specifier. CI overrides signing on the command line without changing local signing settings.
- iOS deployment target: 17.0; Swift language version: 6.0. Synchronized project folders and object version 77 require Xcode 16 or newer; the project records creation with Xcode 26 and upgrade checks for 26.6. No explicit minimum-Xcode file was found. CI deliberately selects Xcode 26.6 on `macos-26`, matching the local validated toolchain and current upload requirements.
- Dependencies: Apple SDK frameworks only. No CocoaPods, Carthage, third-party Swift packages, or dependency lockfiles were found.
- No existing GitHub workflows or applicable `AGENTS.md` files were found. Existing local project/Info.plist changes were preserved.

GitHub's [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists the selected Xcode path. If that version is retired, update `DEVELOPER_DIR` to an available stable version and validate the app before dispatching.

## GitHub configuration

In repository **Settings → Secrets and variables → Actions**, retain the existing secrets:

| Secret | Purpose |
|---|---|
| `ASC_KEY_ID` | Team App Store Connect API key identifier |
| `ASC_ISSUER_ID` | Issuer UUID |
| `ASC_PRIVATE_KEY` | Complete P8 private key text, including header/footer and newlines |
| `BUILD_CERTIFICATE_BASE64` | Base64 Apple Distribution P12 |
| `P12_PASSWORD` | P12 export password |
| `PROVISIONING_PROFILE_BASE64` | Base64 App Store Connect distribution provisioning profile |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password |
| `TESTFLIGHT_TESTERS_JSON` | Sensitive JSON tester configuration |

The workflow also uses the built-in `GITHUB_TOKEN`; no personal access token is required. GitHub must permit the declared `contents: write` permission for the reservation branch, and `actions: read` for reservation recovery. Organisation policy or branch rules must allow that dedicated branch to be created and updated. The workflow remains limited to trusted code on the default branch.

Group names are generated automatically as **`9.0.0 (21)`**, **`9.0.0 (22)`**, etc. `TESTFLIGHT_GROUP_NAME` is no longer used; its repository variable can be removed. After processing, CI [creates the beta group](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-betagroups) for the existing app with `isInternalGroup: false`, `publicLinkEnabled: false`, and `hasAccessToAllBuilds: false`, or reuses an exact matching group. Duplicate, internal, publicly linked, all-build-access groups, and groups containing another build are refused. Validation requires an explicit external-group flag. Nullable public-link/all-build-access flags are accepted as unset; a null public-link flag with a link or link ID is refused. Missing flags and unexpected types fail closed. Errors identify the failing flag without exposing group payloads or tester identities. Creation conflicts are reconciled by bounded reads rather than retrying the write. Each group receives its own build and the testers configured in the secret. The summary reports the generated name and creation/reuse result. Groups are retained; CI does not delete older groups or change existing groups' settings.

Create `TESTFLIGHT_TESTERS_JSON` as an Actions **secret**, not a repository variable or committed file. Its value is a nonempty JSON array; each object must contain nonempty string fields `email`, `firstName`, and `lastName`. Duplicate email addresses are deduplicated case-insensitively. This example uses a reserved, nondeliverable domain; replace it only in GitHub's secret editor:

```json
[
  {
    "email": "tester@example.invalid",
    "firstName": "Example",
    "lastName": "Tester"
  }
]
```

Do not commit actual tester information or paste it into issues, workflow inputs, or logs. Tester payloads stay in the step environment and process memory. Summaries contain aggregate counts only; no tester emails, names, or resource IDs.

## App Store Connect prerequisites

1. The app record for the repository bundle identifier must already exist.
2. Use a team API key with **App Manager or Admin** access to the app, builds, external groups, and testers. Upload permission alone is insufficient for distribution. An individual API key without an issuer is not supported by this POC.
3. Finish the app's TestFlight test information and Beta App Review contact information in App Store Connect. Provide demo credentials if the app requires login. These sensitive details are not invented or committed by this workflow.
4. Accept required agreements and resolve export-compliance requirements. CI does not automatically claim an encryption exemption; it preserves the app's existing declaration. Review it when changing app functionality.
5. The certificate must be valid, include its private key in the P12, and be authorized by the unexpired profile. The profile must be an explicit App Store Connect distribution profile for the repository's bundle ID and team. Development, ad hoc, enterprise, and mismatched profiles are rejected.

Apple may require [Beta App Review before external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/). This is separate from upload processing. The workflow enables `autoNotifyEnabled` before submitting Beta App Review and assigning the build. Apple [sends invitations when the app is ready to test](https://developer.apple.com/documentation/appstoreconnectapi/beta-tester-invitations); pending review is reported as deferred invitations, not successful delivery. For a ready build, an existing tester in `NOT_INVITED` state receives an explicit invitation request. Already invited or accepted testers are reused without blindly resending invitations.

## Run

1. Review and commit the POC files alongside prerequisite app configuration. Keep `DontSmoke/Info.plist` tracked because the project references it.
2. Merge the reviewed workflow into the default branch. Protect that branch and limit write access because its code consumes distribution credentials. The job deliberately skips dispatches from other branches.
3. Before rolling out the parallel workflow, finish or cancel older TestFlight runs that do not use reservations. Otherwise an old pipeline could allocate the same number independently.
4. Open **Actions → External TestFlight POC → Run workflow**, selecting the default branch. On the first parallel run only, enable `initialize_state` after confirming no old runs or reservations remain. Leave it off for subsequent runs. If the state branch later disappears, restore it rather than enabling initialization again.
5. Read the job summaries for reservation, build, and submission. They report version/build, preflight, archive/export, upload acceptance, processing, external group assignment, review status, tester counts, invitation status, and credential cleanup.
6. If review is pending, check App Store Connect for approval or required action. Successful configuration does not mean that Apple has approved the build or that a tester has received/accepted an email.

## Parallel flow and persistent numbering

Each manual dispatch creates three jobs:

1. **reserve (Linux):** validates the Apple app/tester configuration and atomically records a build-number reservation in `codex/testflight-state-integer-21`, at `.testflight/reservations.json`. That orphan branch contains only the ledger. It records version, build, run ID/attempt, source commit, status, and sanitized build metadata (app identifier, generated group name, empty group ID until distribution, tester count); never credentials or tester identities. Each downstream job reads that record by run ID and attempt, checks its exact source revision, and does not depend on GitHub job outputs or `TF_METADATA`. This avoids GitHub suppressing metadata outputs when its secret matcher flags a JSON fragment. Concurrent writes use the GitHub Contents API's expected file SHA; a conflict causes a bounded read/recompute/retry, preventing duplicate numbers. Missing state fails closed rather than resetting the counter; branch creation requires the explicit first-run `initialize_state` input.
2. **build (Mac):** reads the reserved number, checks the exact source commit, creates the signed archive and IPA, encrypts/authenticates the transfer, and publishes one artifact named for that run and attempt. A successful artifact is marked ready; a failed pre-upload build is marked skipped. Each dispatch can build on a separate Mac.
3. **submit (Mac):** starts as soon as its own build job succeeds. It downloads only its run/attempt artifact, verifies authentication, metadata/source revision and IPA checksum, then atomically claims its own reservation before contacting Apple. The claim prevents duplicate upload of that reservation; it does not wait for any other reservation. Each run uploads, waits for its own processing, creates or reuses its generated group, and configures external TestFlight independently. Successful configuration marks it completed, including explicitly pending Beta App Review. Failures after claiming retain the legacy `blocked` status for operator reconciliation of that reservation only; other runs continue.

For example, IPA 22 can upload before IPA 21 finishes building. Both can upload and process simultaneously. Failed, cancelled, or uncertain reservations never hold other runs. Their numbers remain consumed. After pushing a workflow fix, dispatch a **new run** so GitHub uses the updated commit; rerunning an older run uses its original code. With unchanged code, rerun **all jobs** to obtain a reservation and artifact for the new attempt.

Build numbers follow the owner's requested sequence for **version 9.0.0: 21, 22, 23**. The dedicated `codex/testflight-state-integer-21` branch separates this sequence from earlier reservations. Each reservation advances above the saved integer reservations, starting at 21. Uploaded numbers are checked to avoid reusing the exact numeric build (including equivalent strings such as 21.0). Previously uploaded higher numbers, including 9000.1.2, do not raise the new sequence's starting point. This is an explicit owner-requested attempt to upload a lower build number for the same marketing version; **Apple may reject it**. The workflow does not bypass Apple validation or automatically change version. A rejected or uncertain upload requires reconciliation of that run only.

Initialise this new branch only for its first run, after finishing older pipelines. Preserve any older state branch for history; do not reset it. Failed/skipped reservations remain consumed, so later runs may have gaps. Allocation fails above 9999. Do not delete, reset, manually edit, or force-push the new state branch. Restrict modifications and retain its Git history.

Other upload pipelines must use the same reservation/claim mechanism or be disabled. Reading TestFlight alone cannot account for numbers assigned to IPAs that are still compiling. The ledger does not coordinate unrelated upload pipelines.

GitHub's [current runner limits](https://docs.github.com/en/actions/reference/limits) allow 5 simultaneous macOS jobs for Free/Pro/Team, or 50 for Enterprise, shared with other macOS jobs in the account. No additional build cap is imposed by this workflow. The previous workflow permitted one active run and one pending run through a workflow-level lock; the new version removes that lock. Build and submission jobs can run simultaneously and share those Mac slots. Available minutes, storage, organisation policy, and runner availability can reduce actual concurrency.

Reservation has a 15-minute job limit, IPA creation 70 minutes, upload/processing/distribution 135 minutes. Apple processing is polled approximately every 30 seconds for up to 90 minutes with bounded read retries. `FAILED`/`INVALID` processing fails the job. Beta App Review approval is not polled indefinitely; pending configuration is explicitly reported.

## Encrypted IPA transfer

The jobs run on separate machines, so the IPA must be transferred through a GitHub artifact. Only `ipa.bundle` is published, retained for one day. It contains an AES-256-CBC encrypted ZIP of the IPA and sanitized metadata, using OpenSSL PBKDF2 (200,000 iterations) with a random salt. An independent salted PBKDF2-derived HMAC-SHA256 key authenticates the container before decryption. Metadata and IPA checksums are checked against the reservation. Tampered artifacts or a different run/revision are refused.

The existing `KEYCHAIN_PASSWORD` secret is also used as the transfer passphrase. Use a strong random value; keep it unchanged during active runs, and rotate it when those runs/artifacts have finished. Plaintext IPAs, archives, keys, profiles, certificates, and tester payloads are never artifacts. A dedicated transfer secret can replace the reused passphrase in a future revision if separate rotation is needed.

## Failure handling and privacy

Raw signing, Xcode, upload-tool, and API output is deliberately suppressed because it can contain credentials or identities. Errors report the failed tool/HTTP status without response bodies or query strings. Failed IPA uploads additionally extract only five-digit Apple error codes from explicit `ITMS-`, `ERROR:`, or parenthesized error markers (for example `90382`). Codes appear in the sanitized upload result and failure summary; messages and raw output remain suppressed. Unrecognized failures report only the tool exit status. Upload timeouts remain uncertain and are not automatically retried. Requests cannot redirect credentials to a different host. No plaintext IPA, archive, P8, profile, certificate, raw diagnostic output, or tester payload is published as a workflow artifact. The authenticated encrypted IPA artifact is the only transfer artifact.

Concurrent tester-creation conflicts are reconciled with bounded lookup reads; membership and invitation conflicts are accepted only when follow-up reads confirm the intended state. The original mutation is never retried. API mutations are not automatically retried: a network failure may occur after Apple accepted the write. Existing testers and memberships are reconciled on subsequent distribution attempts; build notes are updated if they already exist. Successful tester membership is confirmed with follow-up reads. Partial counts and failure information remain available in the summary.

After an upload timeout, uncertain upload result, processing timeout, or API mutation failure, inspect App Store Connect using the summary's version/build and reservation ID. A failed job does not mean Apple received nothing. Finish or cancel that originating attempt, ensuring no upload remains in flight. If Apple received the build, finish its processing/distribution in App Store Connect for that build.

Then manually run **Actions → TestFlight reservation recovery** on the default branch (the workflow filename remains `testflight-queue-recovery.yml`). Enter the reservation ID (`run_id.attempt`), choose **completed** after finishing the intended distribution, or **skipped** after deciding not to continue that build. Check the Apple-state confirmation box. Recovery is restricted to uploading/blocked reservations whose originating attempt has completed. It updates only that ledger record and never calls Apple, deletes a build, or resends invitations. Other runs do not depend on recovery.

Rerunning creates a new reserved build; it does not resume an earlier upload. Failed pre-upload builds are marked skipped by their own cleanup step; forcibly cancelled runs may retain their last status without holding others. Missing/corrupt state requires restoring the state branch from Git history rather than resetting the counter. The workflow never expires older builds, removes testers, cancels other reviews, or changes public-link settings.

A final cleanup step restores the original keychain search list and attempts every deletion even if one cleanup operation fails. It deletes the temporary keychain, installed profile, API key, P12, IPA, archive, and derived data. Only sanitized summary state is retained until the ephemeral GitHub-hosted runner is disposed. Cleanup failure fails the job and appears in the summary. A forcibly terminated runner cannot guarantee cleanup steps execute, so this job uses an ephemeral hosted runner and must not be moved to a persistent self-hosted runner without additional isolation.

## Validation

Run the offline safety suite without Apple credentials:

```sh
PYTHONPYCACHEPREFIX=/tmp/testflight-python-cache python3 -m unittest discover -s Scripts/testflight -p 'test_*.py' -v
```

The suite verifies generated group names, group creation/reuse, creation conflicts, unsafe groups, and metadata loading with empty job outputs, missing legacy metadata guidance, and source-revision mismatches. It additionally verifies pre-upload unique reservations, conditional-write races, retry idempotence, independent claims across all earlier reservation states, failed build skipping, uncertain uploads, recovery confirmation, authenticated encryption round trips, tampering and revision mismatches. It verifies numeric allocation, tester validation/deduplication, processing waits/failures/timeouts, pending-review handling, concurrent tester creation and membership/invitation conflicts, existing-tester reuse, membership verification, invitation requests, privacy-safe errors/summaries, host restrictions, profile validation, cleanup after failures, exact processed-build identity checks, unconfirmed upload handling, and a cryptographically verified JWT signed with a synthetic key. It also runs in the workflow before secrets are used.

Local validation: the parallel flow passed 36 offline safety tests and Actions lint. The previously validated app remains unchanged. Earlier validation: 16 offline safety tests passed, actionlint 1.7.12 and workflow YAML parsing passed, and Xcode 26.6 Release device build succeeded with `CODE_SIGNING_ALLOWED=NO`, marketing version 9.0.0, and CI-style build number 9000.1.1. The built Info.plist confirmed the exact bundle identifier, version, and build number. The installed upload tool’s help confirmed support for `--upload-package`, `--api-key`, `--api-issuer`, and `API_PRIVATE_KEYS_DIR`. This verifies scheme/app compilation and supported flags, not signed export or live distribution. Signed export, real certificate/profile compatibility, API permissions, live upload-tool behavior, and Apple review must be verified by the first authorized GitHub Actions run. No live upload, tester invitation, reservation-branch creation, or workflow dispatch was performed during this implementation. The first GitHub run must additionally validate GitHub state-branch permissions, concurrent reservations, encrypted artifact transfer, and submission ordering.
