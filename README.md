# Biometry

**Biometry** is a secure, reliable Flutter package designed to simplify biometric authentication and identity verification in mobile applications. Leveraging advanced biometric technologies, Biometry integrates seamlessly with the Biometry API, supporting video-based facial and voice authentication, document verification, user consent management, and secure device telemetry.

This package is tailored specifically for developers building high-security applications, such as banking, finance, identity verification, and compliance-driven projects.

## Features

- **Biometric Authentication**: Secure facial and voice recognition through video input.
- **Document Scanning & Verification**: Built-in scanning using the `flutter_doc_scanner` plugin.
- **Biometric Scanner Widget**: User-friendly camera widget with guided video capture.
- **Consent Management**: Integrated consent handling aligned with security best practices.
- **Device Telemetry**: Automatic collection of comprehensive device metadata.
- **Extensible & Testable API**: Designed for ease of testing and extensibility.

## Getting Started

### Prerequisites

- Obtain an API token from [Biometry](https://console.biometrysolutions.com).
- Flutter SDK version `>=3.0.0 <4.0.0`
- Android minimum SDK version: 21
- iOS minimum platform version: 13.0

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  biometry: ^1.0.2
```

Run:

```bash
flutter pub get
```

## Platform Setup

### Android

Update your `android/app/build.gradle`:

```gradle
defaultConfig {
  minSdkVersion 21
}
```

### iOS

Update `ios/Podfile`:

```ruby
platform :ios, '13.0'
```

Configure camera permissions in `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access for biometric authentication.</string>
```

Enable camera permissions via the `Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
      ]
    end
  end
end
```

## Usage

### Initializing Biometry

```dart
final biometry = await Biometry.initialize(
  token: 'your-api-token',
  fullName: 'John Doe',
);
```

### Displaying the Verification Phrase

```dart
print(biometry.phraseWords); // Example output: "One Two Three Four Five"
```

### Using the Scanner Widget

```dart
BiometryScannerWidget(
  phrase: biometry.phraseWords,
  onCapture: (videoFile) async {
    final response = await biometry.processVideo(videoFile: videoFile);
    print(response.body);
  },
);
```

### Document Authentication

```dart
final response = await biometry.docAuth();
print(response.body);
```

### Consent Handling

```dart
final response = await biometry.allowConsent(consent: true);
print(response.body);
```

## Example Application

A complete, functional example application is provided within the [`example/`](example/) directory of the package.

## Security and Privacy

Biometry adheres to strict security standards:
- Authentication via secure API tokens.
- Collection and secure transmission of detailed device information.
- Session-specific unique identifiers for enhanced traceability.
- No persistent storage or logging of biometric data within the package.

For further security guidance, refer to the [Biometry Developer Portal](https://developer.biometrysolutions.com/overview/).

## Contributing

Contributions are welcome. Please open an issue or submit a pull request on the [GitHub repository](https://github.com/Namadgi/biometry-flutter/issues).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Further Information

- [Biometry Homepage](https://biometrysolutions.com/)
- [Developer Documentation](https://developer.biometrysolutions.com/overview/)

