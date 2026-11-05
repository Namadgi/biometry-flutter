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

- Obtain an API token from [Biometry](https://console.biometrysolutions.com), and keep it on your backend (see [Proxy mode](#proxy-mode-recommended)).
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

`userId` is an opaque, customer-provided identity key (letters, digits, and `._:@-` only, max 128 characters) — it's what the Biometry API uses to identify the user, and is required.

#### Proxy mode (recommended)

Your Biometry API token is project-wide and long-lived. Anything shipped inside an APK or IPA can be extracted, so keep the token on your backend and point the SDK at it with `baseUrl`:

```dart
final biometry = await Biometry.initialize(
  baseUrl: 'https://your-backend.example.com/biometry',
  userId: 'user-1234',
  // Optional: your own app's credentials, checked by your backend.
  headers: {'Authorization': 'Bearer $yourAppSessionToken'},
);
```

The SDK keeps the request paths and only swaps the host, so it calls `https://your-backend.example.com/biometry/api-gateway/v2/sessions`, `.../api-gateway/v2/liveness`, and so on. Without a `token` it sends no `Authorization` header of its own. Your backend must:

1. Authenticate your user (with your own session, cookie or the `headers` you pass here).
2. Check that the `user_id` in the request (in the JSON `request` part of multipart calls, or in the path of consent calls) is a user that caller may act as, and that any `session_id` was started for that user.
3. Forward only the `/api-gateway/v2/...` paths your app uses to `https://api.biometrysolutions.com` with the same path and query, adding `Authorization: Bearer <your Biometry API token>`, and stream the response back.

See [Backend proxy for client SDKs](https://developer.biometrysolutions.com/concepts/backend-proxy/) on the developer portal for a full example.

`headers` are sent on every request and replace any SDK header with the same name (compared case-insensitively).

#### Direct mode (testing only)

Without `baseUrl`, pass your API token and the SDK calls the Biometry API directly. Only do this for testing or internal apps, since anyone who unpacks the app can read the token:

```dart
final biometry = await Biometry.initialize(
  token: 'your-api-token',
  userId: 'user-1234',
);
```

`initialize` throws an `ArgumentError` if you pass neither `token` nor `baseUrl`.

#### Client app headers

Optionally, pass `clientAppName` and `clientAppVersion` to identify your app on every request (sent as the `X-Client-App` and `X-Client-App-Version` headers):

```dart
final biometry = await Biometry.initialize(
  baseUrl: 'https://your-backend.example.com/biometry',
  userId: 'user-1234',
  clientAppName: 'MyApp',
  clientAppVersion: '3.2.1',
);
```

`fullName` is deprecated since 2.1.0. It was never sent to the v2 API and will be removed in 3.0.0; you can drop it from your `initialize` call.

### Setting the Liveness Challenge

The digits the user speaks should be a **challenge issued by your backend**. We recommend 8 distinct digits from `1`-`9`, from a cryptographically secure random source, stored against the user's login attempt, valid for at most 5 minutes and used once. Pass it to the SDK before showing the scanner, and allow about 10 seconds of recording for 8 digits:

```dart
// challenge comes from your backend, e.g. "48719352"
Biometry.setChallenge(challenge);
print(biometry.phrase);      // "48719352"
print(biometry.phraseWords); // "Four Eight Seven One Nine Three Five Two"

// No instance needed, e.g. to show the digits before initialize() finishes:
print(Biometry.challengeWords('48719352'));
```

`setChallenge` accepts only the digits `0`-`9`, 7 to 12 of them, and throws an `ArgumentError` otherwise. The SDK displays and sends the challenge exactly as given. It stays set, including across `Biometry.initialize()` and across calls (one recording can go to `livenessCheck` and then `voiceVerify`), until you call `setChallenge` again or `Biometry.clearChallenge()`. Call `setChallenge` for every login attempt, and `clearChallenge()` when the user abandons one.

Why 8 digits from 1-9: the voice engine's quality check needs at least 7 recognised words, so one misheard digit in a 7-digit phrase already fails; 8 leaves a margin, and the Biometry console uses 8 too. `0` is left out because people say it as "zero" or "oh", which hurts voice matching.

When your backend checks liveness, it must send **its own stored copy** of the challenge as `phrase`, never a phrase that came back from the device. A phrase chosen or returned by the device doesn't stop replays: someone who controls the device can pair a pre-recorded video with whatever digits that video happens to say.

> **Replay protection needs your backend in the path.** When the app calls Biometry directly with a token (direct mode), the phrase comes from the device, so there is no replay protection. Use proxy mode, where the SDK calls your backend and your backend injects its stored copy of the challenge into `phrase` before forwarding to Biometry. See [Backend proxy](https://developer.biometrysolutions.com/concepts/backend-proxy/).

> **Deprecated:** if you don't call `setChallenge`, `Biometry.initialize()` still generates 7 digits from `1`-`9` on the device (and `Biometry.resetPhrase()` generates new ones). This keeps existing apps working but gives no replay protection. Move to a backend-issued challenge.

### Using the Scanner Widget

`phrase` takes the words to show, one at a time: `biometry.phraseWords`, or `Biometry.challengeWords(challenge)` without an instance.

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
- Authentication via API tokens that can stay on your backend (proxy mode), so no Biometry token ships in the app.
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
