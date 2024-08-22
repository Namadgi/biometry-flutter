import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class Biometry {
  static const String _baseUrl = 'https://dev.biometry.namadgi.com.au';
  final String _token;

  Biometry._(this._token);

  static Biometry initialize({required String token}) {
    return Biometry._(token);
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

    final response = await request.send();
    return http.Response.fromStream(response);
  }
}
