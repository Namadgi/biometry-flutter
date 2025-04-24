import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';

/// A widget that records a video of the user's face while displaying a phrase.
/// Once the user starts talking (simulated by auto-start after 1 second),
/// it displays the words of the phrase one by one. When all words are shown,
/// the recording stops and the captured video is returned.
class BiometryScannerWidget extends StatefulWidget {
  /// The phrase to be spoken by the user.
  final String phrase;

  /// Called when the video recording completes.
  final Function(File videoFile) onCapture;

  /// The test controller to use for testing.
  final CameraController? testController; // Optional test controller

  /// Creates a new [BiometryScannerWidget] instance.
  const BiometryScannerWidget({
    super.key,
    required this.phrase,
    required this.onCapture,
    this.testController,
  });

  @override
  BiometryScannerWidgetState createState() => BiometryScannerWidgetState();
}

/// The state of the [BiometryScannerWidget].
class BiometryScannerWidgetState extends State<BiometryScannerWidget>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  late Future<void> _initializeControllerFuture;

  /// The number of seconds to display based on the number of words in the phrase.
  late int scanTime;

  // Animation controller for the circular timer.
  late AnimationController _timerController;
  late Animation<double> _timerAnimation;

  // For displaying the phrase word by word.
  int _currentSecond = 0;
  Timer? _wordTimer;

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = _setupCamera();
    scanTime = widget.phrase.split(" ").length; // 1 second per word.
    _timerController =
        AnimationController(vsync: this, duration: Duration(seconds: scanTime));
    _timerAnimation = Tween<double>(begin: 0, end: 1).animate(_timerController);

    // Start recording and timer after a short delay.
    Future.delayed(const Duration(seconds: 1), () {
      _startRecordingAndDisplayPhrase();
      _timerController.forward();
    });
  }

  Future<void> _setupCamera() async {
    try {
      if (widget.testController != null) {
        _cameraController = widget.testController;
        await _cameraController!.initialize();
      } else {
        final cameras = await availableCameras();
        final frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: true,
        );
        await _cameraController!.initialize();
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _startRecordingAndDisplayPhrase() async {
    if (_cameraController == null) return;
    try {
      await _cameraController!.startVideoRecording();
      setState(() {});
      // Display each word for 1 second.
      _wordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _currentSecond++;
        });
        if (_currentSecond >= scanTime) {
          timer.cancel();
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint("Error starting video recording: $e");
    }
  }

  void _stopRecording() async {
    if (_cameraController == null) return;
    try {
      final file = await _cameraController!.stopVideoRecording();
      final videoFile = await compressVideo(file.path);
      setState(() {});

      widget.onCapture(videoFile);
    } catch (e) {
      debugPrint("Error stopping video recording: $e");
    }
  }

  /// Compresses the video file at the given path and returns the compressed file.
  compressVideo(String videoPath) async {
    // Get the original file size
    final originalFileSize = File(videoPath).lengthSync();
    debugPrint('Original video size: $originalFileSize bytes... $videoPath');

    final compressedVideo = await VideoCompress.compressVideo(
      videoPath,
      quality: VideoQuality.DefaultQuality,
    );

    // Get the compressed file size
    final compressedFileSize = compressedVideo!.file?.lengthSync();
    debugPrint(
        'Compressed video size: $compressedFileSize bytes... $videoPath');

    return compressedVideo.file;
  }

  @override
  void dispose() {
    _wordTimer?.cancel();
    _cameraController?.dispose();
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: 400,
                    height: 400,
                    child: ClipOval(
                      child: Center(
                        child: Transform.scale(
                          scale: _cameraController!.value.aspectRatio,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: SizedBox(
                  width: 400,
                  height: 400,
                  child: AnimatedBuilder(
                    animation: _timerAnimation,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: TimerBorderPainter(
                          _timerAnimation.value,
                          boxSize: 400,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}

/// Custom painter that draws a circular progress border.
class TimerBorderPainter extends CustomPainter {
  /// The progress value between 0 and 1.
  final double progress;

  /// The size of the box to draw in.
  final double boxSize;

  /// Creates a new [TimerBorderPainter] instance.
  TimerBorderPainter(this.progress, {this.boxSize = 400});

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = 16;
    final double radius = (boxSize / 2) - (strokeWidth / 2);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);

    final backgroundPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, -pi / 2, 2 * pi, false, backgroundPaint);

    final progressPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    double sweepAngle = 2 * pi * progress;
    canvas.drawArc(arcRect, -pi / 2, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant TimerBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
