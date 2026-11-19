import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:biometry/biometry.dart';
import 'package:biometry/biometry_scanner_widget.dart';
import 'package:flutter/material.dart';
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
        color: Colors.black.withValues(alpha: 0.2),
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
  const BiometryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const BiometryHomePage(),
    );
  }
}

class BiometryHomePage extends StatefulWidget {
  const BiometryHomePage({super.key});

  @override
  BiometryHomePageState createState() => BiometryHomePageState();
}

class BiometryHomePageState extends State<BiometryHomePage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  // Your app's own session token, sent to your backend proxy. The example
  // proxy (biometry-web-sdk examples/proxy-server, ALLOW_DEMO_AUTH=1)
  // accepts "demo-app-token".
  final TextEditingController _appTokenController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  // The user ticked the consent checkbox in this app.
  bool _consentAgreed = false;
  ConsentStatus? _consentStatus;
  // The user ID the active session was initialized with; the User ID field
  // may be edited afterwards, so completed requests use this one.
  String? _sessionUserId;
  // Users (per backend) with a consent request still running. Consent
  // requests for one user run one at a time, even across Initialize: a slow
  // Revoke from an old session would otherwise reach the server after the
  // new session gave consent and withdraw it. Other users are not blocked.
  final Set<String> _consentUsersInFlight = {};
  String? get _consentKey => _sessionUserId == null
      ? null
      : '${_proxyBaseUrl ?? 'direct'}|$_sessionUserId';
  bool get _consentInFlight => _consentUsersInFlight.contains(_consentKey);
  // Set in proxy mode: your backend records consent, not the app.
  String? _proxyBaseUrl;
  Map<String, String>? _proxyHeaders;

  File? _capturedVideo;
  String _result = '';
  // Requests still running. Each request ends only its own count, so an
  // old request finishing cannot hide the spinner of a newer one.
  int _pendingRequests = 0;
  bool get _isProcessing => _pendingRequests > 0;
  Biometry? _biometry;
  bool _isBiometryInitialized = false;
  // Bumped on every Initialize tap, so a slower earlier call that finishes
  // late cannot install its session or challenge over a newer one.
  int _initGeneration = 0;
  bool _isInitializing = false;
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
    _baseUrlController.dispose();
    _appTokenController.dispose();
    _userIdController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeBiometry() async {
    final token = _tokenController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final appToken = _appTokenController.text.trim();
    if (token.isEmpty && baseUrl.isEmpty) {
      _showSnackBar('Enter a backend proxy URL, or a token for direct mode.');
      return;
    }
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      _showSnackBar('Please enter a user ID.');
      return;
    }
    final generation = ++_initGeneration;
    // Drop the previous session's challenge, so switching from proxy mode to
    // direct mode never shows the old backend digits.
    Biometry.clearChallenge();
    // A recording made for the old challenge must not be sent with the new
    // session and phrase, so drop it and require a new one.
    final oldVideo = _capturedVideo;
    // Hide the actions until this new session (and its challenge) is ready,
    // so a failed re-initialize never leaves the old session usable.
    setState(() {
      _isInitializing = true;
      _isBiometryInitialized = false;
      _capturedVideo = null;
      // The recorded consent and the ticked agreement belonged to the
      // previous session's user.
      _consentStatus = null;
      _consentAgreed = false;
      _sessionUserId = null;
    });
    if (oldVideo != null) {
      try {
        await oldVideo.delete();
      } catch (_) {
        // Already gone; nothing else to clean up.
      }
    }
    try {
      // Proxy mode: with a base URL the app holds no Biometry token; your
      // backend adds it. The SDK calls the default proxy paths
      // (Biometry.defaultProxyPaths, e.g. <baseUrl>/sessions and
      // <baseUrl>/liveness), which the example proxy serves; pass `paths`
      // if your backend uses other routes. Direct mode (token only) is for
      // testing.
      final appHeaders = baseUrl.isNotEmpty && appToken.isNotEmpty
          ? {'Authorization': 'Bearer $appToken'}
          : null;
      final biometry = await Biometry.initialize(
        token: token.isEmpty ? null : token,
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
        userId: userId,
        // Only used in proxy mode: your backend checks it to know the user.
        headers: appHeaders,
      );
      if (!mounted || generation != _initGeneration) return;
      _proxyBaseUrl = baseUrl.isEmpty ? null : baseUrl;
      _proxyHeaders = appHeaders;
      if (baseUrl.isNotEmpty) {
        // Proxy mode: the backend issues the liveness challenge for this
        // session and writes its own copy into `phrase`, so show its digits.
        final challenge =
            await _fetchChallenge(baseUrl, appHeaders, biometry.sessionId);
        if (!mounted || generation != _initGeneration) return;
        Biometry.setChallenge(challenge);
      }
      setState(() {
        _biometry = biometry;
        _sessionUserId = userId;
        _isBiometryInitialized = true;
      });

      _showSnackBar('Biometry initialized successfully');
    } catch (e) {
      if (!mounted || generation != _initGeneration) return;
      _showSnackBar('Failed to initialize Biometry: $e');
    } finally {
      if (mounted && generation == _initGeneration) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  /// Asks the backend proxy for this session's liveness challenge
  /// (biometry-web-sdk examples/proxy-server: `POST /challenge`). The caller
  /// installs it with Biometry.setChallenge once the session is still current.
  Future<String> _fetchChallenge(
      String baseUrl, Map<String, String>? headers, String sessionId) async {
    final response = await http.post(
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/challenge'),
      headers: {...?headers, 'content-type': 'application/json'},
      body: jsonEncode({'session_id': sessionId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Could not get a liveness challenge: ${response.body}');
    }
    return jsonDecode(response.body)['challenge'] as String;
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
    // A request started for one session must not show its result after
    // Initialize has replaced that session.
    final generation = _initGeneration;
    _beginRequest();
    try {
      final response = await operationCallback();
      if (response.statusCode == 200 || response.statusCode == 201) {
        _showResult(generation, '$successMessage\n${response.body}');
      } else {
        _showResult(generation,
            '$errorMessage: ${response.statusCode}\n${response.body}');
      }
    } on HttpException catch (e) {
      _showResult(generation, 'Network error: $e');
    } on FormatException catch (e) {
      _showResult(generation, 'Invalid response format: $e');
    } catch (e) {
      _showResult(generation, 'Unexpected error: $e');
    } finally {
      _endRequest();
    }
  }

  void _beginRequest() {
    setState(() {
      _pendingRequests++;
      _result = '';
      _animationController.forward();
    });
  }

  void _endRequest() {
    _pendingRequests--;
    if (!mounted) return;
    setState(() {
      if (_pendingRequests == 0) _animationController.reverse();
    });
  }

  /// Shows [text] as the result, unless the request belonged to a session
  /// that Initialize has since replaced.
  void _showResult(int generation, String text) {
    if (!mounted || generation != _initGeneration) return;
    setState(() {
      _result = text;
      _showResultsPanel = true;
    });
  }

  /// Gives or withdraws the user's authorization and storage consent, or
  /// reads it back. Enrollment needs both consents (403 without them).
  /// Returns true when the operation succeeded and its result was shown.
  Future<bool> _runConsentOperation(
      Future<ConsentStatus> Function() operation, String action) async {
    if (_biometry == null || !_isBiometryInitialized) {
      _showSnackBar('Biometry is not initialized.');
      return false;
    }
    final key = _consentKey;
    if (key == null) return false;
    if (_consentUsersInFlight.contains(key)) {
      _showSnackBar('A consent request for this user is still running.');
      return false;
    }
    // A consent request started for one session must not publish its result
    // after Initialize has replaced that session.
    final generation = _initGeneration;
    _consentUsersInFlight.add(key);
    _beginRequest();
    try {
      final status = await operation();
      if (!mounted || generation != _initGeneration) return false;
      setState(() {
        _consentStatus = status;
        _result = 'Consent for ${status.userId}\n\n'
            '  • Authorization: ${status.authorization ? 'given' : 'not given'}\n'
            '  • Storage: ${status.storage ? 'given' : 'not given'}\n\n'
            '${status.canEnrol ? 'Ready to enroll.' : 'Enrollment needs both consents.'}';
        _showResultsPanel = true;
      });
      return true;
    } catch (e) {
      _showResult(generation, 'Failed to $action consent: $e');
      return false;
    } finally {
      // Release the guard only if this request still owns it; a newer
      // session's request may be running and keeps its own guard.
      _consentUsersInFlight.remove(key);
      _endRequest();
    }
  }

  Future<void> _giveConsent() async {
    if (!_consentAgreed) {
      _showSnackBar('Tick the consent checkbox first.');
      return;
    }
    final proxy = _proxyBaseUrl;
    if (proxy != null) {
      await _runConsentOperation(() => _recordConsentOnBackend(proxy), 'give');
      return;
    }
    await _runConsentOperation(() => _biometry!.giveConsent(), 'give');
  }

  /// Proxy mode: the example proxy (biometry-web-sdk examples/proxy-server)
  /// does not forward the SDK's consent calls; it records consent for the
  /// signed-in user itself (`POST /onboarding/consent`).
  Future<ConsentStatus> _recordConsentOnBackend(String baseUrl) async {
    final userId = _sessionUserId;
    if (userId == null) {
      throw StateError('Biometry is not initialized.');
    }
    final response = await http.post(
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/onboarding/consent'),
      headers: {...?_proxyHeaders, 'content-type': 'application/json'},
      body: jsonEncode({'accepted': true}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('${response.statusCode} ${response.body}');
    }
    return ConsentStatus(
        userId: userId,
        authorization: true,
        storage: true);
  }

  Future<void> _checkConsent() async {
    if (_proxyBaseUrl != null) {
      _showSnackBar('In proxy mode your backend records and checks consent.');
      return;
    }
    await _runConsentOperation(() => _biometry!.getConsentStatus(), 'fetch');
  }

  Future<void> _revokeConsent() async {
    if (_proxyBaseUrl != null) {
      _showSnackBar('In proxy mode your backend records and revokes consent.');
      return;
    }
    final revoked =
        await _runConsentOperation(() => _biometry!.revokeConsent(), 'revoke');
    if (!revoked || !mounted) return;
    setState(() => _consentAgreed = false);
  }

  Future<void> _endSession() async {
    // Remember this session's video now: by the time the request finishes,
    // Initialize may have started a new session with its own video.
    final video = _capturedVideo;
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.endSession(),
      successMessage: 'Session ended successfully!',
      errorMessage: 'Failed to end session',
    );
    // Clear captured video for security
    if (video == null) return;
    try {
      await video.delete();
    } catch (_) {
      // Initialize already deleted it.
    }
    if (mounted && _capturedVideo == video) {
      setState(() {
        _capturedVideo = null;
      });
    }
  }

  Future<void> _livenessCheck() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.livenessCheck(video: _capturedVideo!),
      successMessage: 'Liveness check completed!',
      errorMessage: 'Failed to check liveness',
      requireVideo: true,
    );
  }

  Future<void> _faceVerify() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.faceVerify(video: _capturedVideo!),
      successMessage: 'Face verified successfully!',
      errorMessage: 'Failed to verify face',
      requireVideo: true,
    );
  }

  Future<void> _voiceVerify() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.voiceVerify(video: _capturedVideo!),
      successMessage: 'Voice verified successfully!',
      errorMessage: 'Failed to verify voice',
      requireVideo: true,
    );
  }

  Future<void> _deepfakeCheck() async {
    await _executeBiometricOperation(
      operationCallback: () => _biometry!.deepfakeCheck(video: _capturedVideo!),
      successMessage: 'Deepfake check submitted!',
      errorMessage: 'Failed to submit deepfake check',
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
    final generation = _initGeneration;
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
    if (captured != null && (!mounted || generation != _initGeneration)) {
      // Recorded for the old session's phrase; it must not be sent with
      // the new session.
      try {
        await captured.delete();
      } catch (_) {
        // Already gone.
      }
      if (mounted) _showSnackBar('Session changed; please scan again.');
      return;
    }
    if (!mounted) return;
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
                            controller: _baseUrlController,
                            decoration: InputDecoration(
                              labelText: 'Backend proxy URL (recommended)',
                              hintText: 'https://your-backend.example.com',
                              labelStyle:
                                  TextStyle(color: AppTheme.textColorSecondary),
                              prefixIcon: Icon(Icons.dns,
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
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _appTokenController,
                            decoration: InputDecoration(
                              labelText: 'App token for your backend (proxy mode)',
                              hintText: 'demo-app-token',
                              labelStyle:
                                  TextStyle(color: AppTheme.textColorSecondary),
                              prefixIcon: Icon(Icons.lock,
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
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tokenController,
                            decoration: InputDecoration(
                              labelText: 'Token (direct mode, testing only)',
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
                              if ((value == null || value.trim().isEmpty) &&
                                  _baseUrlController.text.trim().isEmpty) {
                                return 'Enter a token or a backend proxy URL';
                              }
                              return null;
                            },
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _userIdController,
                            decoration: InputDecoration(
                              labelText: 'User ID',
                              labelStyle:
                                  TextStyle(color: AppTheme.textColorSecondary),
                              prefixIcon: Icon(Icons.badge,
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
                                return 'Please enter a user ID';
                              }
                              return null;
                            },
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 16),
                          _buildActionButton(
                            label: 'Initialize Biometry',
                            onPressed:
                                _isInitializing ? null : _initializeBiometry,
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
                              'Enrollment requires the user\'s authorization and '
                              'storage consent to process and store their biometric '
                              'data. Ask for it before enrolling. In proxy mode your '
                              'backend records it (Give Consent calls its POST '
                              '/onboarding/consent). Custom consent templates do not '
                              'unlock enrollment.',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              value: _consentAgreed,
                              onChanged: _consentInFlight
                                  ? null
                                  : (value) => setState(
                                      () => _consentAgreed = value ?? false),
                              activeColor: AppTheme.accentColor,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'I agree that Biometry may process and store my '
                                'biometric data to verify my identity.',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            if (_consentStatus != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  _consentStatus!.canEnrol
                                      ? 'Consent recorded: ready to enroll.'
                                      : 'Consent not recorded: enrollment will fail.',
                                  style: TextStyle(
                                    color: _consentStatus!.canEnrol
                                        ? AppTheme.accentColor
                                        : const Color(0xFFF87171),
                                  ),
                                ),
                              ),
                            _buildActionButton(
                              label: 'Give Consent',
                              icon: Icons.check_circle,
                              onPressed: _consentInFlight ? null : _giveConsent,
                              tooltip:
                                  'Record the user\'s authorization and storage consent',
                            ),
                            _buildActionButton(
                              label: 'Check Consent',
                              icon: Icons.fact_check,
                              // Proxy mode: the SDK's consent calls throw;
                              // your backend checks consent instead.
                              onPressed: _proxyBaseUrl == null && !_consentInFlight
                                  ? _checkConsent
                                  : null,
                              tooltip: _proxyBaseUrl == null
                                  ? 'Show the consent recorded for this user'
                                  : 'In proxy mode your backend checks consent',
                            ),
                            _buildActionButton(
                              label: 'Revoke Consent',
                              icon: Icons.block,
                              onPressed: _proxyBaseUrl == null && !_consentInFlight
                                  ? _revokeConsent
                                  : null,
                              tooltip: _proxyBaseUrl == null
                                  ? 'Withdraw both consents'
                                  : 'In proxy mode your backend withdraws consent',
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
                              label: 'Liveness Check',
                              onPressed: _capturedVideo != null
                                  ? _livenessCheck
                                  : null,
                              icon: Icons.videocam,
                              tooltip:
                                  'Check face liveness and anti-spoofing on the captured video',
                            ),
                            _buildActionButton(
                              label: 'Verify Face (video)',
                              onPressed:
                                  _capturedVideo != null ? _faceVerify : null,
                              icon: Icons.face_retouching_natural,
                              tooltip:
                                  'Verify the face in the captured video against the enrolled template',
                            ),
                            _buildActionButton(
                              label: 'Verify Voice',
                              onPressed:
                                  _capturedVideo != null ? _voiceVerify : null,
                              icon: Icons.record_voice_over,
                              tooltip:
                                  'Verify the speaker in the captured video against the enrolled template',
                            ),
                            _buildActionButton(
                              label: 'Deepfake Check',
                              onPressed: _capturedVideo != null
                                  ? _deepfakeCheck
                                  : null,
                              icon: Icons.security,
                              tooltip:
                                  'Submit the captured video for asynchronous deepfake analysis',
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
                      color: Colors.black.withValues(alpha: 0.2),
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
