import 'dart:io';
import 'dart:convert'; // for jsonEncode

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:recase/recase.dart';

/// A class to handle biometry-related operations.
class Biometry {
  static const String _baseUrl = 'https://api.biometrysolutions.com/api-gateway';
  final String _token;
  final http.Client _client;

  Biometry._(this._token, this._client);

  /// Initializes the Biometry class with a token and an optional HTTP client.
  static Biometry initialize({required String token, http.Client? client}) {
    return Biometry._(token, client ?? http.Client());
  }

  /// Processes a video file with the given full name and phrase.
  ///
  /// Sends a POST request to the biometry service to process the video.
  /// For iOS and Android, detailed device information is gathered and sent
  /// in the header as a JSON string.
  ///
  /// Returns an [http.Response] containing the result of the request.
  Future<http.Response> processVideo({
    required String fullName,
    required File videoFile,
    required String phrase,
  }) async {
    final uri = Uri.parse('$_baseUrl/process-video');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = fullName
      ..files.add(await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        contentType: MediaType('video', 'mp4'),
      ))
      ..fields['phrase'] = phrase;

    if (Platform.isIOS) {
      // For iOS, collect the device info and send it as a JSON string in the header.
      final iosDeviceInfo = await _getIosDeviceInfoJson();
      debugPrint('iOS Device Info: $iosDeviceInfo');
      request.headers['X-Device-Info'] = iosDeviceInfo;
    } else if (Platform.isAndroid) {
      // For Android, collect the device info similarly.
      final androidDeviceInfo = await _getAndroidDeviceInfoJson();
      debugPrint('Android Device Info: $androidDeviceInfo');
      request.headers['X-Device-Info'] = androidDeviceInfo;
    } else {
      // For other platforms, send basic device info as form fields.
      final deviceInfo = await _getDeviceInfo();
      request.fields.addAll(deviceInfo);
    }

    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }

  /// Collects detailed iOS device information and returns it as a JSON string.
  Future<String> _getIosDeviceInfoJson() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final iosInfo = await deviceInfoPlugin.iosInfo;
    // Convert the iOS device info to a snake_case map.
    final snakeCaseMap = convertKeysToSnakeCase(iosInfo.data);
    return jsonEncode(snakeCaseMap);
  }

  /// Collects detailed Android device information and returns it as a JSON string.
  Future<String> _getAndroidDeviceInfoJson() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final androidInfo = await deviceInfoPlugin.androidInfo;
    // Convert the Android device info to a snake_case map.
    final snakeCaseMap = convertKeysToSnakeCase(androidInfo.data);
    return jsonEncode(snakeCaseMap);
  }

  /// Converts the keys of a map to snake_case.
  Map<String, dynamic> convertKeysToSnakeCase(Map<String, dynamic> original) {
    return original.map((key, value) => MapEntry(key.snakeCase, value));
  }

  /// Collects basic device info for non-mobile platforms.
  Future<Map<String, String>> _getDeviceInfo() async {
    return {
      'device_os': Platform.operatingSystem,
      'device_os_version': Platform.operatingSystemVersion,
    };
  }
}