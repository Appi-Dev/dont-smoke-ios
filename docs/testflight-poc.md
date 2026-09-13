# External TestFlight POC

The manual workflow is `.github/workflows/testflight-poc.yml`. It builds version **9.0.0**, exports an App Store Connect signed IPA, uploads it with Xcode’s `altool --upload-package`, waits for processing, and configures the specified external TestFlight group and testers. It never creates a production App Store version, submits production App Review, or releases an App Store version. The only review submission is **Beta App Review**.

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

Create an Actions **repository variable** named `TESTFLIGHT_GROUP_NAME` containing the exact name of an **existing external group belonging to this app**. Use a descriptive group name without personal/contact information. The workflow refuses missing, duplicate, or internal groups; it does not silently create a group with different settings.

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
3. Create the external group and finish the app's TestFlight test information and Beta App Review contact information in App Store Connect. Provide demo credentials if the app requires login. These sensitive details are not invented or committed by this workflow.
4. Accept required agreements and resolve export-compliance requirements. CI does not automatically claim an encryption exemption; it preserves the app's existing declaration. Review it when changing app functionality.
5. The certificate must be valid, include its private key in the P12, and be authorized by the unexpired profile. The profile must be an explicit App Store Connect distribution profile for the repository's bundle ID and team. Development, ad hoc, enterprise, and mismatched profiles are rejected.

Apple may require [Beta App Review before external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/). This is separate from upload processing. The workflow enables `autoNotifyEnabled` before submitting Beta App Review and assigning the build. Apple [sends invitations when the app is ready to test](https://developer.apple.com/documentation/appstoreconnectapi/beta-tester-invitations); pending review is reported as deferred invitations, not successful delivery. For a ready build, an existing tester in `NOT_INVITED` state receives an explicit invitation request. Already invited or accepted testers are reused without blindly resending invitations.

## Run

1. Review and commit the POC files alongside prerequisite app configuration. Keep `DontSmoke/Info.plist` tracked because the project references it.
2. Merge the reviewed workflow into the default branch. Protect that branch and limit write access because its code consumes distribution credentials. The job deliberately skips dispatches from other branches.
3. Open **Actions → External TestFlight POC → Run workflow**, selecting the default branch.
4. Read the job summary. It reports version/build, preflight, archive/export, upload acceptance, processing, external group assignment, review status, tester counts, invitation status, and credential cleanup.
5. If review is pending, check App Store Connect for approval or required action. Successful configuration does not mean that Apple has approved the build or that a tester has received/accepted an email.

Build numbers use an Apple-compatible three-component numeric format. The initial serial combines `GITHUB_RUN_NUMBER` and `GITHUB_RUN_ATTEMPT`, starting in the `9000.*.*` range. The allocator also reads existing builds for version 9.0.0 and advances above the largest existing number if needed. A rerun gets a new build number. Allocation fails rather than truncating if the four/two/two-digit range or attempt range is exhausted. GitHub workflow concurrency serializes runs without interrupting an upload. GitHub can replace older pending runs with newer dispatches; do not treat pending runs as a durable queue. Other upload pipelines must coordinate separately: this is not an atomic cross-pipeline build-number reservation.

Processing is polled every 30 seconds for approximately 90 minutes, with bounded read retries for rate limiting and transient service failures. Archive, export, and upload also have timeouts; the job's overall limit is 210 minutes. `FAILED`/`INVALID` processing fails the job. Review approval is not polled indefinitely; a successful pending-review configuration is explicitly labeled pending.

## Failure handling and privacy

Raw signing, Xcode, upload-tool, and API output is deliberately suppressed because it can contain credentials or identities. Errors report the failed tool/HTTP status without response bodies or query strings. Requests cannot redirect credentials to a different host. No IPA, archive, P8, profile, certificate, raw diagnostic output, or tester payload is published as a workflow artifact.

API mutations are not automatically retried: a network failure may occur after Apple accepted the write. Existing testers and memberships are reconciled on subsequent distribution attempts; build notes are updated if they already exist. Successful tester membership is confirmed with follow-up reads. Partial counts and failure information remain available in the summary.

After an upload timeout, uncertain upload result, processing timeout, or API mutation failure, first inspect App Store Connect using the summary's version/build and group. Do not infer that a failed job means Apple received nothing. Rerunning this workflow creates a **new build**; it is not a resume command for the previous upload. Finish an already uploaded build's distribution in App Store Connect if necessary. The workflow never expires older builds, removes testers, cancels other reviews, or changes a group's public-link settings.

A final cleanup step restores the original keychain search list and attempts every deletion even if one cleanup operation fails. It deletes the temporary keychain, installed profile, API key, P12, IPA, archive, and derived data. Only sanitized summary state is retained until the ephemeral GitHub-hosted runner is disposed. Cleanup failure fails the job and appears in the summary. A forcibly terminated runner cannot guarantee cleanup steps execute, so this job uses an ephemeral hosted runner and must not be moved to a persistent self-hosted runner without additional isolation.

## Validation

Run the offline safety suite without Apple credentials:

```sh
PYTHONPYCACHEPREFIX=/tmp/testflight-python-cache python3 -m unittest discover -s Scripts/testflight -p 'test_*.py' -v
```

The suite verifies numeric allocation, tester validation/deduplication, processing waits/failures/timeouts, pending-review handling, existing-tester reuse, membership verification, invitation requests, privacy-safe errors/summaries, host restrictions, profile validation, cleanup after failures, exact processed-build identity checks, unconfirmed upload handling, and a cryptographically verified JWT signed with a synthetic key. It also runs in the workflow before secrets are used.

Local validation: 16 offline safety tests passed, actionlint 1.7.12 and workflow YAML parsing passed, and Xcode 26.6 Release device build succeeded with `CODE_SIGNING_ALLOWED=NO`, marketing version 9.0.0, and CI-style build number 9000.1.1. The built Info.plist confirmed the exact bundle identifier, version, and build number. The installed upload tool’s help confirmed support for `--upload-package`, `--api-key`, `--api-issuer`, and `API_PRIVATE_KEYS_DIR`. This verifies scheme/app compilation and supported flags, not signed export or live distribution. Signed export, real certificate/profile compatibility, API permissions, live upload-tool behavior, and Apple review must be verified by the first authorized GitHub Actions run. No live upload or tester invitation was performed during implementation.
