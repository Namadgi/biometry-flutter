import 'dart:developer' as dev;
import 'dart:io';

import 'package:biometry/biometry.dart';
import 'package:biometry/biometry_scanner_widget.dart'; // Assume this is your SDK widget.
import 'package:flutter/material.dart';

void main() {
  runApp(const BiometryApp());
}

class BiometryApp extends StatelessWidget {
  const BiometryApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biometry Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BiometryHomePage(),
    );
  }
}

class BiometryHomePage extends StatefulWidget {
  const BiometryHomePage({Key? key}) : super(key: key);

  @override
  BiometryHomePageState createState() => BiometryHomePageState();
}

class BiometryHomePageState extends State<BiometryHomePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();

  File? _capturedVideo; // This now holds the video returned from "Scan Person"
  String _result = '';
  bool _isProcessing = false;
  Biometry? _biometry;
  bool _isBiometryInitialized = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  /// Initializes Biometry when the "Initialize Biometry" button is pressed.
  Future<void> _initializeBiometry() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showSnackBar('Please enter a valid token before initializing.');
      return;
    }
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) {
      _showSnackBar('Please enter your full name before initializing.');
      return;
    }
    try {
      _biometry = await Biometry.initialize(token: token, fullName: fullName);
      setState(() {
        _isBiometryInitialized = true;
      });
      _showSnackBar(
          'Biometry initialized with Session ID: ${_biometry!.sessionId}');
    } catch (e) {
      _showSnackBar('Failed to initialize Biometry: $e');
    }
  }

  /// Allows consent.
  Future<void> _allowConsent() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    try {
      final response = await _biometry!.allowConsent(consent: true);
      setState(() {
        if (response.statusCode == 200) {
          _result = 'Consent allowed successfully!\n${response.body}';
        } else {
          _result =
              'Failed to allow consent: ${response.statusCode}\n${response.body}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Allows consent.
  Future<void> _allowStorageConsent() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    try {
      final response = await _biometry!.allowStorageConsent(consent: true);
      setState(() {
        if (response.statusCode == 200) {
          _result = 'Storage Consent allowed successfully!\n${response.body}';
        } else {
          _result =
              'Failed to allow storage consent: ${response.statusCode}\n${response.body}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// End Session.
  Future<void> _endSession() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    try {
      final response = await _biometry!.endSession();
      setState(() {
        if (response.statusCode == 200) {
          _result = 'Session ended successfully!\n${response.body}';
        } else {
          _result =
              'Failed to end the session: ${response.statusCode}\n${response.body}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Processes the scanned video.
  Future<void> _processVideo() async {
    if (!_formKey.currentState!.validate() || _capturedVideo == null) {
      _showSnackBar(
          'Please provide all required information and scan a person.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    try {
      final response = await _biometry!.processVideo(
        videoFile: _capturedVideo!,
      );
      setState(() {
        if (response.statusCode == 200) {
          _result = 'Video processed successfully!\n${response.body}';
        } else {
          _result =
              'Failed to process video: ${response.statusCode}\n${response.body}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Processes document authentication.
  Future<void> _processDocAuth() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    try {
      final response = await _biometry!.docAuth();
      setState(() {
        if (response.statusCode == 200) {
          _result = 'Document authenticated successfully!\n${response.body}';
        } else {
          _result =
              'Failed to authenticate document: ${response.statusCode}\n${response.body}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Processes face match.
  Future<void> _faceMatch() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    try {
      final response = await _biometry!.faceMatch();
      setState(() {
        if (response.statusCode == 200) {
          _result = 'Face match processed successfully!\n${response.body}';
        } else {
          _result =
              'Failed to match face: ${response.statusCode}\n${response.body}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Launches the BiometryScannerWidget as a modal window to scan the person's face.
  Future<void> _scanPerson() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar(
          'Biometry is not initialized. Please press the Initialize button.');
      return;
    }
    // Pass the phrase from your text field to the scanner widget.
    final phrase = _biometry!.phraseAsIntList;
    final captured = await showModalBottomSheet<File?>(
      backgroundColor: Colors.white,
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Column(
          children: [
            Spacer(),
            Text(
              "Please Speak Only The Following Numbers",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.normal,
                fontSize: 14,
              ),
            ),
            SizedBox(
              height: 10,
            ),
            Row(
              children: [
                Spacer(),
                Icon(Icons.spatial_audio_off_rounded, color: Colors.grey),
                SizedBox(
                  width: 10,
                ),
                Text(
                  " ${_biometry?.phraseAsIntList}",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Spacer(),
              ],
            ),
            SizedBox(
              child: BiometryScannerWidget(
                phrase: phrase,
                onCapture: (capturedVideo) {
                  dev.log('Captured video: ${capturedVideo.path}');
                  Navigator.pop(context, capturedVideo);
                },
              ),
            ),
            Spacer(),
          ],
        );
      },
    );
    if (captured != null) {
      setState(() {
        _capturedVideo = captured;
      });
      _showSnackBar('Person scanned successfully!');
    } else {
      _showSnackBar('Person scanning cancelled or failed.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometry Example'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              // Token Field
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(labelText: 'Token'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your token';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              // Full Name Field
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              // Initialize Biometry Button
              ElevatedButton(
                onPressed: _initializeBiometry,
                child: const Text('Initialize Biometry'),
              ),
              //--
              // Scan Person Button
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _isBiometryInitialized ? _scanPerson : null,
                child: const Text('Scan Person'),
              ),
              //--
              // Display the random phrase
              const SizedBox(height: 20),
              Text(
                "Phrase: ${_biometry?.phraseAsIntList}",
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _isProcessing
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        // Process Video uses the scanned video.
                        ElevatedButton(
                          onPressed:
                              (_capturedVideo != null && _isBiometryInitialized)
                                  ? _processVideo
                                  : null,
                          child: const Text('Process Video'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed:
                              _isBiometryInitialized ? _processDocAuth : null,
                          child: const Text('Document Auth'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _isBiometryInitialized ? _faceMatch : null,
                          child: const Text('Face Match Against Document'),
                        ),
                        // Consent Button
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed:
                              _isBiometryInitialized ? _allowConsent : null,
                          child: const Text('Consent to Use Biometrics'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _isBiometryInitialized
                              ? _allowStorageConsent
                              : null,
                          child: const Text('Consent to Store Biometrics'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed:
                              _isBiometryInitialized ? _endSession : null,
                          child: const Text('End Session'),
                        ),
                        const SizedBox(height: 10),
                        // Scan Person Button (opens the scanner widget as a modal)
                      ],
                    ),
              const SizedBox(height: 20),
              if (_capturedVideo != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Scanned Video Path: ${_capturedVideo!.path}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

              // Display the captured video from the faceImagePath
              if (_biometry?.faceImagePath?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image(
                    image: FileImage(File(_biometry!.faceImagePath!)),
                  ),
                ),
              if (_result.isNotEmpty)
                Text(
                  _result,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
