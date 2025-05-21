import 'dart:convert';
import 'dart:io';

import 'package:biometry/biometry_scanner_widget.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

// Import the generated mocks file (ensure the filename matches yours).
import 'camera_mocks.mocks.dart';

/// A fake XFile implementation to simulate a file returned by stopVideoRecording.
class FakeXFile implements XFile {
  @override
  final String path;
  FakeXFile(this.path);

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  String get name => 'fake_video.mp4';

  @override
  Future<String> readAsString({Encoding? encoding}) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestBiometryScannerWidget extends BiometryScannerWidget {
  TestBiometryScannerWidget({
    super.key,
    required super.phrase,
    required super.onCapture,
    super.testController,
  });

  @override
  BiometryScannerWidgetState createState() => TestBiometryScannerWidgetState();
}

class TestBiometryScannerWidgetState extends BiometryScannerWidgetState {
  @override
  Future<File> compressVideo(String videoPath) async {
    print('mock compressVideo called for path: $videoPath');
    return File(videoPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Create instances of the generated mocks.
  final mockCameraController = MockCameraController();
  final mockCameraDescription = MockCameraDescription();

  // Set up stubs for CameraDescription.
  when(mockCameraDescription.lensDirection)
      .thenReturn(CameraLensDirection.front);

  // Stub CameraController.initialize() so it completes.
  when(mockCameraController.initialize()).thenAnswer((_) async {});

  // Create a CameraValue to simulate an initialized camera.
  final cameraValue = CameraValue(
    isInitialized: true,
    isRecordingVideo: false,
    isRecordingPaused: false,
    isTakingPicture: false,
    isStreamingImages: false,
    previewSize: const Size(640, 480),
    flashMode: FlashMode.off,
    exposureMode: ExposureMode.auto,
    focusMode: FocusMode.auto,
    exposurePointSupported: false,
    focusPointSupported: false,
    deviceOrientation: DeviceOrientation.portraitUp,
    description: CameraDescription(
      name: 'Test Camera',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
  );
  when(mockCameraController.value).thenReturn(cameraValue);

  // Stub startVideoRecording() to succeed.
  when(mockCameraController.startVideoRecording()).thenAnswer((_) async {});

  // Stub stopVideoRecording() to return a FakeXFile with the expected path.
  final fakeXFile = FakeXFile('fake_path/video.mp4');
  when(mockCameraController.stopVideoRecording())
      .thenAnswer((_) async => fakeXFile);

  // *** IMPORTANT: Stub buildPreview() so that the CameraPreview widget can call it.
  when(mockCameraController.buildPreview()).thenReturn(Container());

  testWidgets(
    'BiometryScannerWidget builds and calls onCapture after phrase time (dependency injection)',
    (WidgetTester tester) async {
      // Create a temporary file path for the fake video.
      final tempDir = Directory.systemTemp.createTempSync();
      final tempFilePath = '${tempDir.path}/fake_video.mp4';

      // Create the temporary file to ensure it exists.
      final tempFile = File(tempFilePath)..createSync();
      // Update FakeXFile to use the temporary file path.
      final fakeXFile = FakeXFile(tempFilePath);

      // Stub stopVideoRecording() to return the updated FakeXFile.
      when(mockCameraController.stopVideoRecording())
          .thenAnswer((_) async => fakeXFile);

      File? capturedFile;
      void onCaptureCallback(File file) {
        print('onCapture called with file: ${file.path}');
        capturedFile = file;
      }

      // Inject the mockCameraController via the testController parameter.
      await tester.pumpWidget(
        MaterialApp(
          home: TestBiometryScannerWidget(
            phrase: 'One Two Three',
            onCapture: onCaptureCallback,
            testController: mockCameraController,
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(capturedFile, isNotNull,
          reason: 'onCapture should have been called');
      expect(capturedFile!.path, equals(tempFilePath),
          reason: 'Captured file path should match');

      // Clean up the temporary file and directory.
      tempFile.deleteSync();
      tempDir.deleteSync();
    },
  );
}
