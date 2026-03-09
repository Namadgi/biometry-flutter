import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:biometry/biometry.dart';
import 'package:biometry/biometry_scanner_widget.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// theme constants
class AppTheme {
  static const primaryColor = Color(0xFF1A2132);
  static const accentColor = Color.fromARGB(255, 105, 124, 164);
  static const successColor = Color(0xFF4CAF50);
  static const errorColor = Color(0xFFEF5350);
  static const textColorSecondary = Color(0xFF6B7280);
  static const textColorDisabled = Color(0xFFB0BEC5);

  static final containerDecoration = BoxDecoration(
    color: primaryColor,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
    ],
  );
}

void main() {
  runApp(const BiometryApp());
}

class BiometryApp extends StatelessWidget {
  const BiometryApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const BiometryHomePage(),
    );
  }
}

class BiometryHomePage extends StatefulWidget {
  const BiometryHomePage({Key? key}) : super(key: key);

  @override
  BiometryHomePageState createState() => BiometryHomePageState();
}

class BiometryHomePageState extends State<BiometryHomePage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();

  File? _capturedVideo;
  String _result = '';
  bool _isProcessing = false;
  Biometry? _biometry;
  bool _isBiometryInitialized = false;
  late AnimationController _animationController;
  bool _showResultsPanel = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _fullNameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Performs reverse geocoding to get city and country from coordinates.
  /// Returns a map with 'city' and 'country' keys, or empty map on failure.
  Future<Map<String, String>> _reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=10&addressdetails=1',
        ),
        headers: {'User-Agent': 'BiometryFlutterExample/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return {};
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;

      if (address == null) {
        return {};
      }

      final country = address['country_code']?.toString().toUpperCase() ??
          address['ISO3166-1:alpha2']?.toString().toUpperCase() ??
          address['country']?.toString();

      final city = _extractCity(address);

      return {
        if (country != null) 'country': country,
        if (city != null) 'city': city,
      };
    } catch (e) {
      return {};
    }
  }

  /// Extracts city name from address data, trying multiple field names.
  String? _extractCity(Map<String, dynamic> address) {
    const cityFields = [
      'city',
      'town',
      'village',
      'municipality',
      'suburb',
      'neighbourhood',
      'county',
      'state_district',
      'state',
    ];

    for (final field in cityFields) {
      final value = address[field]?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  /// Checks and requests location permission if needed.
  /// Returns true if permission is granted (whileInUse or always), false otherwise.
  Future<bool> _checkAndRequestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Gets the current device location and returns a BiometryGeoLocation object.
  /// Returns null if location permission is denied or location cannot be determined.
  Future<BiometryGeoLocation?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      if (!await _checkAndRequestPermission()) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final locationInfo = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final country = locationInfo['country'] ?? 'Unknown';
      final city = locationInfo['city'] ?? 'Unknown';

      return BiometryGeoLocation(
        lat: position.latitude,
        lng: position.longitude,
        country: country,
        city: city,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _initializeBiometry() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showSnackBar('Please enter a valid token.');
      return;
    }
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) {
      _showSnackBar('Please enter your full name.');
      return;
    }
    try {
      // Get current device location
      final geoLocation = await _getCurrentLocation();

      _biometry = await Biometry.initialize(
        token: token,
        fullName: fullName,
        geoLocation: geoLocation,
      );
      setState(() {
        _isBiometryInitialized = true;
      });

      final message = geoLocation != null
          ? 'Biometry initialized with location: ${geoLocation.city}, ${geoLocation.country}'
          : 'Biometry initialized successfully';
      _showSnackBar(message);
    } catch (e) {
      _showSnackBar('Failed to initialize Biometry: $e');
    }
  }

  // method to handle biometric operations
  Future<void> _executeBiometricOperation({
    required Future<dynamic> Function() operationCallback,
    required String successMessage,
    required String errorMessage,
    bool requireVideo = false,
  }) async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar('Biometry is not initialized.');
      return;
    }
    if (requireVideo && _capturedVideo == null) {
      _showSnackBar('Please scan a person first.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
      _animationController.forward();
    });
    try {
      final response = await operationCallback();
      setState(() {
        if (response.statusCode == 200 || response.statusCode == 201) {
          _result = '$successMessage\n${response.body}';
        } else {
          _result = '$errorMessage: ${response.statusCode}\n${response.body}';
        }
        _showResultsPanel = true;
      });
    } on HttpException catch (e) {
      setState(() {
        _result = 'Network error: $e';
        _showResultsPanel = true;
      });
    } on FormatException catch (e) {
      setState(() {
        _result = 'Invalid response format: $e';
        _showResultsPanel = true;
      });
    } catch (e) {
      setState(() {
        _result = 'Unexpected error: $e';
        _showResultsPanel = true;
      });
    } finally {
      setState(() {
        _isProcessing = false;
        _animationController.reverse();
      });
    }
  }

  Future<void> _allowConsent() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.allowConsent(consent: true),
      successMessage: 'Consent allowed successfully!',
      errorMessage: 'Failed to allow consent',
    );
  }

  Future<void> _allowStorageConsent() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.allowStorageConsent(consent: true),
      successMessage: 'Storage Consent allowed successfully!',
      errorMessage: 'Failed to allow storage consent',
    );
  }

  Future<void> _getConsentHistory() async {
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar('Biometry is not initialized.');
      return;
    }
    setState(() {
      _isProcessing = true;
      _result = '';
      _animationController.forward();
    });
    try {
      final history = await _biometry!.getConsentHistory();
      setState(() {
        _result = _formatConsentHistory(history);
        _showResultsPanel = true;
      });
    } catch (e) {
      setState(() {
        _result = 'Failed to fetch consent history: $e';
        _showResultsPanel = true;
      });
    } finally {
      setState(() {
        _isProcessing = false;
        _animationController.reverse();
      });
    }
  }

  String _formatConsentHistory(ConsentHistoryResult h) {
    String formatRecord(String label, ConsentRecord r) {
      final entries = r.history
          .map((e) =>
              '  • ${e.isConsentGiven ? "Granted" : "Revoked"} on ${e.date.toLocal()}')
          .join('\n');
      return '$label\n'
          '  Current: ${r.isConsentGiven ? "Granted" : "Revoked"}\n'
          '  History:\n$entries';
    }

    final authConsent = h.consent != null
        ? formatRecord("Authorization Consent:", h.consent!)
        : 'Authorization Consent:\n  Not set';
    final storageConsent = h.storageConsent != null
        ? formatRecord("Storage Consent:", h.storageConsent!)
        : 'Storage Consent:\n  Not set';

    return 'Consent History for ${h.userFullname}\n\n$authConsent\n\n$storageConsent';
  }

  Future<void> _endSession() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.endSession(),
      successMessage: 'Session ended successfully!',
      errorMessage: 'Failed to end session',
    );
    // Clear captured video for security
    if (_capturedVideo != null) {
      await _capturedVideo!.delete();
      setState(() {
        _capturedVideo = null;
      });
    }
  }

  Future<void> _processVideo() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.processVideo(videoFile: _capturedVideo!),
      successMessage: 'Video processed successfully!',
      errorMessage: 'Failed to process video',
      requireVideo: true,
    );
  }

  Future<void> _processDocAuth() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.docAuth(),
      successMessage: 'Document authenticated successfully!',
      errorMessage: 'Failed to authenticate document',
    );
  }

  Future<void> _faceMatch() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.faceMatch(),
      successMessage: 'Face match processed successfully!',
      errorMessage: 'Failed to match face',
    );
  }

  Future<void> _enrollVoice() async {
    await _executeBiometricOperation(
      operationCallback: () =>
          _biometry!.enrolVoice(videoFile: _capturedVideo!),
      successMessage: 'Voice enrolled successfully!',
      errorMessage: 'Failed to enroll voice',
      requireVideo: true,
    );
  }

  Future<void> _enrollFace() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.enrolFace(),
      successMessage: 'Face enrolled successfully!',
      errorMessage: 'Failed to enroll face',
    );
  }

  Future<void> _scanPerson() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please provide all required information.');
      return;
    }
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar('Biometry is not initialized.');
      return;
    }
    final phrase = _biometry!.phraseAsIntList;
    final captured = await showModalBottomSheet<File?>(
      backgroundColor: AppTheme.primaryColor,
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Column(
          children: [
            const Spacer(),
            Text(
              "Please Speak Only The Following Numbers",
              style: TextStyle(
                color: AppTheme.textColorSecondary,
                fontWeight: FontWeight.normal,
              ),
              semanticsLabel: 'Instruction to speak the displayed numbers',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                Icon(Icons.spatial_audio_off_rounded,
                    color: AppTheme.accentColor),
                const SizedBox(width: 10),
                Text(
                  phrase,
                  style: TextStyle(
                    color: AppTheme.accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                  semanticsLabel: 'Numbers to speak: $phrase',
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              child: BiometryScannerWidget(
                phrase: phrase,
                onCapture: (capturedVideo) {
                  dev.log('Captured video: ${capturedVideo.path}');
                  Navigator.pop(context, capturedVideo);
                },
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.errorColor, fontSize: 16),
                semanticsLabel: 'Cancel scanning',
              ),
            ),
            const Spacer(),
          ],
        );
      },
    );
    if (captured != null) {
      setState(() {
        _capturedVideo = captured;
        _showResultsPanel = true;
      });
      _showSnackBar('Person scanned successfully!');
    } else {
      _showSnackBar('Person scanning cancelled or failed.');
    }
  }

  void _showSnackBar(String message) {
    final isSuccess = message.contains('successfully');

    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            semanticsLabel: message,
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor:
              isSuccess ? AppTheme.successColor : AppTheme.errorColor,
        ),
      );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Tooltip(
        message: tooltip ?? '',
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: icon != null
              ? Icon(icon,
                  size: 20,
                  color: onPressed != null
                      ? Colors.white
                      : AppTheme.textColorDisabled)
              : const SizedBox.shrink(),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color:
                  onPressed != null ? Colors.white : AppTheme.textColorDisabled,
            ),
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: onPressed != null
                ? AppTheme.accentColor
                : AppTheme.textColorSecondary,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometric Authentication'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              Icons.info,
              color: _showResultsPanel ? AppTheme.successColor : Colors.white,
            ),
            tooltip: _showResultsPanel ? 'Hide Results' : 'Show Results',
            onPressed: () {
              setState(() {
                _showResultsPanel = !_showResultsPanel;
              });
            },
          ),
        ],
      ),
      backgroundColor: AppTheme.primaryColor,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: AppTheme.containerDecoration,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Initialize Session',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                            semanticsLabel: 'Initialize Session Section',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _tokenController,
                            decoration: InputDecoration(
                              labelText: 'Token',
                              labelStyle:
                                  TextStyle(color: AppTheme.textColorSecondary),
                              prefixIcon: Icon(Icons.vpn_key,
                                  color: AppTheme.accentColor),
                              filled: true,
                              fillColor: const Color(0xFF1F2937),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            style: const TextStyle(color: Colors.white),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your token';
                              }
                              return null;
                            },
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _fullNameController,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              labelStyle:
                                  TextStyle(color: AppTheme.textColorSecondary),
                              prefixIcon: Icon(Icons.person,
                                  color: AppTheme.accentColor),
                              filled: true,
                              fillColor: const Color(0xFF1F2937),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            style: const TextStyle(color: Colors.white),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your full name';
                              }
                              return null;
                            },
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 16),
                          _buildActionButton(
                            label: 'Initialize Biometry',
                            onPressed: _initializeBiometry,
                            icon: Icons.start,
                            tooltip: 'Start the biometric session',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isBiometryInitialized) ...[
                      Container(
                        decoration: AppTheme.containerDecoration,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Consent Management',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                              semanticsLabel: 'Consent Management Section',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Consents are required for enrollment.',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildActionButton(
                              label: 'Consent to Use Biometrics',
                              icon: Icons.check_circle,
                              onPressed: _allowConsent,
                              tooltip: 'Allow use of biometric data',
                            ),
                            _buildActionButton(
                              label: 'Consent to Store Biometrics',
                              icon: Icons.storage,
                              onPressed: _allowStorageConsent,
                              tooltip: 'Allow storage of biometric data',
                            ),
                            _buildActionButton(
                              label: 'View Consent History',
                              icon: Icons.history,
                              onPressed: _getConsentHistory,
                              tooltip: 'Retrieve full consent history',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: AppTheme.containerDecoration,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Biometric Actions',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                              semanticsLabel: 'Biometric Actions Section',
                            ),
                            const SizedBox(height: 16),
                            _buildActionButton(
                              label: 'Scan Person',
                              onPressed: _scanPerson,
                              icon: Icons.camera_alt,
                              tooltip: 'Capture biometric video',
                            ),
                            if (_biometry?.phraseAsIntList != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.format_quote,
                                      color: AppTheme.accentColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Phrase: ${_biometry!.phraseAsIntList}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Color.fromARGB(255, 119, 144, 199),
                                      ),
                                      semanticsLabel:
                                          'Phrase: ${_biometry!.phraseAsIntList}',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            _buildActionButton(
                              label: 'Process Video',
                              onPressed:
                                  _capturedVideo != null ? _processVideo : null,
                              icon: Icons.videocam,
                              tooltip:
                                  'Process the captured video (auto-enrolls if consents given)',
                            ),
                            _buildActionButton(
                              label: 'Document Auth',
                              onPressed: _processDocAuth,
                              icon: Icons.document_scanner,
                              tooltip: 'Scan document for authentication',
                            ),
                            _buildActionButton(
                              label: 'Enroll Face',
                              onPressed: _enrollFace,
                              icon: Icons.face,
                              tooltip: 'Enroll facial biometrics',
                            ),
                            _buildActionButton(
                              label: 'Enroll Voice',
                              onPressed:
                                  _capturedVideo != null ? _enrollVoice : null,
                              icon: Icons.mic,
                              tooltip: 'Enroll voice biometrics',
                            ),
                            _buildActionButton(
                              label: 'Face Match',
                              onPressed: _faceMatch,
                              icon: Icons.compare,
                              tooltip: 'Match face against document',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: AppTheme.containerDecoration,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Session Management',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                              semanticsLabel: 'Session Management Section',
                            ),
                            const SizedBox(height: 16),
                            _buildActionButton(
                              label: 'End Session',
                              icon: Icons.stop,
                              onPressed: _endSession,
                              tooltip: 'End the biometric session',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_showResultsPanel &&
              (_capturedVideo != null ||
                  _biometry?.faceImagePath != null ||
                  _result.isNotEmpty))
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                  minHeight: 100,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3447),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Results',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                            semanticsLabel: 'Results Panel',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _showResultsPanel = false;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_capturedVideo != null)
                        ListTile(
                          leading: Icon(Icons.video_file,
                              color: AppTheme.accentColor),
                          title: Text(
                            'Video: ${_capturedVideo!.path.split('/').last}',
                            style: const TextStyle(
                                fontSize: 16, color: Colors.white),
                            semanticsLabel:
                                'Captured video: ${_capturedVideo!.path.split('/').last}',
                          ),
                        ),
                      if (_biometry?.faceImagePath?.isNotEmpty ?? false)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Captured Face:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              semanticsLabel: 'Captured Face Image',
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_biometry!.faceImagePath!),
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                semanticLabel: 'Captured face image',
                              ),
                            ),
                          ],
                        ),
                      if (_result.isNotEmpty)
                        ListTile(
                          leading: Icon(
                            _result.contains('successfully')
                                ? Icons.check_circle
                                : Icons.error,
                            color: _result.contains('successfully')
                                ? AppTheme.successColor
                                : AppTheme.errorColor,
                          ),
                          title: Text(
                            _result,
                            style: TextStyle(
                              fontSize: 16,
                              color: _result.contains('successfully')
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                            ),
                            semanticsLabel: _result,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isProcessing)
            FadeTransition(
              opacity: _animationController,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      const Color.fromARGB(255, 255, 255, 255)),
                  semanticsLabel: 'Processing',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
