import 'dart:convert';
import 'dart:io';

import 'package:biometry/src/biometry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'biometry_test.mocks.dart';

@GenerateMocks([http.Client, File])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const v2Base = 'https://api.biometrysolutions.com/api-gateway/v2';
  const docScannerChannel = MethodChannel('flutter_doc_scanner');
  // base64 for "hello" — a minimal, validly-formatted payload for the
  // portrait_photo field.
  const validPortraitPhotoBase64 = 'aGVsbG8=';

  Stream<List<int>> bodyStream(String json) =>
      Stream.fromIterable([utf8.encode(json)]);

  final originalPathProviderPlatform = PathProviderPlatform.instance;

  setUpAll(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPathProviderPlatform;
  });

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

      // Stub the doc scanner plugin's platform channel so scanDocument()
      // returns a real, on-disk file instead of hitting a real device.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(docScannerChannel, (call) async {
        if (call.method == 'getScannedDocumentAsImages') {
          return ['test/video.mp4'];
        }
        return null;
      });

      // Stub streamed requests for every v2 endpoint with a representative
      // success response. Individual tests override this locally (via a
      // fresh `when(mockHttpClient.send(any))`) to exercise failure paths.
      when(mockHttpClient.send(any)).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as http.BaseRequest;
        final url = request.url.toString();

        if (url == '$v2Base/sessions?warmup=true') {
          return http.StreamedResponse(
            bodyStream('{"data":{"session_id":"session-id-123"}}'),
            200,
          );
        } else if (url == '$v2Base/documents/check') {
          return http.StreamedResponse(
            bodyStream('{"data":{"portrait_photo":"$validPortraitPhotoBase64",'
                '"first_name":"John","last_name":"Doe"}}'),
            200,
          );
        } else if (url == '$v2Base/enrollments/face') {
          return http.StreamedResponse(
            bodyStream('{"data":{"enrolled":true,"user_id":"john-doe"}}'),
            200,
          );
        } else if (url == '$v2Base/enrollments/voice') {
          return http.StreamedResponse(
            bodyStream('{"data":{"enrolled":true,"user_id":"john-doe"}}'),
            200,
          );
        } else if (url == '$v2Base/face-match') {
          return http.StreamedResponse(
            bodyStream('{"data":{"face_recognition":{"score":0.98}}}'),
            200,
          );
        } else if (url == '$v2Base/liveness') {
          return http.StreamedResponse(
            bodyStream('{"data":{"face_liveness_detection":{"score":0.99}}}'),
            200,
          );
        } else if (url == '$v2Base/face-verify') {
          return http.StreamedResponse(
            bodyStream('{"data":{"face_recognition":{"score":0.97}}}'),
            200,
          );
        } else if (url == '$v2Base/voice-verify') {
          return http.StreamedResponse(
            bodyStream('{"data":{"voice_recognition":{"score":0.95}}}'),
            200,
          );
        } else if (url == '$v2Base/deepfake/checks') {
          return http.StreamedResponse(
            bodyStream('{"data":{"id":"check-1","status":"pending"}}'),
            201,
          );
        } else if (url == '$v2Base/consents/consent-abc/approve/john-doe') {
          return http.StreamedResponse(bodyStream('{"meta":{}}'), 200);
        } else if (url == '$v2Base/sessions/session-id-123/end') {
          return http.StreamedResponse(bodyStream('{"meta":{}}'), 200);
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

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(docScannerChannel, null);
    });

    test('int parsing drops leading zeros', () {
      const phraseWithLeadingZero = '0123456789';
      final parsed = int.parse(phraseWithLeadingZero);
      final reconstructed = parsed.toString();

      expect(reconstructed, isNot(equals(phraseWithLeadingZero)),
          reason: 'Leading zero was dropped after parsing as int');
    });

    group('initialize', () {
      test('throws when the session-start call fails', () async {
        final failingClient = MockClient();
        when(failingClient.send(any)).thenAnswer((_) async =>
            http.StreamedResponse(
                bodyStream('{"error":"invalid token"}'), 401));

        expect(
          () => Biometry.initialize(
            token: 'bad-token',
            userId: 'john-doe',
            fullName: 'John Doe',
            client: failingClient,
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('throws when the response is 200 but session_id is missing',
          () async {
        final malformedClient = MockClient();
        when(malformedClient.send(any)).thenAnswer(
            (_) async => http.StreamedResponse(bodyStream('{"data":{}}'), 200));

        expect(
          () => Biometry.initialize(
            token: 'test-token',
            userId: 'john-doe',
            fullName: 'John Doe',
            client: malformedClient,
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('endSession', () {
      test('ends the session', () async {
        final response = await biometry.endSession();
        expect(response.statusCode, 200);
      });

      test('includes the phone number for a SIM-swap check when provided',
          () async {
        http.Request? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/sessions/session-id-123/end') {
            captured = request as http.Request;
            return http.StreamedResponse(bodyStream('{"meta":{}}'), 200);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.endSession(phoneNumber: '+15551234567');

        expect(captured, isNotNull);
        final body = jsonDecode(captured!.body) as Map<String, dynamic>;
        expect(body['phone_number'], '+15551234567');
      });
    });

    group('docAuth', () {
      test('scans, verifies the document, and captures the portrait photo',
          () async {
        final response = await biometry.docAuth();

        expect(response.statusCode, 200);
        expect(biometry.faceImagePath, isNotNull);
        expect(File(biometry.faceImagePath!).existsSync(), isTrue);
      });

      test('sends the session ID in the multipart request field', () async {
        http.MultipartRequest? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/documents/check') {
            captured = request as http.MultipartRequest;
            return http.StreamedResponse(
              bodyStream(
                  '{"data":{"portrait_photo":"$validPortraitPhotoBase64"}}'),
              200,
            );
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.docAuth();

        expect(captured, isNotNull);
        expect(captured!.files.single.field, 'document');
        final requestJson =
            jsonDecode(captured!.fields['request']!) as Map<String, dynamic>;
        expect(requestJson['session_id'], 'session-id-123');
      });

      test('throws when the API returns a non-2xx status', () async {
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/documents/check') {
            return http.StreamedResponse(
                bodyStream('{"error":"unprocessable"}'), 422);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.docAuth(), throwsA(isA<Exception>()));
      });
    });

    group('enrolFace', () {
      test('throws when no face image has been captured yet', () {
        expect(() => biometry.enrolFace(), throwsA(isA<Exception>()));
      });

      test('enrolls the captured face', () async {
        await biometry.docAuth();

        final response = await biometry.enrolFace();

        expect(response.statusCode, 200);
      });

      test('sends the user_id in the multipart request field', () async {
        await biometry.docAuth();

        http.MultipartRequest? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/enrollments/face') {
            captured = request as http.MultipartRequest;
            return http.StreamedResponse(
              bodyStream('{"data":{"enrolled":true,"user_id":"john-doe"}}'),
              200,
            );
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.enrolFace();

        expect(captured, isNotNull);
        expect(captured!.headers['Authorization'], 'Bearer test-token');
        expect(captured!.files.single.field, 'face');
        final requestJson =
            jsonDecode(captured!.fields['request']!) as Map<String, dynamic>;
        expect(requestJson['user_id'], 'john-doe');
      });

      test('throws when the API returns a non-2xx status', () async {
        await biometry.docAuth();

        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/enrollments/face') {
            return http.StreamedResponse(bodyStream('{"error":"bad"}'), 403);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.enrolFace(), throwsA(isA<Exception>()));
      });
    });

    group('enrolVoice', () {
      test('enrolls the given voice recording', () async {
        final response = await biometry.enrolVoice(videoFile: mockFile);
        expect(response.statusCode, 200);
      });

      test('sends the phrase and user_id in the multipart request field',
          () async {
        http.MultipartRequest? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/enrollments/voice') {
            captured = request as http.MultipartRequest;
            return http.StreamedResponse(
              bodyStream('{"data":{"enrolled":true,"user_id":"john-doe"}}'),
              200,
            );
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.enrolVoice(videoFile: mockFile);

        expect(captured!.files.single.field, 'voice');
        final requestJson =
            jsonDecode(captured!.fields['request']!) as Map<String, dynamic>;
        expect(requestJson['user_id'], 'john-doe');
        expect(requestJson['phrase'], isNotEmpty);
      });

      test('throws when the API returns a non-2xx status', () async {
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/enrollments/voice') {
            return http.StreamedResponse(bodyStream('{"error":"bad"}'), 400);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.enrolVoice(videoFile: mockFile),
            throwsA(isA<Exception>()));
      });
    });

    group('faceMatch', () {
      test('throws when no face image has been captured yet', () {
        expect(() => biometry.faceMatch(), throwsA(isA<Exception>()));
      });

      test('throws when useSessionVideo is false and no video is given',
          () async {
        await biometry.docAuth();

        expect(
          () => biometry.faceMatch(useSessionVideo: false),
          throwsA(isA<Exception>()),
        );
      });

      test('matches against the session video by default', () async {
        await biometry.docAuth();

        final response = await biometry.faceMatch();

        expect(response.statusCode, 200);
      });

      test('matches against an explicit video when useSessionVideo is false',
          () async {
        await biometry.docAuth();

        http.MultipartRequest? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/face-match') {
            captured = request as http.MultipartRequest;
            return http.StreamedResponse(
              bodyStream('{"data":{"face_recognition":{"score":0.98}}}'),
              200,
            );
          }
          fail('Unexpected URL call: ${request.url}');
        });

        final response = await biometry.faceMatch(
          video: mockFile,
          useSessionVideo: false,
        );

        expect(response.statusCode, 200);
        final fields = captured!.files.map((f) => f.field).toSet();
        expect(fields, {'reference_image', 'video'});
        final requestJson =
            jsonDecode(captured!.fields['request']!) as Map<String, dynamic>;
        expect(requestJson['use_session_video'], false);
      });

      test('throws when the API returns a non-2xx status', () async {
        await biometry.docAuth();

        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/face-match') {
            return http.StreamedResponse(
                bodyStream('{"error":"unprocessable"}'), 422);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.faceMatch(), throwsA(isA<Exception>()));
      });
    });

    group('livenessCheck', () {
      test('returns success response', () async {
        final response = await biometry.livenessCheck(video: mockFile);

        expect(response.statusCode, 200);
      });

      test('sends excluded services when provided', () async {
        http.MultipartRequest? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/liveness') {
            captured = request as http.MultipartRequest;
            return http.StreamedResponse(
              bodyStream('{"data":{"face_liveness_detection":{"score":0.99}}}'),
              200,
            );
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.livenessCheck(
          video: mockFile,
          excludeServices: ['voice_recognition'],
        );

        final requestJson =
            jsonDecode(captured!.fields['request']!) as Map<String, dynamic>;
        expect(requestJson['services'], {
          'exclude': ['voice_recognition'],
        });
      });

      test('throws when the API returns a non-2xx status', () async {
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/liveness') {
            return http.StreamedResponse(
                bodyStream('{"error":"unprocessable"}'), 422);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.livenessCheck(video: mockFile),
            throwsA(isA<Exception>()));
      });
    });

    group('faceVerify', () {
      test('returns success response', () async {
        final response = await biometry.faceVerify(video: mockFile);
        expect(response.statusCode, 200);
      });

      test('throws when the API returns a non-2xx status', () async {
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/face-verify') {
            return http.StreamedResponse(bodyStream('{"error":"bad"}'), 404);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.faceVerify(video: mockFile),
            throwsA(isA<Exception>()));
      });
    });

    group('voiceVerify', () {
      test('returns success response', () async {
        final response = await biometry.voiceVerify(video: mockFile);
        expect(response.statusCode, 200);
      });

      test('throws when the API returns a non-2xx status', () async {
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/voice-verify') {
            return http.StreamedResponse(bodyStream('{"error":"bad"}'), 404);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.voiceVerify(video: mockFile),
            throwsA(isA<Exception>()));
      });
    });

    group('deepfakeCheck', () {
      test('submits the video and returns the created check (201)', () async {
        final response = await biometry.deepfakeCheck(video: mockFile);
        expect(response.statusCode, 201);
      });

      test('throws when the API returns a non-2xx/201 status', () async {
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/deepfake/checks') {
            return http.StreamedResponse(
                bodyStream('{"error":"unprocessable"}'), 422);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        expect(() => biometry.deepfakeCheck(video: mockFile),
            throwsA(isA<Exception>()));
      });
    });

    group('consent', () {
      test('approveConsent records the approval', () async {
        final response =
            await biometry.approveConsent(consentId: 'consent-abc');
        expect(response.statusCode, 200);
      });

      test('percent-encodes reserved characters in the consent ID', () async {
        Uri? capturedUri;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.path.contains('/consents/')) {
            capturedUri = request.url;
            return http.StreamedResponse(bodyStream('{"meta":{}}'), 200);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.approveConsent(consentId: 'consent with/slash');

        expect(capturedUri, isNotNull);
        // A raw '/' in consentId would otherwise split into an extra path
        // segment; pathSegments decodes each segment back, so a correctly
        // encoded value still shows up as a single segment here.
        expect(
          capturedUri!.pathSegments,
          [
            'api-gateway',
            'v2',
            'consents',
            'consent with/slash',
            'approve',
            'john-doe'
          ],
        );
      });

      test('getConsentApprovals returns the recorded approvals', () async {
        final approvals = await biometry.getConsentApprovals();

        expect(approvals, hasLength(1));
        expect(approvals.first.consentId, 'consent-abc');
        expect(approvals.first.userId, 'john-doe');
        expect(
            approvals.first.approvedAt, DateTime.parse('2024-01-15T10:30:00Z'));
      });

      test('getConsentApprovals throws when the API call fails', () async {
        when(mockHttpClient.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response('{"error":"unauthorized"}', 401));

        expect(() => biometry.getConsentApprovals(), throwsA(isA<Exception>()));
      });

      test('assertConsent passes when the consent has been approved', () async {
        await expectLater(
            biometry.assertConsent(consentId: 'consent-abc'), completes);
      });

      test('assertConsent throws when the consent has not been approved',
          () async {
        expect(
          () => biometry.assertConsent(consentId: 'consent-not-approved'),
          throwsA(isA<Exception>()),
        );
      });

      test('assertConsent reuses cached approvals on a second call', () async {
        await biometry.assertConsent(consentId: 'consent-abc');

        // The real assertion is the verify() below: it confirms the second
        // call served from the cached approvals list instead of hitting the
        // network again.
        await expectLater(
            biometry.assertConsent(consentId: 'consent-abc'), completes);
        verify(mockHttpClient.get(any, headers: anyNamed('headers'))).called(1);
      });
    });

    group('client app headers', () {
      test('are sent on session start and subsequent requests when provided',
          () async {
        final client = MockClient();
        http.BaseRequest? capturedRequest;
        when(client.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          capturedRequest = request;
          if (request.url.toString() == '$v2Base/sessions?warmup=true') {
            return http.StreamedResponse(
              bodyStream('{"data":{"session_id":"session-id-456"}}'),
              200,
            );
          } else if (request.url.toString() == '$v2Base/liveness') {
            return http.StreamedResponse(bodyStream('{"data":{}}'), 200);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        final clientAppBiometry = await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          fullName: 'John Doe',
          client: client,
          clientAppName: 'MyApp',
          clientAppVersion: '3.2.1',
        );

        expect(capturedRequest!.headers['X-Client-App'], 'MyApp');
        expect(capturedRequest!.headers['X-Client-App-Version'], '3.2.1');

        await clientAppBiometry.livenessCheck(video: mockFile);

        expect(capturedRequest!.headers['X-Client-App'], 'MyApp');
        expect(capturedRequest!.headers['X-Client-App-Version'], '3.2.1');
      });

      test('are omitted when not provided', () async {
        http.BaseRequest? captured;
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          if (request.url.toString() == '$v2Base/liveness') {
            captured = request;
            return http.StreamedResponse(bodyStream('{"data":{}}'), 200);
          }
          fail('Unexpected URL call: ${request.url}');
        });

        await biometry.livenessCheck(video: mockFile);

        expect(captured!.headers.containsKey('X-Client-App'), isFalse);
        expect(captured!.headers.containsKey('X-Client-App-Version'), isFalse);
      });
    });

    group('phrase utilities', () {
      test('phraseWords spells out each digit of the phrase', () {
        Biometry.resetPhrase();
        final words = biometry.phraseWords.split(' ');
        const validWords = {
          'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven',
          'Eight', 'Nine', //
        };

        expect(words, hasLength(7));
        for (final word in words) {
          expect(validWords.contains(word), isTrue,
              reason: '"$word" is not a valid phrase word');
        }
      });

      test('resetPhrase generates 7 unique digits', () {
        Biometry.resetPhrase();
        final digits = biometry.phraseAsIntList.split(', ');

        expect(digits, hasLength(7));
        expect(digits.toSet(), hasLength(7),
            reason: 'Phrase digits should all be unique');
      });
    });
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async =>
      Directory.systemTemp.createTempSync('biometry_test_tmp_').path;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.createTempSync('biometry_test_docs_').path;
}
