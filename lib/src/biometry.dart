import 'dart:convert'; // for jsonEncode
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';

/// A class to handle biometry-related operations against the Biometry v2 API.
///   - [initialize] - Initializes the Biometry class with a token, user ID, full name and an optional HTTP client.
///   - [scanDocument] - Scans a document using the flutter_doc_scanner plugin.
///   - [docAuth] - Verifies a document using the biometry service.
///   - [enrolFace] - Enrolls a face using the biometry service.
///   - [enrolVoice] - Enrolls voice using the biometry service.
///   - [faceMatch] - Matches the enrolled/captured face against a live video or the session video.
///   - [livenessCheck] - Checks face liveness, active speaker detection and visual speech recognition on a video.
///   - [faceVerify] - Verifies a face in a video against the user's enrolled face template.
///   - [voiceVerify] - Verifies a speaker in a video against the user's enrolled voice template.
///   - [deepfakeCheck] - Submits a video for asynchronous deepfake analysis.
///   - [approveConsent] - Records the user's approval of a consent template.
///   - [getConsentApprovals] - Retrieves the user's recorded consent approvals.
///   - [assertConsent] - Ensures the user has approved a given consent template.
class Biometry {
  static const String _host = 'https://api.biometrysolutions.com';
  static const String _apiGateway = '$_host/api-gateway';
  static const String _apiGatewayV2 = '$_apiGateway/v2';
  static String _phrase = '';

  // Generate a 7-digit number with unique digits from 0-9.

  final String _token;
  final http.Client _client;

  /// The session ID to be sent with all requests to encapsulate usage.
  final String sessionId;

  /// The opaque, customer-provided identity key sent to the API as `user_id`.
  final String _userId;

  /// The full name of the user. Kept for display purposes only — it is not
  /// transmitted to the v2 API, which identifies users by [_userId].
  final String fullName;

  /// The path to the image of the person.
  String? _faceImagePath;

  /// Cached consent approvals, populated on first call to [assertConsent].
  List<ConsentApproval>? _cachedApprovals;

  /// Client app name sent as `X-Client-App` on every API request.
  final String? _clientAppName;

  /// Client app version sent as `X-Client-App-Version` on every API request.
  final String? _clientAppVersion;

  Biometry._(
    this._token,
    this._client,
    this.sessionId,
    this._userId,
    this.fullName, {
    String? clientAppName,
    String? clientAppVersion,
  })  : _clientAppName = clientAppName,
        _clientAppVersion = clientAppVersion;

  /// Initializes the Biometry class with a token, user ID, full name and an optional HTTP client.
  ///
  /// [clientAppName] and [clientAppVersion] are optional. When provided, they
  /// are sent as `X-Client-App` and `X-Client-App-Version` headers on every
  /// request to the API gateway.
  static Future<Biometry> initialize({
    required String token,
    required String userId,
    required String fullName,
    http.Client? client,
    String? clientAppName,
    String? clientAppVersion,
  }) async {
    await _configureAudioSession();

    final http.Client httpClient = client ?? http.Client();
    String id = await _fetchSessionId(
      token,
      httpClient,
      clientAppName: clientAppName,
      clientAppVersion: clientAppVersion,
    );
    final rand = Random.secure();

    final allDigits = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rand);
    final digits = allDigits.take(7).toList();
    Biometry._phrase = digits.join();

