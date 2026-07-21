import 'dart:io';

import 'package:biometry/src/biometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'biometry_test.mocks.dart';

@GenerateMocks([http.Client, File])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Biometry', () {
    late MockClient mockHttpClient;
    late Biometry biometry;
    late MockFile mockFile;

    setUp(() async {
      mockHttpClient = MockClient();
      mockFile = MockFile();

      // Stub file properties
      when(mockFile.length()).thenAnswer((_) async => 12345);
      when(mockFile.path).thenReturn('test/video.mp4');
      when(mockFile.exists()).thenAnswer((_) async => true);

      // Stub streamed requests (initialize + livenessCheck)
      when(mockHttpClient.send(any)).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as http.BaseRequest;
        final url = request.url.toString();

        if (url ==
            'https://api.biometrysolutions.com/api-gateway/v2/sessions?warmup=true') {
          return http.StreamedResponse(
            Stream.fromIterable(
                ['{"data":{"session_id":"session-id-123"}}'.codeUnits]),
            200,
          );
        } else if (url ==
            'https://api.biometrysolutions.com/api-gateway/v2/liveness') {
          return http.StreamedResponse(
            Stream.fromIterable(['{"status":"success"}'.codeUnits]),
            200,
          );
        }

        fail('Unexpected URL call: $url');
      });

      // Stub GET requests (getConsentApprovals)
      when(mockHttpClient.get(any, headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response(
                '{"data":[{"consent_id":"consent-abc","user_id":"john-doe",'
                '"approved_at":"2024-01-15T10:30:00Z"}]}',
                200,
              ));

      // Now that we stubbed the sessions call, we can initialize
      biometry = await Biometry.initialize(
        token: 'test-token',
        client: mockHttpClient,
        userId: 'john-doe',
        fullName: 'John Doe',
      );
    });

    test('int parsing drops leading zeros', () {
      const phraseWithLeadingZero = '0123456789';
      final parsed = int.parse(phraseWithLeadingZero);
      final reconstructed = parsed.toString();

      expect(reconstructed, isNot(equals(phraseWithLeadingZero)),
          reason: 'Leading zero was dropped after parsing as int');
    });

    test('livenessCheck returns success response', () async {
      // Act
      final response = await biometry.livenessCheck(video: mockFile);

      // Assert
      expect(response.statusCode, 200);
      expect(response.body, '{"status":"success"}');
    });
  });
}
