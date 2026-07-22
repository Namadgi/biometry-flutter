## [2.0.0] - 2026-07-21

### Added
- `userId` parameter (required) on `Biometry.initialize()` — the opaque, customer-provided identity key the v2 API uses to identify users.
- `livenessCheck()`, `faceVerify()`, `voiceVerify()`, and `deepfakeCheck()` methods, replacing `processVideo()`.
- `faceMatch()` accepts `useSessionVideo` (defaults to `true`, matching the old hardcoded behavior) and an optional `video` file for when it's `false`.
- `docAuth()` accepts optional `provider` and `mrzProvider` overrides.
- `endSession()` accepts an optional `phoneNumber` to run a SIM-swap fraud check when ending the session.
- `approveConsent({consentId})` and `getConsentApprovals()`, with a new `ConsentApproval` model (`consentId`, `userId`, `approvedAt`).
- `clientAppName` and `clientAppVersion` parameters on `Biometry.initialize()`, sent as `X-Client-App` / `X-Client-App-Version` headers on every request (carried forward from 1.0.9).

### Changed
- **Migrated to the Biometry v2 REST API** (`/api-gateway/v2/*`) across every endpoint: sessions, document verification, face/voice enrollment, and face matching.
- `assertConsent()` now takes a required `consentId` and checks it against `getConsentApprovals()`, instead of checking a cached boolean flag.

### Removed (Breaking)
- `fullName` is no longer sent to the API — it's local/display-only now; pass `userId` instead for API calls.
- `processVideo()` removed — v2 has no single call that both authenticates and auto-enrolls; use `livenessCheck()`, `faceVerify()`, `voiceVerify()`, and/or `deepfakeCheck()` individually.
- `allowConsent()`, `allowStorageConsent()`, `getConsentHistory()`, and the `ConsentHistoryResult`/`ConsentRecord`/`ConsentHistoryEntry` models removed — replaced by `approveConsent()`/`getConsentApprovals()`/`ConsentApproval`. **v2 has no consent-revoke endpoint** — there is currently no way to withdraw a recorded approval.
- `BiometryGeoLocation`, `setGeoLocation()`, and the `geoLocation` parameter on `initialize()` removed — v2 has no geolocation field.
- Device-info collection removed (the `X-Device-Info` header and the `device_info_plus`/`recase` dependencies) — v2 has no device-info field.

### Fixed
- `scanDocument()` now correctly handles the `flutter_doc_scanner` ^0.0.21 API (`ImageScanResult` / `DocScanException`) instead of the old raw `List`/`Map`/`PlatformException` shape — the previous implementation silently returned an empty path on every scan against the actually-resolved plugin version.

**This is a breaking release.** Every consumer needs to: pass `userId` to `initialize()`, replace `processVideo()` calls with the new granular verification methods, and migrate consent handling to the approval-based API. See the [README](README.md) for updated usage examples.

## [1.0.10] - 2026-03-11

_Retroactively added — published to pub.dev but missing from this changelog's history until now._

### Fixed
- **scanDocument():** Fixed "no image path received" exception by updating the document scanning logic to support the breaking API changes in `flutter_doc_scanner` 0.0.17+ (typed `ImageScanResult` return).

### Changed
- Updated `flutter_doc_scanner` dependency constraint to `^0.0.18`.

## [1.0.9] - 2026-03-10

_Retroactively added — published to pub.dev but missing from this changelog's history until now._

### Added
- **Client app metadata headers:** `Biometry.initialize()` accepts two new optional parameters — `clientAppName` and `clientAppVersion`. When provided, `X-Client-App` and `X-Client-App-Version` headers are attached to every request sent to the API gateway (session start/end, docAuth, processVideo, enrolFace, enrolVoice, faceMatch).

No breaking changes.

## [1.0.8] - 2026-03-03

### Added
- **Reference frame for face match (cross-device):** `Biometry.initialize()` accepts optional `referenceFramePath` to use a local reference image without calling `docAuth()` first.
- **Server-extracted reference frame:** `setReferenceFrameFromTransaction(transactionId)` fetches the frame from the Biometry samples API (`X-Request-Id` from `processVideo` response) and sets it as the face reference — works on any device that has the transaction ID.
- **Client-extracted reference frame:** `extractReferenceFrame(videoFile)` extracts a frame from a video file and saves it as the reference (e.g. for offline or testing).
- `faceMatch()` now sets the request content-type from the reference image file extension (`image/jpeg` for `.jpg`/`.jpeg`, `image/png` otherwise).

### Changed
- **Consent history API:** `ConsentHistoryResult.consent` and `ConsentHistoryResult.storageConsent` are now nullable (`ConsentRecord?`) to match the API (one consent type can be null). Code that formats or displays consent must handle null.
- **getConsentHistory():** A 404 response now returns a `ConsentHistoryResult` with both consent fields null instead of throwing. Non-404 errors still throw with a clear message. Parse/unexpected-format failures throw with an "Unexpected consent history response format" message instead of "No consents found".
- **assertConsent():** Handles null `consent` before reading `isConsentGiven`.
- **Samples API:** Response key for the extracted frame is read as `login-extracted-frame` (hyphenated) with fallback to `login_extracted_frame`. Reference frame download uses a separate `http.get()` for the signed GCS URL so the Biometry auth header is not sent to storage.

