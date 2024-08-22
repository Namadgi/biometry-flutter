import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class Biometry {
  static const String _baseUrl = 'https://dev.biometry.namadgi.com.au';
  final String _token;
  final http.Client _client;

  Biometry._(this._token, this._client);

  static Biometry initialize({required String token, http.Client? client}) {
    return Biometry._(token, client ?? http.Client());
  }

  Future<http.Response> processVideo({
    required String fullname,
    required File videoFile,
    required String phrase,
  }) async {
    final uri = Uri.parse('$_baseUrl/process-video');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['X-User-Fullname'] = fullname
      ..files.add(await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        contentType: MediaType('video', 'mp4'),
      ))
      ..fields['phrase'] = phrase;

    final response = await _client.send(request);
    return http.Response.fromStream(response);
  }
}
