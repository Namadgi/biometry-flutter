import 'dart:convert'; // for jsonEncode
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:recase/recase.dart';

/// A class to handle biometry-related operations.
///   - [initialize] - Initializes the Biometry class with a token, full name and an optional HTTP client.
///   - [scanDocument] - Scans a document using the flutter_doc_scanner plugin.
///   - [docAuth] - Processes a document using the biometry service.
///   - [processVideo] - Processes a video file using the biometry service.
class Biometry {
  static const String _host = 'https://api.biometrysolutions.com';
  static const String _apiGateway = '$_host/api-gateway';
  static const String _consentUrl = '$_host/api-consent';
  static int _phrase = 0;

  // A generate a random number from 1234567890 to 9876543210.

  final String _token;
  final http.Client _client;

  /// The session ID to be sent with all requests to encapsulate usage.
  final String sessionId;

  /// The full name of the user, stored for subsequent API calls.
  final String _fullName;

  Biometry._(this._token, this._client, this.sessionId, this._fullName);

  /// Initializes the Biometry class with a token, full name and an optional HTTP client.
  static Future<Biometry> initialize({
    required String token,
    required String fullName,
    http.Client? client,
  }) async {
    await _configureAudioSession();

    final http.Client httpClient = client ?? http.Client();
    String sessionId = await _fetchSessionId(token, httpClient, fullName);
    Biometry._phrase = Random().nextInt(9000000000 ~/ 10) + 1000000000;
    debugPrint("Phrase: $_phrase");
    return Biometry._(token, httpClient, sessionId, fullName);
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

  /// Fetches a new session ID from the API.
  static Future<String> _fetchSessionId(
      String token, http.Client client, String fullName) async {
    final uri = Uri.parse('$_apiGateway/sessions/start');

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['X-User-Fullname'] = fullName;

    final response = await client.send(request);
    final responseBody = await http.Response.fromStream(response);
    debugPrint("Response from API: ${responseBody.body}");
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(responseBody.body);
      String data = jsonResponse['data'] ?? '';
      debugPrint("Data: $data");
      return data;
    } else {
      throw Exception('Failed to retrieve session ID: ${responseBody.body}');
    }
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
    // By default they fetch PDF for Android and PNG for iOS.
    dynamic scannedDocuments;
    try {
      scannedDocuments =
          await FlutterDocScanner().getScannedDocumentAsImages(page: 1) ??
              'Unknown platform documents';
    } on PlatformException {
      scannedDocuments = 'Failed to get scanned documents.';
    }
    if (scannedDocuments is List) {
      return scannedDocuments[0];
    }
    return "";
  }

  /// Returns the phrase as a string of words.
  String get phraseWords {
    return _phrase.toString().split('').map((e) {
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
    return _phrase.toString().split('').join(', ');
  }

  /// Processes a document.
  Future<http.Response> docAuth() async {
    final uri = Uri.parse('$_apiGateway/docauth/check');

    // Take a photo of the document using flutter_doc_scanner.
    var docFile = await scanDocument();
    debugPrint("docFile: $docFile");

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = _fullName
      ..files.add(await http.MultipartFile.fromPath(
        'document',
        docFile,
        contentType: MediaType('application', 'pdf'),
      ))
      ..fields['X-Request-User-Provided-ID'] = sessionId;

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
    final response = await _client.send(request);

    return http.Response.fromStream(response);
  }

  /// Processes a video file.
  ///
  /// Sends a POST request to the biometry service to process the video.
  /// Detailed device information is gathered and sent in the header as a JSON string.
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
      ..fields['X-Request-User-Provided-ID'] = sessionId;

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
    final response = await _client.send(request);
    return http.Response.fromStream(response);
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
}
