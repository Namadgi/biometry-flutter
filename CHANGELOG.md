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