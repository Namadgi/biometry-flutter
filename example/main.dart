import 'dart:io';

import 'package:biometry/biometry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(BiometryApp());
}

class BiometryApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biometry Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: BiometryHomePage(),
    );
  }
}

class BiometryHomePage extends StatefulWidget {
  @override
  _BiometryHomePageState createState() => _BiometryHomePageState();
}

class _BiometryHomePageState extends State<BiometryHomePage> {
  final TextEditingController _fullnameController = TextEditingController();
  final TextEditingController _phraseController = TextEditingController();
  File? _selectedVideo;
  String _result = '';
  Biometry? _biometry;

  @override
  void initState() {
    super.initState();
    // Initialize the Biometry instance
    _biometry = Biometry.initialize(
        token:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NTMyNzIwMDQsImp0aSI6IjY0MTg5ZjVkLWJhMzQtNGNhYi05NGNmLTA1ZTgyN2E5MDc1MSIsImlhdCI6MTcyNDI0MTYwNCwiaXNzIjoiYmlvbWV0cnktcHJvamVjdHMiLCJ1c2VyX2lkIjoiYWQzNTE1MDMtZjc2ZC00NjU3LWI5ZjktOTIwODdmMTcxODk3IiwicHJvamVjdF9pZCI6IjIwNDgyZDhhLTZiOTItNDdmOC04YmRiLTM1YjA5Zjc3MzBmNiIsInNlbGVjdGVkX3NlcnZpY2VzIjpbIkFjdGl2ZSBTcGVha2VyIERldGVjdGlvbiIsIlZpc3VhbCBTcGVlY2ggUmVjb2duaXRpb24iLCJGYWNlIExpdmVuZXNzIERldGVjdGlvbiIsIlZvaWNlIFJlY29nbml0aW9uIiwiRmFjZSBSZWNvZ25pdGlvbiJdfQ.sJopHrRJqXwfTuIlCqCUcmEJeutXURmcd6ADdfvljy4');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Biometry Video Processing'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _fullnameController,
              decoration: InputDecoration(labelText: 'Full Name'),
            ),
            TextField(
              controller: _phraseController,
              decoration: InputDecoration(labelText: 'Phrase'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickVideo,
              child: Text('Select Video'),
            ),
            if (_selectedVideo != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                    'Selected Video: ${_selectedVideo!.path.split('/').last}'),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _selectedVideo != null ? _processVideo : null,
              child: Text('Process Video'),
            ),
            SizedBox(height: 20),
            if (_result.isNotEmpty)
              Text(
                _result,
                style:
                    TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedVideo = File(result.files.single.path!);
      });
    }
  }

  Future<void> _processVideo() async {
    if (_fullnameController.text.isEmpty ||
        _phraseController.text.isEmpty ||
        _selectedVideo == null) {
      setState(() {
        _result = 'Please provide all required information and select a video.';
      });
      return;
    }

    try {
      final response = await _biometry!.processVideo(
        fullname: _fullnameController.text,
        videoFile: _selectedVideo!,
        phrase: _phraseController.text,
      );

      setState(() {
        if (response.statusCode == 200) {
          _result = 'Video processed successfully!';
        } else {
          _result = 'Failed to process video: ${response.statusCode}';
        }
      });
    } catch (e) {
      setState(() {
        _result = 'An error occurred: $e';
      });
    }
  }
}
