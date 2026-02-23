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