### Fixed
- Consent history parsing no longer throws when the API returns null for `consent` or `storage_consent`.
- Correct handling of the Get samples response format per [Biometry API docs](https://developer.biometrysolutions.com/api/transactions-samples/).

Note: No breaking API changes for callers that null-check or use optional consent fields. Callers that assumed non-null `consent`/`storageConsent` need to add null checks.

## [1.0.7] - 2026-02-23

### Added
- New `getConsentHistory()` method to retrieve the full consent history for the current user, returning a typed `ConsentHistoryResult` with both authorization and storage consent records including their histories.
- New model classes: `ConsentHistoryResult`, `ConsentRecord`, and `ConsentHistoryEntry` for typed access to consent history data.
- Consent guard: `processVideo()`, `docAuth()`, `faceMatch()`, `enrolFace()`, and `enrolVoice()` now verify that the user has given authorization consent before executing. The consent check is fetched once per session and cached — no extra network call on subsequent operations.
- Example app now includes a "View Consent History" button in the Consent Management section.

Note: No breaking API changes; library API remains backward-compatible.

## [1.0.6] - 2025-12-31

### Changed
- Session warmup is now enabled by default by calling `sessions/start?warmup=true` to reduce first-call latency.
- Updated example assets and tests to reflect the warmup-enabled session initialization flow.


## [1.0.5] - 2025-12-24

### Added
- Support for optional geolocation information in all transactions via the `X-Geo-Location` header
- New `BiometryGeoLocation` class to represent latitude, longitude, country, city, and optional IP address
- `geoLocation` parameter in `Biometry.initialize()` to set geolocation during initialization
- `setGeoLocation()` method to update geolocation information at any time
- Example app now includes automatic device location detection with reverse geocoding

### Changed
- Centralized header management using `_addCommonHeaders()` internal method
- Refactored all API methods to consistently include device telemetry and geolocation headers
- Example app uses `LocationAccuracy.medium` with 15-second timeout for better battery efficiency

### Technical Details
- Geolocation data is included in all API requests when provided
- If geolocation is not provided, the API falls back to IP-based lookup (existing behavior)
- Example app includes permission handling and reverse geocoding using OpenStreetMap Nominatim API

Note: No breaking API changes; library API remains backward-compatible.

## [1.0.4] - 2025-10-31

### Added
- Example app UX improvements: animated results panel, progress/loading states, and clearer form validation and error messages.
- Additional inline docs and debug logs to help integrate and troubleshoot `Biometry.initialize` and video processing flows.
- New API: `Biometry.resetPhrase()` to regenerate the 7-digit verification phrase (unique digits) at any time, using the same logic as during initialization.

### Changed
- Polished example app UI and state management for initialization and processing flows.
- Updated iOS example project settings to target iOS 13+ consistently and set `PERMISSION_CAMERA=1` in Pod build settings.
- Refreshed README badges, links, and setup instructions; clarified automatic enrollment notes around `processVideo()`.
- Minor metadata updates in `pubspec.yaml`.

### Fixed
- Minor typos and formatting across README and in-code comments.
- Improved example tests and minor adjustments in `example/test/widget_test.dart`.

Note: No breaking API changes; library API remains backward-compatible.

## [1.0.3] - 2025-09-25

### Added
- Support for automatic enrollment when both consent and storage consent are given before `processVideo()`
- Enhanced logging for `processVideo()` response including status, headers, and body
- Documentation for new automatic enrollment behavior

### Changed
- Reduced phrase length from 10 digits to 7 digits for better user experience
- Updated documentation to explain automatic enrollment feature
- Enhanced `processVideo()` method documentation

### Fixed
- Improved response logging for better debugging and monitoring

## [1.0.2] - 2025-05-21

### Changed
- Bumped dependencies in `pubspec.yaml` to their latest compatible versions for improved stability and performance.
- Refreshed and corrected README links to point to the most up-to-date documentation and resources.

## [1.0.1] - 2025-05-21

### Added
- Enhanced example app with updated UI, session management, and integrated biometric actions.
- Added face and voice enrollment

### Changed
- Updated documentation for setup, security, and contribution guidelines.
- Refactor biometric scanning widget
- Refactor biometry logic
- Upgraded to Dart 3 and Flutter 3.29.0 with new dependencies for audio, camera, and video processing.

### Fixed
- Improved error handling and metadata collection for better cross-platform support.

### Tests
- Added widget and integration tests for biometric features.

## [1.0.0] - 2024-03-23

### Added
- Initial stable release of the Biometry Flutter package.
- Support for secure biometric authentication via video-based face and voice recognition.
- Integrated document scanning using flutter_doc_scanner.
- Biometric scanning widget (BiometryScannerWidget) for capturing user video with dynamic phrase prompts.
- API integration for document authentication (docAuth), video processing (processVideo), and user consent management (allowConsent).
- Device telemetry and metadata collection for audit and security purposes.
- Customisable and testable API client with injectable HTTP client for unit tests.

### Changed
- Improved package structure for better maintainability and extensibility.
- Enhanced documentation tailored for security-sensitive deployments.

## [0.1.4] - 2025-02-11
### Changed
- Updated the `Biometry` class to include a new field, `sessionID`, which allows all interactions to be linked to a session.

## [0.1.3] - 2025-02-06
### Changed
- Enhanced `convertKeysToSnakeCase` to support recursive conversion of nested maps and lists, ensuring consistent `snake_case` formatting for deeply nested device information.

### Fixed
- Addressed an issue where nested maps and lists were not properly converted to `snake_case`, leading to inconsistent data formats.

## [0.1.2] - 2024-08-22
### Added
- Added documentation comments to public members of the `Biometry` class to resolve `public_member_api_docs` lint warnings.

### Changed
- Updated `example/pubspec.yaml` to remove 'path' dependencies for publishable package compliance.

## [0.1.1] - 2024-08-22
### Fixed
- Fixed a bug where the `processVideo` method would incorrectly handle file lengths.
- Moved `http_parser` from `dev_dependencies` to `dependencies`.

## [0.1.0] - 2024-08-21
### Added
- Initial release of the Biometry package.
- Added support for video processing for biometric verification.
- Included seamless integration with the Biometry API.