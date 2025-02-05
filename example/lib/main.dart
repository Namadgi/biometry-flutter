import 'dart:io';

import 'package:biometry/biometry.dart';
import 'package:file_picker/file_picker.dart';
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
  final TextEditingController _phraseController = TextEditingController();
  File? _selectedVideo;
  String _result = '';
  bool _isProcessing = false;
  Biometry? _biometry;

  @override
  void dispose() {
    _tokenController.dispose();
    _fullNameController.dispose();
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedVideo = File(result.files.single.path!);
        });
      }
    } catch (e) {
      _showSnackBar('Error picking video: $e');
    }
  }

  Future<void> _processVideo() async {
    // Validate the form and check if a video is selected.
    if (!_formKey.currentState!.validate() || _selectedVideo == null) {
      _showSnackBar('Please provide all required information and select a video.');
      return;
    }

    // Retrieve the token from the text field.
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showSnackBar('Please enter your token.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _result = '';
    });

    // Initialise the Biometry instance with the provided token.
    _biometry = Biometry.initialize(token: token);

    try {
      final response = await _biometry!.processVideo(
        fullname: _fullNameController.text,
        videoFile: _selectedVideo!,
        phrase: _phraseController.text,
      );

      setState(() {
        if (response.statusCode == 200) {
          _result = 'Video processed successfully!\n${response.body}';
        } else {
          _result = 'Failed to process video: ${response.statusCode}\n${response.body}';
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometry Video Processing'),
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
                    return 'Please enter your full name';
                  }
                  return null;
                },
              ),
              // Phrase Field
              TextFormField(
                controller: _phraseController,
                decoration: const InputDecoration(labelText: 'Phrase'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a phrase';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _pickVideo,
                child: const Text('Select Video'),
              ),
              if (_selectedVideo != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Selected Video: ${_selectedVideo!.path.split('/').last}',
                  ),
                ),
              const SizedBox(height: 20),
              _isProcessing
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                onPressed: _selectedVideo != null ? _processVideo : null,
                child: const Text('Process Video'),
              ),
              const SizedBox(height: 20),
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