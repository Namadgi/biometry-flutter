# Biometry

`Biometry` is a Flutter package that allows developers to integrate biometric authentication and verification into their Flutter applications using the Biometry API. This package simplifies the process of handling biometric data, making it easy to authenticate users securely.

## Features

- **Biometric Authentication**: Easily authenticate users with biometric data such as voice and face recognition.
- **Video Processing**: Upload and process video files for biometric verification.
- **API Integration**: Seamlessly integrate with the Biometry API using a clean and straightforward Dart interface.

## Getting Started

### Prerequisites

Before you can start using the `Biometry` package, you need to:

1. Obtain an API token from the Biometry service.
2. Ensure your Flutter environment is set up. You can check the official [Flutter installation guide](https://flutter.dev/docs/get-started/install) for help.

### Installation

Add `biometry` to your `pubspec.yaml`:

```yaml
dependencies:
  biometry:
    path: ../biometry  # Replace with the path or pub.dev version if published
```

Then, run:

```sh
flutter pub get
```

## Usage

### Initialize the Biometry SDK

Initialize the `Biometry` class with your API token:

```dart
import 'package:biometry/biometry.dart';

void main() {
  final biometry = Biometry.initialize(token: 'your-api-token');

  // Now you can use the biometry instance to perform operations
}
```

### Process a Video for Biometric Verification

Here’s how you can process a video file for biometric verification:

```dart
import 'dart:io';

void processVideo(Biometry biometry) async {
  final videoFile = File('/path/to/your/video.mp4');
  final response = await biometry.processVideo(
    fullname: 'John Doe',
    videoFile: videoFile,
    phrase: 'one two three four five six seven eight',
  );

  if (response.statusCode == 200) {
    print('Video processed successfully: ${response.body}');
  } else {
    print('Failed to process video: ${response.statusCode}');
  }
}
```

### Example App

You can find a complete example in the `example/` directory of this package. The example demonstrates how to integrate the Biometry package into a Flutter app.

## Additional Information

### Contributions

Contributions are welcome! If you would like to contribute to this package, please fork the repository and submit a pull request. Make sure to follow the contribution guidelines.

### Issues and Feedback

If you encounter any issues or have any feedback, please open an issue on the [GitHub repository](https://github.com/Funkygeek/biometry-pubdev/issues).

### License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

### More Information

For more detailed documentation on the Biometry API, visit the [official documentation](https://dev.biometry.namadgi.com.au/dev-portal/overview/).
