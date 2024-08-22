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
      biometry = Biometry.initialize(token: 'test-token');
      mockFile = MockFile();
    });

    test('processVideo returns success response', () async {
      // Arrange
      final mockResponse = http.Response('{"status":"success"}', 200);

      // Mock the behavior of the File class
      when(mockFile.length())
          .thenAnswer((_) async => 12345); // Return a valid length
      when(mockFile.path)
          .thenReturn('test/video.mp4'); // Return a valid file path

      when(mockHttpClient.send(any)).thenAnswer((invocation) async {
        final http.BaseRequest request = invocation.positionalArguments[0];
        return http.StreamedResponse(
          Stream.fromIterable([mockResponse.body.codeUnits]),
          200,
        );
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
