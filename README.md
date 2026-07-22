# Biometry

**Biometry** is a secure, reliable Flutter package designed to simplify biometric authentication and identity verification in mobile applications. Leveraging advanced biometric technologies, Biometry integrates seamlessly with the Biometry **v2 API**, supporting video-based facial and voice verification, liveness and deepfake detection, document verification, and consent management.

This package is tailored specifically for developers building high-security applications, such as banking, finance, identity verification, and compliance-driven projects.

## Features

- **Biometric Verification**: Face and voice enrollment and verification through image/video input.
- **Liveness & Deepfake Detection**: Anti-spoofing checks (face liveness, active speaker detection, visual speech recognition) and asynchronous deepfake analysis.
- **Document Scanning & Verification**: Built-in scanning using the `flutter_doc_scanner` plugin.
- **Biometric Scanner Widget**: User-friendly camera widget with guided video capture.
- **Consent Management**: Approve and look up consent-template approvals recorded for a user.
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
  biometry: ^2.0.0
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

`userId` is an opaque, customer-provided identity key (letters, digits, and `._:@-` only, max 128 characters) — it's what the Biometry API uses to identify the user, and is required. `fullName` is kept for your own display purposes only; it is never sent to the API.

```dart
final biometry = await Biometry.initialize(
  token: 'your-api-token',
  userId: 'user-1234',
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
    final response = await biometry.livenessCheck(video: videoFile);
    print(response.body);
  },
);
```

The captured video can be run through any combination of [`livenessCheck`](#liveness-face-verification-voice-verification--deepfake-detection), `faceVerify`, `voiceVerify`, and `deepfakeCheck` depending on what your flow needs — they are independent calls, not a single bundled step.

### Document Authentication

```dart
final response = await biometry.docAuth();
print(response.body);
```

`docAuth()` scans a document with the built-in scanner, sends it for verification, and — on success — extracts the document's portrait photo for use as the reference image in [`faceMatch`](#face-matching-against-a-reference-image). Optionally override the project's default providers:

```dart
final response = await biometry.docAuth(
  provider: 'idscan',
  mrzProvider: 'idscan',
);
```

### Face & Voice Enrollment

Enrolls a face (captured via `docAuth()`) or a voice recording against `userId`, for later verification:

```dart
final faceResponse = await biometry.enrolFace();

final voiceResponse = await biometry.enrolVoice(videoFile: videoFile);
```

### Face Matching Against a Reference Image

Matches the face extracted by `docAuth()` against either the session's video (default) or an explicit video you supply:

```dart
// Matches against the session video captured during this session.
final response = await biometry.faceMatch();

// Matches against a specific video instead.
final response = await biometry.faceMatch(
  video: videoFile,
  useSessionVideo: false,
);
```

### Liveness, Face Verification, Voice Verification & Deepfake Detection

```dart
final liveness = await biometry.livenessCheck(video: videoFile);

final faceVerify = await biometry.faceVerify(video: videoFile);

final voiceVerify = await biometry.voiceVerify(video: videoFile);

final deepfake = await biometry.deepfakeCheck(video: videoFile);
```

`livenessCheck` accepts an optional `excludeServices` list (`face_liveness_detection`, `active_speaker_detection`, `visual_speech_recognition`, `face_recognition`, `voice_recognition`) to skip specific checks. `deepfakeCheck` submits the video for asynchronous analysis — the response body contains a check `status` (`pending`/`processing`/`completed`/`failed`), not an immediate verdict.

### Consent Handling

Consent templates (their `journey_id`, header, and body text) are configured in the Biometry dashboard, not by this SDK. The SDK only records and looks up **approvals** of an existing template ID:

```dart
final response = await biometry.approveConsent(consentId: 'your-consent-template-id');

final approvals = await biometry.getConsentApprovals();

// Throws if the user hasn't approved this consent template.
await biometry.assertConsent(consentId: 'your-consent-template-id');
```

> **Note:** the v2 API does not currently support revoking a recorded approval.

### Ending a Session

```dart
final response = await biometry.endSession();

// Optionally run a SIM-swap fraud check for a phone number when ending.
final simSwapResponse =
    await biometry.endSession(phoneNumber: '+15551234567');
```

## Example Application

A complete, functional example application is provided within the [`example/`](example/) directory of the package.

## Security and Privacy

Biometry adheres to strict security standards:
- Authentication via secure API tokens.
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
