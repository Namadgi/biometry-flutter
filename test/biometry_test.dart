import 'dart:io';

import 'package:biometry/src/biometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'biometry_test.mocks.dart';

@GenerateMocks([http.Client, File])
void main() {
  group('Biometry', () {
    late MockClient mockHttpClient;
    late Biometry biometry;
    late MockFile mockFile;

    setUp(() {
      mockHttpClient = MockClient();
      biometry =
          Biometry.initialize(token: 'test-token', client: mockHttpClient);
      mockFile = MockFile();
    });

    test('processVideo returns success response', () async {
      // Arrange
      final mockResponse = http.StreamedResponse(
        Stream.fromIterable(['{"status":"success"}'.codeUnits]),
        200,
      );

      // Mock the behavior of the File class
      when(mockFile.length())
          .thenAnswer((_) async => 12345); // Return a valid length
      when(mockFile.path)
          .thenReturn('test/video.mp4'); // Return a valid file path

      // Mock the behavior of the http.Client class
      when(mockHttpClient.send(any)).thenAnswer((invocation) async {
        final http.MultipartRequest request = invocation.positionalArguments[0];
        expect(request.method, 'POST'); // Ensure the method is POST
        expect(request.url.toString(),
            'https://dev.biometry.namadgi.com.au/process-video'); // Ensure the URL is correct
        expect(request.headers['Authorization'],
            'Bearer test-token'); // Ensure the Authorization header is correct
        expect(request.headers['X-User-Fullname'],
            'John Doe'); // Ensure the X-User-Fullname header is correct
        expect(request.fields['phrase'],
            'one two three four five six seven eight'); // Ensure the phrase field is correct
        return mockResponse;
      });

      // Act
      final response = await biometry.processVideo(
        fullname: 'John Doe',
        videoFile: mockFile,
        phrase: 'one two three four five six seven eight',
      );

      // Assert
      expect(response.statusCode, 200);
      expect(response.body, '{"status":"success"}');
    });
  });
}
