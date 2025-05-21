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