    if (kDebugMode) {
      debugPrint("Phrase: $_phrase");
    }
    return Biometry._(
      token,
      httpClient,
      id,
      userId,
      fullName,
      clientAppName: clientAppName,
      clientAppVersion: clientAppVersion,
    );
  }

  /// Disposes the Biometry class.
  static void dispose() {
    // Dispose of any resources if needed.
    // For example, if you have a camera controller, you might want to dispose of it here.
  }

  /// Resets the internal phrase to a new random 7-digit sequence with unique digits (0-9).
  /// Uses the same generation logic as during initialization.
  static void resetPhrase() {
    final rand = Random.secure();
    final allDigits = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rand);
    final digits = allDigits.take(7).toList();
    _phrase = digits.join();
    if (kDebugMode) {
      debugPrint("Phrase: $_phrase");
    }
  }

  static Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.mixWithOthers,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
  }

  /// Return the face path captured by docAuth
  String? get faceImagePath => _faceImagePath;

  /// Fetches a new session ID from the API.
  static Future<String> _fetchSessionId(
    String token,
    http.Client client, {
    String? clientAppName,
    String? clientAppVersion,
  }) async {
    final uri = Uri.parse('$_apiGatewayV2/sessions?warmup=true');

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (clientAppName != null && clientAppName.isNotEmpty) {
      request.headers['X-Client-App'] = clientAppName;
    }
    if (clientAppVersion != null && clientAppVersion.isNotEmpty) {
      request.headers['X-Client-App-Version'] = clientAppVersion;
    }

    final response = await client.send(request);
    final responseBody = await http.Response.fromStream(response);
    if (kDebugMode) {
      debugPrint("Response from API: ${responseBody.body}");
    }
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(responseBody.body);
      final dataRaw = jsonResponse['data'];
      final id = dataRaw is Map<String, dynamic>
          ? dataRaw['session_id'] as String?
          : null;
      if (id == null || id.isEmpty) {
        throw Exception(
            'Failed to retrieve session ID: missing session_id in response: ${responseBody.body}');
      }
      if (kDebugMode) {
        debugPrint("Session ID: $id");
      }
      return id;
    } else {
      throw Exception('Failed to retrieve session ID: ${responseBody.body}');
    }
  }

  /// Ends the session by sending a POST request to the API.
  ///
  /// If [phoneNumber] is provided, the API additionally runs a SIM-swap
  /// fraud check for that number.
  Future<http.Response> endSession({String? phoneNumber}) async {
    final uri = Uri.parse('$_apiGatewayV2/sessions/$sessionId/end');
    debugPrint("End session: $uri");

    final body = jsonEncode({
      if (phoneNumber != null) 'phone_number': phoneNumber,
    });

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    _addClientAppHeaders(request);
    final response = await _client.send(request);
    if (response.statusCode == 200) {
      // clear all files in the temp directory
      final tempDir = await getTemporaryDirectory();
      final tempFiles = tempDir.listSync();
      for (var file in tempFiles) {
        if (file is File) {
          await file.delete();
        }
      }
    }
    return http.Response.fromStream(response);
  }

  /// Scans a document using the `flutter_doc_scanner` plugin and returns the
  /// path to the first scanned image.
  ///
  /// Returns an empty `String` if the user cancels the scan or scanning
  /// fails.
  Future<String> scanDocument() async {
    try {
      final result =
          await FlutterDocScanner().getScannedDocumentAsImages(page: 1);
      if (result == null || result.images.isEmpty) {
        return "";
      }
      return result.images.first;
    } on DocScanException catch (e) {
      debugPrint("Document scan failed: ${e.code} ${e.message}");
      return "";
    }
  }

  /// Returns the phrase as a string of words.
  String get phraseWords {
    return _phrase.split('').map((e) {
      switch (e) {
        case '0':
          return 'Zero';
        case '1':
          return 'One';
        case '2':
          return 'Two';
        case '3':
          return 'Three';
        case '4':
          return 'Four';
        case '5':
          return 'Five';
        case '6':
          return 'Six';
        case '7':
          return 'Seven';
        case '8':
          return 'Eight';
        case '9':
          return 'Nine';
        default:
          return e; // Leave the character as-is
      }
    }).join(' ');
  }

  /// Returns the phrase as a string of integers.
  String get phraseAsIntList {
    return _phrase.split('').join(', ');
  }

  /// Enrolls a face using the biometry service.
  Future<http.Response> enrolFace() async {
    if (_faceImagePath == null) {
      throw Exception(
          'No face image available. Please authenticate a document first.');
    }

    final uri = Uri.parse('$_apiGatewayV2/enrollments/face');

    final requestJson = jsonEncode({'user_id': _userId});

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(
        await http.MultipartFile.fromPath(
          'face',
          _faceImagePath!,
          contentType: _faceImagePath!.toLowerCase().endsWith('.jpg') ||
                  _faceImagePath!.toLowerCase().endsWith('.jpeg')
              ? MediaType('image', 'jpeg')
              : MediaType('image', 'png'),
        ),
      );

    if (kDebugMode) {
      print('Enrol Face request: $request');
      print('Headers: ${request.headers}');
    }

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        print('Error Enrol Face response: ${response.body}');
      }
      throw Exception('Face enrollment failed: ${response.statusCode}');
    }

    if (kDebugMode) {
      print('Enrol Face response: ${response.body}');
    }
    return response;
  }

  /// Enrolls voice using the biometry service.
  Future<http.Response> enrolVoice({
    required File videoFile,
    String? vocabulary,
  }) async {
    final uri = Uri.parse('$_apiGatewayV2/enrollments/voice');

    final fileExtension = videoFile.path.split('.').last.toLowerCase();
    final contentType =
        MediaType('video', fileExtension); // Dynamic content type

    final requestJson = jsonEncode({
      'user_id': _userId,
      'phrase': phraseWords,
      if (vocabulary != null) 'vocabulary': vocabulary,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(await http.MultipartFile.fromPath(
        'voice',
        videoFile.path,
        contentType: contentType,
      ));

    if (kDebugMode) {
      print('Enrol Voice request: $request');
      print('Headers: ${request.headers}');
      print('Fields: ${request.fields}');
    }

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        print('Error Enrol Voice response: ${response.body}');
      }
      throw Exception('Voice enrollment failed: ${response.statusCode}');
    }

    if (kDebugMode) {
      print('Enrol Voice response: ${response.body}');
    }
    return response;
  }

  /// Verifies an identity document using the biometry service.
  ///
  /// Sends a POST request to the biometry service with the scanned document.
  /// Returns a `Future<http.Response>` object.
  /// Throws an `Exception` if the request fails.
  ///
  /// [provider] and [mrzProvider] override the project's default document
  /// authenticity / MRZ extraction providers when supplied.
  Future<http.Response> docAuth({String? provider, String? mrzProvider}) async {
    final uri = Uri.parse('$_apiGatewayV2/documents/check');
    var docFile = await scanDocument();
    debugPrint("docFile: $docFile");
    final filePath = _stripFileUriPrefix(docFile);

    if (docFile.isEmpty) {
      throw Exception('Document scan failed: No document file path received');
    }

    final requestJson = jsonEncode({
      'session_id': sessionId,
      if (provider != null) 'provider': provider,
      if (mrzProvider != null) 'mrz_provider': mrzProvider,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(await http.MultipartFile.fromPath(
        'document',
        filePath,
        contentType: filePath.toLowerCase().endsWith('.jpg') ||
                filePath.toLowerCase().endsWith('.jpeg')
            ? MediaType('image', 'jpeg')
            : MediaType('image', 'png'),
      ));

    // Send the request and wait for the response stream to complete.
    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'DocAuth failed with status code: ${response.statusCode}');
    }

    // Process the face image from the response.
    await _processFaceImage(response);

    return response;
  }

  /// Matches the captured/enrolled face against either a fresh [video] or,
  /// by default, the video already captured for the current session.
  ///
  /// When [useSessionVideo] is `false`, [video] is required.
  Future<http.Response> faceMatch({
    File? video,
    bool useSessionVideo = true,
  }) async {
    if (_faceImagePath == null) {
      throw Exception('No face image path provided');
    }
    if (!useSessionVideo && video == null) {
      throw Exception(
          'A video file is required when useSessionVideo is false.');
    }

    final uri = Uri.parse('$_apiGatewayV2/face-match');

    final requestJson = jsonEncode({
      'user_id': _userId,
      'session_id': sessionId,
      'use_session_video': useSessionVideo,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(
        await http.MultipartFile.fromPath(
          'reference_image',
          _faceImagePath!,
          contentType: _faceImagePath!.toLowerCase().endsWith('.jpg') ||
                  _faceImagePath!.toLowerCase().endsWith('.jpeg')
              ? MediaType('image', 'jpeg')
              : MediaType('image', 'png'),
        ),
      );

    if (!useSessionVideo && video != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'video',
        video.path,
        contentType:
            MediaType('video', video.path.split('.').last.toLowerCase()),
      ));
    }

    if (kDebugMode) {
      print('request: $request');
      print("use_session_video: $useSessionVideo");
    }

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    // Check response status code.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        print('Error Face match response: ${response.body}');
      }
      throw Exception('Face match request failed: ${response.statusCode}');
    }
    if (kDebugMode) {
      print('Face match response: ${response.body}');
    }
    return response;
  }

  /// Checks face liveness, active speaker detection, and visual speech
  /// recognition anti-spoofing on [video].
  ///
  /// This is one of the endpoints that together replace the v1
  /// `processVideo` call, which has no direct v2 equivalent. Pass service
  /// names in [excludeServices] (from `face_liveness_detection`,
  /// `active_speaker_detection`, `visual_speech_recognition`,
  /// `face_recognition`, `voice_recognition`) to skip them.
  Future<http.Response> livenessCheck({
    required File video,
    List<String>? excludeServices,
    String? trigger,
    String? vocabulary,
  }) async {
    final uri = Uri.parse('$_apiGatewayV2/liveness');

    final requestJson = jsonEncode({
      'user_id': _userId,
      'phrase': phraseWords,
      'session_id': sessionId,
      if (excludeServices != null) 'services': {'exclude': excludeServices},
      if (trigger != null) 'trigger': trigger,
      if (vocabulary != null) 'vocabulary': vocabulary,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(await http.MultipartFile.fromPath(
        'video',
        video.path,
        contentType:
            MediaType('video', video.path.split('.').last.toLowerCase()),
      ));

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Liveness check failed: ${response.statusCode}');
    }
    return response;
  }

  /// Verifies the face in [video] against the user's enrolled face template.
  Future<http.Response> faceVerify({
    required File video,
    String? vocabulary,
  }) async {
    final uri = Uri.parse('$_apiGatewayV2/face-verify');

    final requestJson = jsonEncode({
      'user_id': _userId,
      'phrase': phraseWords,
      'session_id': sessionId,
      if (vocabulary != null) 'vocabulary': vocabulary,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(await http.MultipartFile.fromPath(
        'video',
        video.path,
        contentType:
            MediaType('video', video.path.split('.').last.toLowerCase()),
      ));

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Face verify failed: ${response.statusCode}');
    }
    return response;
  }

  /// Verifies the speaker in [video] against the user's enrolled voice
  /// template.
  Future<http.Response> voiceVerify({
    required File video,
    String? vocabulary,
  }) async {
    final uri = Uri.parse('$_apiGatewayV2/voice-verify');

    final requestJson = jsonEncode({
      'user_id': _userId,
      'phrase': phraseWords,
      'session_id': sessionId,
      if (vocabulary != null) 'vocabulary': vocabulary,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(await http.MultipartFile.fromPath(
        'voice',
        video.path,
        contentType:
            MediaType('video', video.path.split('.').last.toLowerCase()),
      ));

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Voice verify failed: ${response.statusCode}');
    }
    return response;
  }

  /// Submits [video] for asynchronous deepfake analysis.
  ///
  /// The response body contains a check `status`
  /// (`pending`/`processing`/`completed`/`failed`) rather than an immediate
  /// verdict — poll `GET /v2/deepfake/checks/{id}` (not yet wrapped by this
  /// SDK) using the returned check `id` if you need the final result.
  Future<http.Response> deepfakeCheck({required File video}) async {
    final uri = Uri.parse('$_apiGatewayV2/deepfake/checks');

    final requestJson = jsonEncode({
      'user_id': _userId,
      'session_id': sessionId,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..fields['request'] = requestJson
      ..files.add(await http.MultipartFile.fromPath(
        'video',
        video.path,
        contentType:
            MediaType('video', video.path.split('.').last.toLowerCase()),
      ));

    _addClientAppHeaders(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Deepfake check failed: ${response.statusCode}');
    }
    return response;
  }

  /// Records that the user has approved the consent template [consentId].
  ///
  /// Note: the v2 API has no revoke/unapprove endpoint — unlike v1's
  /// `allowConsent(consent: false)`, there is currently no way to withdraw
  /// a recorded approval through this API.
  Future<http.Response> approveConsent({required String consentId}) async {
    final uri = Uri.parse(
        '$_apiGatewayV2/consents/${Uri.encodeComponent(consentId)}/approve/${Uri.encodeComponent(_userId)}');

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token';

    debugPrint("request: $request");
    _addClientAppHeaders(request);
    final response = await _client.send(request);
    final httpResponse = await http.Response.fromStream(response);
    if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
      _cachedApprovals = null;
    }
    return httpResponse;
  }

  Future<void> _processFaceImage(http.Response response) async {
    try {
      final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));

      if (jsonResponse is! Map<String, dynamic> ||
          !jsonResponse.containsKey('data')) {
        dev.log('Error: Invalid JSON response - missing or invalid "data" key');
        return;
      }

      final dataRaw = jsonResponse['data'];
      if (dataRaw is! Map<String, dynamic>) {
        dev.log('Error: Invalid JSON response - "data" is null or not a map');
        return;
      }
      final data = dataRaw;
      if (!data.containsKey('portrait_photo') ||
          data['portrait_photo'] is! String) {
        dev.log('Error: Missing or invalid "portrait_photo" key');
        return;
      }

      final portraitPhotoBase64 = data['portrait_photo'] as String;

      if (!_isValidBase64(portraitPhotoBase64)) {
        dev.log('Error: Invalid base64 string format');
        return;
      }

      dev.log(
          'Portrait photo received (${portraitPhotoBase64.length} base64 chars)');

      final imageBytes = base64Decode(portraitPhotoBase64);

      final directory = await getApplicationDocumentsDirectory();
      final filePath =
          '${directory.path}/face_match_${DateTime.now().millisecondsSinceEpoch}.png';

      final imageFile = File(filePath);
      await imageFile.writeAsBytes(imageBytes);

      _faceImagePath = filePath;

      dev.log('Face image saved to: $filePath');
    } catch (e, stackTrace) {
      dev.log('Error processing face image: $e',
          error: e, stackTrace: stackTrace);
      return;
    }
  }

  bool _isValidBase64(String str) {
    if (str.isEmpty) return false;

    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=]+$');
    if (!base64Pattern.hasMatch(str)) return false;

    if (str.length % 4 != 0) return false;

    if (str.contains('=')) {
      if (!str.endsWith('=') && !str.endsWith('==')) return false;
      final paddingStart = str.indexOf('=');
      if (str.substring(paddingStart).contains(RegExp(r'[^=]'))) return false;
    }

    try {
      base64Decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _addClientAppHeaders(http.BaseRequest request) {
    if (_clientAppName != null && _clientAppName!.isNotEmpty) {
      request.headers['X-Client-App'] = _clientAppName!;
    }
    if (_clientAppVersion != null && _clientAppVersion!.isNotEmpty) {
      request.headers['X-Client-App-Version'] = _clientAppVersion!;
    }
  }

  String _stripFileUriPrefix(String uri) {
    if (uri.startsWith('file://')) {
      return uri.replaceFirst('file://', '');
    }
    return uri;
  }

  /// Ensures the user has approved the consent template [consentId],
  /// fetching and caching the user's approvals on first call. Subsequent
  /// calls within the same session reuse the cached value without an extra
  /// network request.
  Future<void> assertConsent({required String consentId}) async {
    final approvals = _cachedApprovals ?? await getConsentApprovals();
    _cachedApprovals = approvals;

    final hasApproval = approvals.any((a) => a.consentId == consentId);
    if (!hasApproval) {
      throw Exception('User "$_userId" has not approved consent "$consentId".');
    }
  }

  /// Retrieves all consent approvals recorded for the current user.
  Future<List<ConsentApproval>> getConsentApprovals() async {
    final uri = Uri.parse(
        '$_apiGatewayV2/consents/my-approvals/${Uri.encodeComponent(_userId)}');

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
        if (_clientAppName != null && _clientAppName!.isNotEmpty)
          'X-Client-App': _clientAppName!,
        if (_clientAppVersion != null && _clientAppVersion!.isNotEmpty)
          'X-Client-App-Version': _clientAppVersion!,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to fetch consent approvals: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final dataRaw = json['data'];
    if (dataRaw is! List) {
      throw Exception(
        'Unexpected consent approvals response format: ${response.body}',
      );
    }
    final approvals = dataRaw
        .map((e) => ConsentApproval.fromJson(e as Map<String, dynamic>))
        .toList();
    _cachedApprovals = approvals;
    return approvals;
  }
}

/// A single consent approval record, as returned by
/// [Biometry.getConsentApprovals].
class ConsentApproval {
  /// The ID of the consent template that was approved.
  final String consentId;

  /// The user who approved it.
  final String userId;

  /// When the approval was recorded.
  final DateTime approvedAt;

  /// Creates an approval record with the given fields.
  const ConsentApproval({
    required this.consentId,
    required this.userId,
    required this.approvedAt,
  });

  /// Parses [ConsentApproval] from the API JSON shape.
  factory ConsentApproval.fromJson(Map<String, dynamic> json) =>
      ConsentApproval(
        consentId: json['consent_id'] as String,
        userId: json['user_id'] as String,
        approvedAt: DateTime.parse(json['approved_at'] as String),
      );
}
