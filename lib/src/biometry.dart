import 'dart:convert'; // for jsonEncode
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:recase/recase.dart';
import 'package:uuid/uuid.dart';

/// A class to handle biometry-related operations.
///   - [initialize] - Initializes the Biometry class with a token, full name and an optional HTTP client.
///   - [scanDocument] - Scans a document using the flutter_doc_scanner plugin.
///   - [docAuth] - Processes a document using the biometry service.
///   - [processVideo] - Processes a video file using the biometry service. If both consents are given, automatically performs enrollment.
///   - [enrolFace] - Enrolls a face using the biometry service (required if consents not given).
///   - [enrolVoice] - Enrolls voice using the biometry service (required if consents not given).
class Biometry {
  static const String _host = 'https://api.biometrysolutions.com';
  static const String _apiGateway = '$_host/api-gateway';
  static const String _consentUrl = '$_host/api-consent';
  static String _phrase = '';

  // Generate a 7-digit number with unique digits from 0-9.

  final String _token;
  final http.Client _client;

  /// The session ID to be sent with all requests to encapsulate usage.
  final String sessionId;

  /// The full name of the user, stored for subsequent API calls.
  final String _fullName;

  /// The path to the image of the person.
  String? _faceImagePath;

  /// Geolocation information to be included in transactions.
  BiometryGeoLocation? _geoLocation;

  Biometry._(
    this._token,
    this._client,
    this.sessionId,
    this._fullName, {
    BiometryGeoLocation? geoLocation,
  }) : _geoLocation = geoLocation;

  /// Initializes the Biometry class with a token, full name and an optional HTTP client.
  static Future<Biometry> initialize({
    required String token,
    required String fullName,
    http.Client? client,
    BiometryGeoLocation? geoLocation,
  }) async {
    await _configureAudioSession();

    final http.Client httpClient = client ?? http.Client();
    String id = await _fetchSessionId(token, httpClient, fullName,
        geoLocation: geoLocation);
    final rand = Random.secure();

    final allDigits = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rand);
    final digits = allDigits.take(7).toList();
    Biometry._phrase = digits.join();

