# Biometry

**Biometry** is a secure, reliable Flutter package designed to simplify biometric authentication and identity verification in mobile applications. Leveraging advanced biometric technologies, Biometry integrates seamlessly with the Biometry **v2 API**, supporting video-based facial and voice verification, liveness and deepfake detection, document verification, and consent management.

This package is tailored specifically for developers building high-security applications, such as banking, finance, identity verification, and compliance-driven projects.

## Features

- **Biometric Verification**: Face and voice enrollment and verification through image/video input.
- **Liveness & Deepfake Detection**: Anti-spoofing checks (face liveness, active speaker detection, visual speech recognition) and asynchronous deepfake analysis.
- **Document Scanning & Verification**: Built-in scanning using the `flutter_doc_scanner` plugin.
- **Biometric Scanner Widget**: User-friendly camera widget with guided video capture.
- **Consent Management**: Give, withdraw and check the user's authorization and storage consent that enrollment requires, and record approvals of your own custom consent templates.
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
2. Accept only the `/api-gateway/v2/...` paths your app uses.
3. Never pass the request body through. Rebuild it from the fields and files that call needs, **set** `user_id` to the signed-in user (do not just compare it: the gateway's JSON decoder matches keys case-insensitively, so a duplicate `USER_ID` key can slip past a check), keep a `session_id` only if it was started for that user, and drop the query string (except `warmup=true` on session start).
4. Send the rebuilt request to `https://api.biometrysolutions.com` with the same path, adding `Authorization: Bearer <your Biometry API token>`.

In proxy mode your backend also owns two things:

- **Consent.** Before the first enrollment, record the user's authorization and storage consent with `PUT /api-gateway/v2/users/{user_id}/consents` (`{"authorization": true, "storage": true}`), in one of two ways (see [Consent](#consent)). Either let the app's `giveConsent()` / `revokeConsent()` / `getConsentStatus()` through (`PUT`/`GET` on that endpoint: set `{user_id}` to the signed-in user and forward only the boolean `authorization` and `storage` fields), or record it server-to-server with your API key, for example in your onboarding flow. The example proxy does the latter in `recordConsent()` / `POST /onboarding/consent` and does not forward the app's own consent calls. `approveConsent()` / `getConsentApprovals()` are for your own custom consent templates and do **not** unlock enrollment.
- **Liveness challenge.** Your backend issues the digits the user reads for the current session, keeps its own copy, and writes it into `phrase` on liveness and voice-verify (each may use it once per session), ignoring the phrase the app sends. A use only counts once Biometry answers `2xx`, so the user can retry with the same digits after a gateway error. face-verify needs no challenge, and the example proxy sends it without a phrase. In the app, fetch the challenge from your backend (`POST /challenge` with the `sessionId` in the example proxy) and pass it to `Biometry.setChallenge(challenge)` before showing the scanner, so the user reads your backend's digits, not ones generated on the device (see [Setting the Liveness Challenge](#setting-the-liveness-challenge)). Call `Biometry.clearChallenge()` if the user abandons the attempt. The example app does this when you fill in the backend proxy URL. Make the recording window (`scanTime`) long enough for 8 digits, about 10 seconds.
- Your user ids must be 3 to 128 characters of `A-Za-z0-9._:@-` for the consent endpoint.

The example proxy needs these Biometry API gateway changes deployed, in this order: biometry-api-gateway #147 (makes `phrase` optional on v2 face-verify; the proxy sends face-verify without one, which the current gateway refuses), then #148 (adds `PUT /api-gateway/v2/users/{user_id}/consents`). Deploy them before switching your app to proxy mode.

```dart
final biometry = await Biometry.initialize(baseUrl: backend, userId: userId, headersProvider: appAuth);
final res = await http.post(Uri.parse('$backend/challenge'),
    headers: {...await appAuth(), 'content-type': 'application/json'},
    body: jsonEncode({'session_id': biometry.sessionId}));
Biometry.setChallenge(jsonDecode(res.body)['challenge'] as String);
// Now show BiometryScannerWidget; liveness and voice-verify will use this challenge.
```

See [Backend proxy for client SDKs](https://developer.biometrysolutions.com/concepts/backend-proxy/) on the developer portal for a full example.

`headers` and `headersProvider` only apply in proxy mode: without `baseUrl` they are ignored and a warning is printed with `debugPrint`, so your app's own credentials are never sent to Biometry. `headers` are sent on every request and replace any SDK header with the same name (compared case-insensitively). If your app's session token can be refreshed while a `Biometry` instance is alive, pass `headersProvider` instead (or as well); it is called before every request and applied last:

```dart
final biometry = await Biometry.initialize(
  baseUrl: 'https://your-backend.example.com/biometry',
  userId: 'user-1234',
  headersProvider: () async =>
      {'Authorization': 'Bearer ${await auth.currentToken()}'},
);
```

#### Direct mode (testing only)

Without `baseUrl`, pass your API token and the SDK calls the Biometry API directly. Only do this for testing or internal apps, since anyone who unpacks the app can read the token:

```dart
final biometry = await Biometry.initialize(
  token: 'your-api-token',
  userId: 'user-1234',
);
```

`initialize` throws an `ArgumentError` (an `Error`, not an `Exception`) if you pass neither `token` nor `baseUrl`, or an empty token without `baseUrl`.

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

`setChallenge` accepts only the digits `0`-`9`, 7 to 12 of them, and throws an `ArgumentError` otherwise. The SDK displays the challenge exactly as given, and `biometry.phrase` returns the digits unchanged. Requests send it spelled out as words in the `phrase` field, for example `"Nine Three Zero Five Seven One Eight"` for `9305718`. It stays set, including across `Biometry.initialize()` and across calls (one recording can go to `livenessCheck` and then `voiceVerify`), until you call `setChallenge` again or `Biometry.clearChallenge()`. Call `setChallenge` for every login attempt, and `clearChallenge()` when the user abandons one.

After `clearChallenge()` there is no phrase, so `phraseWords`, `livenessCheck`, `voiceVerify` and `enrolVoice` throw a `StateError` until you call `setChallenge` (or `initialize()` generates the deprecated fallback). `faceVerify` needs no challenge and keeps working.

Why 8 digits from 1-9: the voice engine's quality check needs at least 7 recognised words, so one misheard digit in a 7-digit phrase already fails; 8 leaves a margin, and the Biometry console uses 8 too. `0` is left out because people say it as "zero" or "oh", which hurts voice matching.

When your backend checks liveness, it must send **its own stored copy** of the challenge as `phrase`, never a phrase that came back from the device. A phrase chosen or returned by the device doesn't stop replays: someone who controls the device can pair a pre-recorded video with whatever digits that video happens to say.

> **Replay protection needs your backend in the path.** When the app calls Biometry directly with a token (direct mode), the phrase comes from the device, so there is no replay protection. Use proxy mode, where the SDK calls your backend and your backend injects its stored copy of the challenge into `phrase` before forwarding to Biometry. See [Backend proxy](https://developer.biometrysolutions.com/concepts/backend-proxy/).

> **Deprecated:** if you don't call `setChallenge` (the challenge is omitted), `Biometry.initialize()` still generates 7 digits from `1`-`9` on the device (and `Biometry.resetPhrase()` generates new ones), and prints a one-time warning (once per process) that device-generated challenges give no replay protection. This keeps existing apps working. Move to a backend-issued challenge: see [Liveness challenge](https://developer.biometrysolutions.com/concepts/liveness-challenge/). An empty or invalid challenge passed to `setChallenge` is never replaced by a fallback; it throws.

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

Enrollment requires the user's consent first (see [Consent](#consent)); without it the API answers 403.

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

### Consent

Face and voice enrollment require the user's **authorization** consent (Biometry may process their biometric data) and **storage** consent (Biometry may store it for later verification). Ask the user in your app, then record their answer before enrolling:

```dart
// Gives both consents. Calling it again is harmless.
final status = await biometry.giveConsent();
print(status.canEnrol); // true

await biometry.enrolFace();

// Check what is recorded for the user.
final current = await biometry.getConsentStatus();

// Withdraw both (or pass authorization: false / storage: false to keep one).
// Enrollment fails with 403 until giveConsent() is called again.
await biometry.revokeConsent();
```

Consent is stored against the `userId`, so it only has to be given once per user, not once per session. User ids must be 3 to 128 characters of `A-Z a-z 0-9 . _ : @ -`.

#### Custom consent templates

`approveConsent()`, `getConsentApprovals()` and `assertConsent()` record and check approvals of your own custom consent templates (created with `POST /v2/consents`). They are separate from the consent above and do **not** unlock enrollment.

```dart
await biometry.approveConsent(consentId: 'your-consent-template-id');
final approvals = await biometry.getConsentApprovals();
// Throws if the user hasn't approved this consent template.
await biometry.assertConsent(consentId: 'your-consent-template-id');
```

A template approval cannot be withdrawn.

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