    debugPrint("Phrase: $_phrase");
    return Biometry._(token, httpClient, id, fullName,
        geoLocation: geoLocation);
  }

  /// Sets or updates the geolocation information.
  void setGeoLocation(BiometryGeoLocation? geoLocation) {
    _geoLocation = geoLocation;
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
    debugPrint("Phrase: $_phrase");
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
    http.Client client,
    String fullName, {
    BiometryGeoLocation? geoLocation,
  }) async {
    final uri = Uri.parse('$_apiGateway/sessions/start?warmup=true');

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['X-User-Fullname'] = fullName;

    if (geoLocation != null) {
      final geoJson = jsonEncode(geoLocation.toJson());
      request.headers['X-Geo-Location'] = geoJson;
    }

    final response = await client.send(request);
    final responseBody = await http.Response.fromStream(response);
    if (kDebugMode) {
      debugPrint("Response from API: ${responseBody.body}");
    }
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(responseBody.body);
      String data = jsonResponse['data'] ?? '';
      if (kDebugMode) {
        debugPrint("Data: $data");
      }
      return data;
    } else {
      throw Exception('Failed to retrieve session ID: ${responseBody.body}');
    }
  }

  void _addGeoLocationHeader(http.BaseRequest request) {
    if (_geoLocation != null) {
      final geoJson = jsonEncode(_geoLocation!.toJson());
      request.headers['X-Geo-Location'] = geoJson;
    }
  }

  /// Ends the session by sending a POST request to the API.
  Future<http.Response> endSession() async {
    final uri = Uri.parse('$_apiGateway/sessions/end/$sessionId');
    debugPrint("End session: $uri");
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName;

    _addGeoLocationHeader(request);

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

  /// Scans a document using the `flutter_doc_scanner` plugin.
  ///
  /// By default, it fetches a PDF for Android and a PNG for iOS.
  ///
  /// Returns:
  /// - A `String` representing the path to the scanned document.
  /// - An empty `String` if the scanning fails or no document is found.
  ///
  /// Throws:
  /// - `PlatformException` if the scanning process fails.
  Future<String> scanDocument() async {
    dynamic scannedDocuments;
    try {
      scannedDocuments =
          await FlutterDocScanner().getScannedDocumentAsImages(page: 1) ??
              'Unknown platform documents';
    } on PlatformException catch (_) {
      scannedDocuments = 'Failed to get scanned documents.';
    }
    // ios: scannedDocuments is a list of file paths
    if (scannedDocuments is List && scannedDocuments.isNotEmpty) {
      return scannedDocuments[0];
    }
    // android: scannedDocuments is a map with a string value for 'uri'
    if (scannedDocuments is Map && scannedDocuments.containsKey('Uri')) {
      final uriString = scannedDocuments['Uri'];
      if (uriString is String) {
        final uriMatch = RegExp(r'imageUri=([^}]+)').firstMatch(uriString);
        if (uriMatch != null) {
          final fileUri = uriMatch.group(1);
          return fileUri ?? "";
        } else {
          debugPrint("Regex did not match in uriString: $uriString");
        }
      } else {
        debugPrint("uriString is not a String: $uriString");
      }
    }
    return "";
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

    final uri = Uri.parse('$_apiGateway/enroll/face');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName
      ..headers['X-Request-User-Provided-ID'] = sessionId
      ..headers['X-Session-ID'] = sessionId
      ..files.add(
        await http.MultipartFile.fromPath(
          'face',
          _faceImagePath!,
          contentType: MediaType(
              'image', _faceImagePath!.split('.').last), // Dynamic content type
        ),
      )
      ..fields['is_document'] = 'false';

    // Device info gathering
    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }
    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);

    if (kDebugMode) {
      print('Enrol Face request: $request');
      print('Headers: ${request.headers}');
    }

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
  }) async {
    final uri = Uri.parse('$_apiGateway/enroll/voice');

    final fileExtension = videoFile.path.split('.').last.toLowerCase();
    final contentType =
        MediaType('video', fileExtension); // Dynamic content type

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName
      ..headers['X-Request-User-Provided-ID'] = sessionId
      ..headers['X-Session-ID'] = sessionId
      ..files.add(await http.MultipartFile.fromPath(
        'voice',
        videoFile.path,
        contentType: contentType,
      ))
      ..fields['unique_id'] = Uuid().v4() // Generate unique ID
      ..fields['phrase'] = phraseWords;

    // Device info gathering
    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }
    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);

    if (kDebugMode) {
      print('Enrol Voice request: $request');
      print('Headers: ${request.headers}');
      print('Fields: ${request.fields}');
    }

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

  /// Processes a document using the biometry service.
  /// Sends a POST request to the biometry service with the scanned document.
  /// Detailed device information is gathered and sent in the header as a JSON string.
  /// Returns a `Future<http.Response>` object.
  /// Throws an `Exception` if the request fails.
  /// Developer docs: https://developer.biometrysolutions.com/concepts/doc-auth/
  ///
  Future<http.Response> docAuth() async {
    final uri = Uri.parse('$_apiGateway/docauth/check');
    var docFile = await scanDocument();
    debugPrint("docFile: $docFile");
    final filePath = _stripFileUriPrefix(docFile);

    if (docFile.isEmpty) {
      throw Exception('Document scan failed: No document file path received');
    }

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName
      ..files.add(await http.MultipartFile.fromPath(
        'document',
        filePath,
        contentType: MediaType('image', 'png'),
      ))
      ..headers['X-Session-ID'] = sessionId;

    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }

    if (kDebugMode) {
      dev.log('Device info: $deviceInfoJson');
    }

    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);

    // Send the request and wait for the response stream to complete.
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    // Process the face image from the response.
    await _processFaceImage(response);

    // Optional: Check the response status code.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'DocAuth failed with status code: ${response.statusCode}');
    }

    return response;
  }

  /// Processes a face match.
  /// Sends a POST request to the biometry service to process the face match.
  /// Detailed device information is gathered and sent in the header as a JSON string.
  /// Returns a `Future<http.Response>` object.
  /// Throws an `Exception` if the request fails.
  /// Developer docs: https://developer.biometrysolutions.com/concepts/face-match/
  Future<http.Response> faceMatch() async {
    // Check if the image path is provided.
    if (_faceImagePath == null) {
      throw Exception('No face image path provided');
    }

    final uri = Uri.parse('$_apiGateway/match-faces');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName
      ..headers['X-Use-Prefilled-Video'] =
          'true' // TODO: make dynamic if needed
      ..headers['X-Session-ID'] = sessionId
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          _faceImagePath!,
          contentType: MediaType('application', 'png'),
        ),
      )
      ..fields['X-Request-User-Provided-ID'] = sessionId;

    // Gather device information.
    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }

    if (kDebugMode) {
      print('request: $request');
      print(
          "X-Use-Prefilled-Video: ${request.headers['X-Use-Prefilled-Video']}");
      print("X-Session-ID: ${request.headers['X-Session-ID']}");
    }
    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);

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

  /// Processes a video file.
  ///
  /// Sends a POST request to the biometry service to process the video.
  /// Detailed device information is gathered and sent in the header as a JSON string.
  ///
  /// If both consent and storage consent have been given, the backend will automatically
  /// perform enrollment (both face and voice) during video processing. Otherwise, it
  /// performs authentication only.
  ///
  /// When automatic enrollment is triggered, the response will include the 'X-Auto-Enroll'
  /// header to indicate that enrollment has started (enrollment is asynchronous).
  Future<http.Response> processVideo({
    required File videoFile,
  }) async {
    final uri = Uri.parse('$_apiGateway/process-video');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName
      ..files.add(await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        contentType: MediaType('video', 'mp4'),
      ))
      ..fields['phrase'] = phraseWords
      ..headers['X-Request-User-Provided-ID'] =
          sessionId //Todo: update when API is updated
      ..headers['X-Session-ID'] = sessionId;
    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }

    if (kDebugMode) {
      print('Device info: $deviceInfoJson');
    }

    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (kDebugMode) {
      final redactedHeaders = Map.of(response.headers)
        ..update('authorization', (_) => 'REDACTED',
            ifAbsent: () => 'REDACTED');
      debugPrint('Process Video Response Status: ${response.statusCode}');
      debugPrint('Process Video Response Headers: $redactedHeaders');
      debugPrint('Process Video Response Body: ${response.body}');
    }

    return response;
  }

  /// Allows consent by sending a consent flag to the API.
  ///
  /// Developer docs: https://developer.biometrysolutions.com/concepts/consent/
  Future<http.Response> allowConsent({required bool consent}) async {
    final uri = Uri.parse('$_consentUrl/consent');

    // Create a JSON body with the consent flag.
    final body = jsonEncode({
      'is_consent_given': consent,
      'user_fullname': _fullName,
    });

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['Content-Type'] = 'application/json'
      ..headers['X-User-Fullname'] = _fullName
      ..headers['X-Request-User-Provided-ID'] = sessionId
      ..body = body;

    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }
    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);
    debugPrint("request: $request");
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Allows Storage consent by sending a consent flag to the API.
  /// This allows Biometry to keep the video and voice data for future use.
  /// Developer docs: https://developer.biometrysolutions.com/concepts/consent/
  Future<http.Response> allowStorageConsent({required bool consent}) async {
    final uri = Uri.parse('$_consentUrl/strg-consent');

    // Create a JSON body with the consent flag.
    final body = jsonEncode({
      'is_consent_given': consent,
      'user_fullname': _fullName,
    });

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['Content-Type'] = 'application/json'
      ..headers['X-User-Fullname'] = _fullName
      ..headers['X-Request-User-Provided-ID'] = sessionId
      ..body = body;

    String deviceInfoJson = '';
    if (Platform.isIOS) {
      deviceInfoJson = await _getIosDeviceInfoJson();
    } else if (Platform.isAndroid) {
      deviceInfoJson = await _getAndroidDeviceInfoJson();
    } else {
      final deviceInfo = await _getDeviceInfo();
      deviceInfoJson = jsonEncode(deviceInfo);
    }
    request.headers['X-Device-Info'] = deviceInfoJson;
    _addGeoLocationHeader(request);
    debugPrint("request: $request");
    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Collects detailed iOS device information and returns it as a JSON string.
  Future<String> _getIosDeviceInfoJson() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final iosInfo = await deviceInfoPlugin.iosInfo;
    final snakeCaseMap = convertKeysToSnakeCase(iosInfo.data);
    return jsonEncode(snakeCaseMap);
  }

  /// Collects detailed Android device information and returns it as a JSON string.
  Future<String> _getAndroidDeviceInfoJson() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final androidInfo = await deviceInfoPlugin.androidInfo;
    final snakeCaseMap = convertKeysToSnakeCase(androidInfo.data);
    return jsonEncode(snakeCaseMap);
  }

  /// Converts the keys of a map (and any nested maps or lists) to snake_case.
  Map<String, dynamic> convertKeysToSnakeCase(Map<String, dynamic> original) {
    return original.map((key, value) {
      final snakeCaseKey = key.snakeCase;
      if (value is Map<String, dynamic>) {
        return MapEntry(snakeCaseKey, convertKeysToSnakeCase(value));
      } else if (value is List) {
        return MapEntry(
          snakeCaseKey,
          value.map((item) {
            if (item is Map<String, dynamic>) {
              return convertKeysToSnakeCase(item);
            }
            return item;
          }).toList(),
        );
      }
      return MapEntry(snakeCaseKey, value);
    });
  }

  /// Collects basic device info for non-mobile platforms.
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    return {
      'device_os': Platform.operatingSystem,
      'device_os_version': Platform.operatingSystemVersion,
    };
  }

  Future<void> _processFaceImage(http.Response response) async {
    try {
      final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));

      if (jsonResponse is! Map<String, dynamic> ||
          !jsonResponse.containsKey('data')) {
        dev.log('Error: Invalid JSON response - missing or invalid "data" key');
        return;
      }

      final data = jsonResponse['data'] as Map<String, dynamic>;
      if (!data.containsKey('face_image_base64') ||
          data['face_image_base64'] is! String) {
        dev.log('Error: Missing or invalid "face_image_base64" key');
        return;
      }

      final faceImageBase64 = data['face_image_base64'] as String;

      if (!_isValidBase64(faceImageBase64)) {
        dev.log('Error: Invalid base64 string format');
        return;
      }

      dev.log('Face image base64: $faceImageBase64');

      final imageBytes = base64Decode(faceImageBase64);

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

  String _stripFileUriPrefix(String uri) {
    if (uri.startsWith('file://')) {
      return uri.replaceFirst('file://', '');
    }
    return uri;
  }
}

/// Represents geolocation information for biometry transactions.
class BiometryGeoLocation {
  /// Latitude coordinate.
  final double lat;

  /// Longitude coordinate.
  final double lng;

  /// Country name or code.
  final String country;

  /// City name.
  final String city;

  /// Optional client IP address.
  final String? ip;

  /// Creates a new [BiometryGeoLocation] instance.
  BiometryGeoLocation({
    required this.lat,
    required this.lng,
    required this.country,
    required this.city,
    this.ip,
  });

  /// Converts the geolocation information to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      'country': country,
      'city': city,
      if (ip != null) 'ip': ip,
    };
  }
}
