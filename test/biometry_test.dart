import 'dart:convert';
import 'dart:io';

import 'package:biometry/src/biometry.dart';
import 'package:flutter/foundation.dart';
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
        // ignore: deprecated_member_use_from_same_package
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

    group('user consents', () {
      const consentsUrl = '$v2Base/users/john-doe/consents';

      // Captures each PUT to the consents endpoint and answers with the
      // state the request asked for.
      List<http.Request> stubConsentPuts({int status = 200}) {
        final puts = <http.Request>[];
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.Request;
          if (request.url.toString() != consentsUrl) {
            fail('Unexpected URL call: ${request.url}');
          }
          puts.add(request);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.StreamedResponse(
            bodyStream(jsonEncode({
              'data': {
                'user_id': 'john-doe',
                'authorization': body['authorization'] ?? false,
                'storage': body['storage'] ?? false,
              },
              'meta': {},
            })),
            status,
          );
        });
        return puts;
      }

      test('giveConsent gives both consents by default', () async {
        final puts = stubConsentPuts();

        final status = await biometry.giveConsent();

        expect(puts, hasLength(1));
        expect(puts.single.method, 'PUT');
        expect(puts.single.headers['Authorization'], 'Bearer test-token');
        expect(puts.single.headers['Content-Type'], startsWith('application/json'));
        expect(jsonDecode(puts.single.body),
            {'authorization': true, 'storage': true});
        expect(status.userId, 'john-doe');
        expect(status.authorization, isTrue);
        expect(status.storage, isTrue);
        expect(status.canEnrol, isTrue);
      });

      test('giveConsent sends only the selected consent', () async {
        final puts = stubConsentPuts();

        await biometry.giveConsent(storage: false);

        expect(jsonDecode(puts.single.body), {'authorization': true});
      });

      test('revokeConsent withdraws the selected consents', () async {
        final puts = stubConsentPuts();

        await biometry.revokeConsent();
        await biometry.revokeConsent(authorization: false);

        expect(jsonDecode(puts[0].body),
            {'authorization': false, 'storage': false});
        expect(jsonDecode(puts[1].body), {'storage': false});
      });

      test('give and revoke reject selecting nothing', () {
        expect(() => biometry.giveConsent(authorization: false, storage: false),
            throwsArgumentError);
        expect(
            () => biometry.revokeConsent(authorization: false, storage: false),
            throwsArgumentError);
      });

      test('giveConsent throws when the API call fails', () async {
        stubConsentPuts(status: 400);

        expect(() => biometry.giveConsent(), throwsA(isA<Exception>()));
      });

      test('getConsentStatus returns the recorded state', () async {
        Uri? capturedUri;
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[0] as Uri;
          return http.Response(
            '{"data":{"user_id":"john-doe","authorization":true,'
            '"storage":false},"meta":{}}',
            200,
          );
        });

        final status = await biometry.getConsentStatus();

        expect(capturedUri.toString(), consentsUrl);
        expect(status.authorization, isTrue);
        expect(status.storage, isFalse);
        expect(status.canEnrol, isFalse);
      });

      test('direct mode calls the v2 consents URL with the user id encoded',
          () async {
        const encodedUrl = '$v2Base/users/user%201%2F%C3%A4/consents';
        final b = await Biometry.initialize(
          token: 'test-token',
          client: mockHttpClient,
          userId: 'user 1/ä',
        );
        final sent = <http.Request>[];
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.Request;
          sent.add(request);
          return http.StreamedResponse(
            bodyStream('{"data":{"user_id":"user 1/ä",'
                '"authorization":true,"storage":true},"meta":{}}'),
            200,
          );
        });
        Uri? getUri;
        when(mockHttpClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((invocation) async {
          getUri = invocation.positionalArguments[0] as Uri;
          return http.Response(
            '{"data":{"user_id":"user 1/ä","authorization":true,'
            '"storage":true},"meta":{}}',
            200,
          );
        });

        await b.giveConsent();
        await b.revokeConsent();
        await b.getConsentStatus();

        expect(sent.map((r) => r.url.toString()), [encodedUrl, encodedUrl]);
        expect(sent.map((r) => r.method), ['PUT', 'PUT']);
        expect(getUri.toString(), encodedUrl);
      });

      test('getConsentStatus throws when the API call fails', () async {
        when(mockHttpClient.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response('{"error":"unauthorized"}', 401));

        expect(() => biometry.getConsentStatus(), throwsA(isA<Exception>()));
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

    group('direct mode (no baseUrl)', () {
      test('sends the token to the default API host on every call', () async {
        final requests = <http.BaseRequest>[];
        final client = MockClient();
        when(client.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          requests.add(request);
          final body = request.url.path.endsWith('/sessions')
              ? '{"data":{"session_id":"s-1"}}'
              : '{"data":{}}';
          return http.StreamedResponse(bodyStream(body), 200);
        });
        when(client.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response('{"data":[]}', 200));

        final direct = await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          client: client,
        );
        await direct.livenessCheck(video: mockFile);
        await direct.getConsentApprovals();

        expect(requests.map((r) => r.url.toString()), [
          '$v2Base/sessions?warmup=true',
          '$v2Base/liveness',
        ]);
        for (final r in requests) {
          expect(r.headers['Authorization'], 'Bearer test-token');
        }
        final getCall =
            verify(client.get(captureAny, headers: captureAnyNamed('headers')))
                .captured;
        expect(getCall[0].toString(),
            '$v2Base/consents/my-approvals/john-doe');
        expect(getCall[1], {'Authorization': 'Bearer test-token'});
      });

      test('keeps the /api-gateway/v2 URLs on every call', () async {
        final requests = <http.BaseRequest>[];
        final client = MockClient();
        when(client.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          requests.add(request);
          final path = request.url.path;
          final body = path.endsWith('/sessions')
              ? '{"data":{"session_id":"s-1"}}'
              : path.endsWith('/documents/check')
                  ? '{"data":{"portrait_photo":"$validPortraitPhotoBase64"}}'
                  : '{"data":{}}';
          return http.StreamedResponse(bodyStream(body), 200);
        });
        when(client.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response('{"data":[]}', 200));

        final direct = await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          client: client,
        );
        await direct.docAuth();
        await direct.enrolFace();
        await direct.enrolVoice(videoFile: mockFile);
        await direct.faceMatch();
        await direct.livenessCheck(video: mockFile);
        await direct.faceVerify(video: mockFile);
        await direct.voiceVerify(video: mockFile);
        await direct.deepfakeCheck(video: mockFile);
        await direct.approveConsent(consentId: 'consent-abc');
        await direct.endSession();
        await direct.getConsentApprovals();

        expect(requests.map((r) => r.url.toString()), [
          '$v2Base/sessions?warmup=true',
          '$v2Base/documents/check',
          '$v2Base/enrollments/face',
          '$v2Base/enrollments/voice',
          '$v2Base/face-match',
          '$v2Base/liveness',
          '$v2Base/face-verify',
          '$v2Base/voice-verify',
          '$v2Base/deepfake/checks',
          '$v2Base/consents/consent-abc/approve/john-doe',
          '$v2Base/sessions/s-1/end',
        ]);
        expect(
            verify(client.get(captureAny, headers: anyNamed('headers')))
                .captured
                .single
                .toString(),
            '$v2Base/consents/my-approvals/john-doe');
      });

      test('ignores paths, even invalid ones, with a debugPrint warning',
          () async {
        final printed = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) printed.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);

        final direct = await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          paths: const {
            ProxyOperation.liveness: 'not-a-path',
            ProxyOperation.startSession: '/start',
          },
          client: mockHttpClient,
        );
        await direct.livenessCheck(video: mockFile);

        expect(
            printed.where(
                (m) => m.contains('paths only apply with baseUrl')),
            hasLength(1));
        final urls = verify(mockHttpClient.send(captureAny))
            .captured
            .map((r) => (r as http.BaseRequest).url.toString())
            .toList();
        expect(urls.sublist(urls.length - 2),
            ['$v2Base/sessions?warmup=true', '$v2Base/liveness']);
      });

      test('throws ArgumentError when there is no token and no baseUrl',
          () async {
        final client = MockClient();
        await expectLater(
          Biometry.initialize(userId: 'john-doe', client: client),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          Biometry.initialize(token: '', userId: 'john-doe', client: client),
          throwsA(isA<ArgumentError>()),
        );
        verifyNever(client.send(any));
      });

      test('ignores headers and headersProvider, with a debugPrint warning',
          () async {
        final printed = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) printed.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);

        final requests = <http.BaseRequest>[];
        final client = MockClient();
        when(client.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          requests.add(request);
          final body = request.url.path.endsWith('/sessions')
              ? '{"data":{"session_id":"s-1"}}'
              : '{"data":{}}';
          return http.StreamedResponse(bodyStream(body), 200);
        });
        when(client.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response('{"data":[]}', 200));
        var providerCalls = 0;

        final direct = await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          headers: {'Authorization': 'Bearer app-jwt', 'X-App': '1'},
          headersProvider: () {
            providerCalls++;
            return {'X-Provided': '1'};
          },
          client: client,
        );
        await direct.livenessCheck(video: mockFile);
        await direct.getConsentApprovals();

        expect(
            printed.where((m) => m.contains('only apply with baseUrl')),
            hasLength(1));
        expect(providerCalls, 0);
        for (final r in requests) {
          expect(r.url.toString(), startsWith(v2Base));
          expect(r.headers['Authorization'], 'Bearer test-token');
          expect(r.headers.containsKey('X-App'), isFalse);
          expect(r.headers.containsKey('X-Provided'), isFalse);
        }
        final getHeaders = verify(
                client.get(any, headers: captureAnyNamed('headers')))
            .captured
            .single as Map<String, String>;
        expect(getHeaders, {'Authorization': 'Bearer test-token'});
      });

      test('does not warn without headers in direct mode', () async {
        final printed = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) printed.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);

        await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          headers: const {},
          client: mockHttpClient,
        );
        expect(printed.where((m) => m.contains('only apply with baseUrl')),
            isEmpty);
      });

      test('fullName is optional, deprecated and kept on the instance',
          () async {
        // ignore: deprecated_member_use_from_same_package
        expect(biometry.fullName, 'John Doe');

        final noName = await Biometry.initialize(
          token: 'test-token',
          userId: 'john-doe',
          client: mockHttpClient,
        );
        // ignore: deprecated_member_use_from_same_package
        expect(noName.fullName, '');
      });
    });

    group('proxy mode (baseUrl)', () {
      const proxy = 'https://app.example.com/biometry';

      late MockClient client;
      late List<http.BaseRequest> requests;

      setUp(() {
        client = MockClient();
        requests = [];
        when(client.send(any)).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          requests.add(request);
          final url = request.url.toString();
          if (url.contains('/api-gateway/')) {
            fail('Proxy request kept the /api-gateway prefix: $url');
          }
          if (request.url.query == 'warmup=true') {
            return http.StreamedResponse(
                bodyStream('{"data":{"session_id":"s-proxy"}}'), 200);
          }
          if (request.url.path.endsWith('/documents/check')) {
            return http.StreamedResponse(
                bodyStream(
                    '{"data":{"portrait_photo":"$validPortraitPhotoBase64"}}'),
                200);
          }
          if (url.startsWith('$proxy/')) {
            return http.StreamedResponse(bodyStream('{"data":{}}'), 200);
          }
          fail('Request left the proxy: $url');
        });
        when(client.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response('{"data":[]}', 200));
      });

      test('sends every request to baseUrl with no Authorization header',
          () async {
        final b = await Biometry.initialize(
          baseUrl: proxy,
          userId: 'john-doe',
          client: client,
        );
        expect(b.sessionId, 's-proxy');

        await b.livenessCheck(video: mockFile);
        await b.faceVerify(video: mockFile);
        await b.approveConsent(consentId: 'consent-abc');
        await b.endSession();
        await b.getConsentApprovals();

        expect(requests.map((r) => r.url.toString()), [
          '$proxy/sessions?warmup=true',
          '$proxy/liveness',
          '$proxy/face-verify',
          '$proxy/consents/consent-abc/approve/john-doe',
          '$proxy/sessions/s-proxy/end',
        ]);
        for (final r in requests) {
          expect(r.headers.containsKey('Authorization'), isFalse,
              reason: '${r.url} must not carry an Authorization header');
        }
        final getCall =
            verify(client.get(captureAny, headers: captureAnyNamed('headers')))
                .captured;
        expect(getCall[0].toString(),
            '$proxy/consents/my-approvals/john-doe');
        expect((getCall[1] as Map).containsKey('Authorization'), isFalse);
      });

      test('consent methods throw StateError without sending a request',
          () async {
        final b = await Biometry.initialize(
          baseUrl: proxy,
          userId: 'john-doe',
          client: client,
        );
        requests.clear();
        clearInteractions(client);

        final calls = <String, Future<ConsentStatus> Function()>{
          'giveConsent': b.giveConsent,
          'revokeConsent': b.revokeConsent,
          'getConsentStatus': b.getConsentStatus,
        };
        for (final entry in calls.entries) {
          await expectLater(
            entry.value(),
            throwsA(isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                startsWith('${entry.key} is not available in proxy mode'),
                contains('POST /onboarding/consent'),
              ),
            )),
          );
        }

        expect(requests, isEmpty);
        verifyNever(client.send(any));
        verifyNever(client.get(any, headers: anyNamed('headers')));
      });

      test('consent methods throw StateError even with a token', () async {
        final b = await Biometry.initialize(
          token: 'test-token',
          baseUrl: proxy,
          userId: 'john-doe',
          client: client,
        );
        requests.clear();

        await expectLater(b.giveConsent(), throwsStateError);
        await expectLater(b.revokeConsent(), throwsStateError);
        await expectLater(b.getConsentStatus(), throwsStateError);
        expect(requests, isEmpty);
      });

      test('sends custom headers on every request', () async {
        final b = await Biometry.initialize(
          baseUrl: '$proxy/',
          userId: 'john-doe',
          headers: {'X-App-Session': 'app-session-1'},
          clientAppName: 'MyApp',
          client: client,
        );
        await b.livenessCheck(video: mockFile);
        await b.getConsentApprovals();

        expect(requests.first.url.toString(), '$proxy/sessions?warmup=true',
            reason: 'trailing slash on baseUrl is dropped');
        for (final r in requests) {
          expect(r.headers['X-App-Session'], 'app-session-1');
          expect(r.headers['X-Client-App'], 'MyApp');
          expect(r.headers.containsKey('Authorization'), isFalse);
        }
        final getHeaders = verify(
                client.get(any, headers: captureAnyNamed('headers')))
            .captured
            .single as Map<String, String>;
        expect(getHeaders['X-App-Session'], 'app-session-1');
      });

      test('headersProvider is called before every request, after headers',
          () async {
        var calls = 0;
        final b = await Biometry.initialize(
          baseUrl: proxy,
          userId: 'john-doe',
          headers: {'Authorization': 'Bearer static', 'X-Static': 's'},
          headersProvider: () async => {'authorization': 'Bearer jwt-${++calls}'},
          client: client,
        );
        await b.livenessCheck(video: mockFile);
        await b.getConsentApprovals();

        expect(calls, 3);
        expect(requests.map((r) => r.headers['Authorization']),
            ['Bearer jwt-1', 'Bearer jwt-2']);
        expect(requests.every((r) => r.headers['X-Static'] == 's'), isTrue);
        final getHeaders = verify(
                client.get(any, headers: captureAnyNamed('headers')))
            .captured
            .single as Map<String, String>;
        expect(getHeaders, {'X-Static': 's', 'authorization': 'Bearer jwt-3'});
      });

      test('a synchronous headersProvider works too', () async {
        await Biometry.initialize(
          baseUrl: proxy,
          userId: 'john-doe',
          headersProvider: () => {'X-App-Session': 'sync'},
          client: client,
        );
        expect(requests.single.headers['X-App-Session'], 'sync');
      });

      test('a custom Authorization header replaces the token header',
          () async {
        final b = await Biometry.initialize(
          token: 'project-token',
          baseUrl: proxy,
          userId: 'john-doe',
          headers: {'authorization': 'Bearer app-user-jwt'},
          client: client,
        );
        await b.getConsentApprovals();

        final r = requests.single;
        expect(r.headers['Authorization'], 'Bearer app-user-jwt');
        final getHeaders = verify(
                client.get(any, headers: captureAnyNamed('headers')))
            .captured
            .single as Map<String, String>;
        expect(getHeaders, {'authorization': 'Bearer app-user-jwt'});
      });

      test('sends the token to baseUrl when both are set', () async {
        await Biometry.initialize(
          token: 'project-token',
          baseUrl: proxy,
          userId: 'john-doe',
          client: client,
        );
        expect(requests.single.url.toString(), '$proxy/sessions?warmup=true');
        expect(requests.single.headers['Authorization'], 'Bearer project-token');
      });

      test('uses the v2 paths without the /api-gateway/v2 prefix', () async {
        final b = await Biometry.initialize(
          baseUrl: proxy,
          userId: 'john-doe',
          client: client,
        );
        await b.docAuth();
        await b.enrolFace();
        await b.enrolVoice(videoFile: mockFile);
        await b.faceMatch();
        await b.livenessCheck(video: mockFile);
        await b.faceVerify(video: mockFile);
        await b.voiceVerify(video: mockFile);
        await b.deepfakeCheck(video: mockFile);
        await b.approveConsent(consentId: 'consent-abc');
        await b.endSession();
        await b.getConsentApprovals();

        expect(requests.map((r) => r.url.toString()), [
          '$proxy/sessions?warmup=true',
          '$proxy/documents/check',
          '$proxy/enrollments/face',
          '$proxy/enrollments/voice',
          '$proxy/face-match',
          '$proxy/liveness',
          '$proxy/face-verify',
          '$proxy/voice-verify',
          '$proxy/deepfake/checks',
          '$proxy/consents/consent-abc/approve/john-doe',
          '$proxy/sessions/s-proxy/end',
        ]);
        expect(
            verify(client.get(captureAny, headers: anyNamed('headers')))
                .captured
                .single
                .toString(),
            '$proxy/consents/my-approvals/john-doe');
      });

      test('defaultProxyPaths covers every operation', () {
        expect(Biometry.defaultProxyPaths.keys.toSet(),
            ProxyOperation.values.toSet());
      });

      test('paths overrides some routes and fills placeholders encoded',
          () async {
        final b = await Biometry.initialize(
          baseUrl: proxy,
          userId: 'john doe@x',
          paths: const {
            ProxyOperation.startSession: '/start',
            ProxyOperation.endSession: '/s/{session_id}/finish',
            ProxyOperation.approveConsent: '/users/{user_id}/ok/{consent_id}',
            ProxyOperation.getConsentApprovals: '/users/{user_id}/consents',
          },
          client: client,
        );
        await b.livenessCheck(video: mockFile);
        await b.approveConsent(consentId: 'consent a/b');
        await b.endSession();
        await b.getConsentApprovals();

        expect(requests.map((r) => r.url.toString()), [
          '$proxy/start?warmup=true',
          '$proxy/liveness',
          '$proxy/users/john%20doe%40x/ok/consent%20a%2Fb',
          '$proxy/s/s-proxy/finish',
        ]);
        expect(
            verify(client.get(captureAny, headers: anyNamed('headers')))
                .captured
                .single
                .toString(),
            '$proxy/users/john%20doe%40x/consents');
      });

      test('rejects invalid paths before any request', () async {
        const bad = <ProxyOperation, String>{
          ProxyOperation.liveness: 'liveness',
          ProxyOperation.faceVerify: '/face-verify?x=1',
          ProxyOperation.voiceVerify: '/voice-verify#a',
          ProxyOperation.deepfakeCheck: '/deepfake/{session_id}',
          ProxyOperation.startSession: '/sessions/{',
        };
        const badEndSession = [
          '/sessions/end',
          '/sessions/{sessionId}/end',
          '/sessions/{session_id}/{session_id}',
          '/sessions/{session_id}}/end',
        ];
        final cases = [
          ...bad.entries,
          ...badEndSession.map((p) => MapEntry(ProxyOperation.endSession, p)),
          const MapEntry(ProxyOperation.approveConsent,
              '/consents/{consent_id}/approve'),
        ];
        for (final c in cases) {
          await expectLater(
            Biometry.initialize(
              baseUrl: proxy,
              userId: 'john-doe',
              paths: {c.key: c.value},
              client: client,
            ),
            throwsA(isA<ArgumentError>()
                .having((e) => e.name, 'name',
                    'paths[ProxyOperation.${c.key.name}]')
                .having((e) => e.invalidValue, 'invalidValue', c.value)),
            reason: '${c.key.name}: ${c.value}',
          );
        }
        verifyNever(client.send(any));
      });

      test('rejects a baseUrl that is not an absolute http(s) URL', () async {
        for (final bad in [
          '',
          'app.example.com',
          'ftp://app.example.com',
          'https://app.example.com?x=1',
        ]) {
          await expectLater(
            Biometry.initialize(baseUrl: bad, userId: 'u', client: client),
            throwsA(isA<ArgumentError>()),
            reason: bad,
          );
        }
        verifyNever(client.send(any));
      });

      group('http baseUrl', () {
        tearDown(() => Biometry.debugReleaseModeOverride = null);

        test('release builds refuse http except for this device', () async {
          Biometry.debugReleaseModeOverride = true;
          for (final bad in [
            'http://app.example.com',
            'http://10.0.2.2:8787',
            'http://192.168.1.10:8787',
            'http://app.localhost:8787',
          ]) {
            await expectLater(
              Biometry.initialize(baseUrl: bad, userId: 'u', client: client),
              throwsA(isA<ArgumentError>().having(
                  (e) => e.message, 'message', contains('https'))),
              reason: bad,
            );
          }
          verifyNever(client.send(any));
          for (final ok in [
            'http://localhost:8787',
            'http://127.0.0.1:8787',
            'http://[::1]:8787',
          ]) {
            when(client.send(any)).thenAnswer((_) async => http.StreamedResponse(
                bodyStream('{"data":{"session_id":"s-local"}}'), 200));
            final biometry = await Biometry.initialize(
                baseUrl: ok, userId: 'u', client: client);
            expect(biometry.sessionId, 's-local', reason: ok);
          }
        });

        test('debug builds accept any http address', () async {
          Biometry.debugReleaseModeOverride = false;
          when(client.send(any)).thenAnswer((_) async => http.StreamedResponse(
              bodyStream('{"data":{"session_id":"s-emulator"}}'), 200));
          final biometry = await Biometry.initialize(
              baseUrl: 'http://10.0.2.2:8787', userId: 'u', client: client);
          expect(biometry.sessionId, 's-emulator');
        });
      });
    });

    group('phrase utilities', () {
      test('phraseWords spells out each digit of the phrase', () {
        // ignore: deprecated_member_use_from_same_package
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

      test('resetPhrase generates 7 unique digits from 1-9', () {
        // ignore: deprecated_member_use_from_same_package
        Biometry.resetPhrase();
        final digits = biometry.phraseAsIntList.split(', ');

        expect(digits, hasLength(7));
        expect(digits.toSet(), hasLength(7),
            reason: 'Phrase digits should all be unique');
        expect(digits, isNot(contains('0')));
      });
    });

    group('setChallenge', () {
      // _phrase is static, so leave a device-generated phrase behind for
      // whichever test runs next.
      tearDown(() {
        // ignore: deprecated_member_use_from_same_package
        Biometry.resetPhrase();
      });

      test('uses the given challenge exactly, including a leading zero', () {
        Biometry.setChallenge('0712845');

        expect(biometry.phrase, '0712845');
        expect(biometry.phraseAsIntList, '0, 7, 1, 2, 8, 4, 5');
        expect(biometry.phraseWords, 'Zero Seven One Two Eight Four Five');
      });

      test('accepts more than 7 digits and repeated digits', () {
        Biometry.setChallenge('1123581321');
        expect(biometry.phrase, '1123581321');
      });

      test('accepts up to 12 digits', () {
        Biometry.setChallenge('123456789123');
        expect(biometry.phrase, '123456789123');
      });

      test('a challenge set before initialize() survives it', () async {
        Biometry.setChallenge('48719352');

        final fresh = await Biometry.initialize(
          token: 'test-token',
          client: mockHttpClient,
          userId: 'john-doe',
        );

        expect(fresh.phrase, '48719352');
        expect(biometry.phrase, '48719352');
      });

      test('resetPhrase forgets the challenge, so initialize() generates again',
          () async {
        Biometry.setChallenge('48719352');
        // ignore: deprecated_member_use_from_same_package
        Biometry.resetPhrase();

        final fresh = await Biometry.initialize(
          token: 'test-token',
          client: mockHttpClient,
          userId: 'john-doe',
        );

        expect(fresh.phrase, isNot('48719352'));
        expect(fresh.phrase, matches(RegExp(r'^[1-9]{7}$')));
      });

      test('clearChallenge forgets the challenge, so initialize() generates again',
          () async {
        Biometry.setChallenge('48719352');
        Biometry.clearChallenge();
        expect(biometry.phrase, isEmpty);

        final fresh = await Biometry.initialize(
          token: 'test-token',
          client: mockHttpClient,
          userId: 'john-doe',
        );

        expect(fresh.phrase, matches(RegExp(r'^[1-9]{7}$')));
      });

      test('the challenge stays set across liveness then voice verify', () async {
        when(mockHttpClient.send(any)).thenAnswer(
            (_) async => http.StreamedResponse(bodyStream('{"data":{}}'), 200));

        Biometry.setChallenge('48719352');
        await biometry.livenessCheck(video: mockFile);
        await biometry.voiceVerify(video: mockFile);

        expect(biometry.phrase, '48719352');
      });

      test('challengeWords spells out a challenge without an instance', () {
        expect(Biometry.challengeWords('48719352'),
            'Four Eight Seven One Nine Three Five Two');
        expect(Biometry.challengeWords('0712845'),
            'Zero Seven One Two Eight Four Five');
        expect(() => Biometry.challengeWords('123'), throwsArgumentError);
        expect(() => Biometry.challengeWords('1234 5678'), throwsArgumentError);
      });

      test('sends the challenge as the phrase on liveness, face and voice verify',
          () async {
        final sentPhrases = <String, String>{};
        when(mockHttpClient.send(any)).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments[0] as http.MultipartRequest;
          final requestJson =
              jsonDecode(request.fields['request']!) as Map<String, dynamic>;
          sentPhrases[request.url.path.split('/').last] =
              requestJson['phrase'] as String;
          return http.StreamedResponse(bodyStream('{"data":{}}'), 200);
        });

        Biometry.setChallenge('9305718');
        await biometry.livenessCheck(video: mockFile);
        await biometry.faceVerify(video: mockFile);
        await biometry.voiceVerify(video: mockFile);

        const expected = 'Nine Three Zero Five Seven One Eight';
        expect(sentPhrases, {
          'liveness': expected,
          'face-verify': expected,
          'voice-verify': expected,
        });
      });

      group('after clearChallenge', () {
        setUp(Biometry.clearChallenge);

        test('phraseWords throws instead of returning an empty phrase', () {
          expect(() => biometry.phraseWords, throwsStateError);
        });

        test('livenessCheck throws without sending a request', () async {
          clearInteractions(mockHttpClient);
          await expectLater(
              biometry.livenessCheck(video: mockFile), throwsStateError);
          verifyNever(mockHttpClient.send(any));
        });

        test('enrolVoice throws without sending a request', () async {
          clearInteractions(mockHttpClient);
          await expectLater(
              biometry.enrolVoice(videoFile: mockFile), throwsStateError);
          verifyNever(mockHttpClient.send(any));
        });

        test('voiceVerify throws without sending a request', () async {
          clearInteractions(mockHttpClient);
          await expectLater(
              biometry.voiceVerify(video: mockFile), throwsStateError);
          verifyNever(mockHttpClient.send(any));
        });

        test('faceVerify needs no challenge and sends an empty phrase',
            () async {
          String? sentPhrase;
          when(mockHttpClient.send(any)).thenAnswer((invocation) async {
            final request =
                invocation.positionalArguments[0] as http.MultipartRequest;
            final requestJson =
                jsonDecode(request.fields['request']!) as Map<String, dynamic>;
            sentPhrase = requestJson['phrase'] as String;
            return http.StreamedResponse(bodyStream('{"data":{}}'), 200);
          });

          final response = await biometry.faceVerify(video: mockFile);

          expect(response.statusCode, 200);
          expect(sentPhrase, '');
        });
      });

      for (final invalid in <String>[
        '',
        '123456', // too short
        '1234567891234', // 13 digits: too long
        '12345a7',
        '1234 567',
        '1,2,3,4,5,6,7',
        ' 1234567',
        'One Two Three Four Five Six Seven',
        '１２３４５６７', // full-width digits are not ASCII 0-9
      ]) {
        test('rejects "$invalid" without changing the current phrase', () {
          Biometry.setChallenge('2468013');

          expect(() => Biometry.setChallenge(invalid), throwsArgumentError);
          expect(biometry.phrase, '2468013');
        });
      }
    });

    group('device-generated challenge warning', () {
      late DebugPrintCallback originalDebugPrint;
      late List<String> printed;

      setUp(() {
        printed = <String>[];
        originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) printed.add(message);
        };
        Biometry.debugResetDeviceChallengeWarning();
      });

      tearDown(() {
        debugPrint = originalDebugPrint;
        // ignore: deprecated_member_use_from_same_package
        Biometry.resetPhrase();
      });

      List<String> warnings() => printed
          .where((m) => m.contains('no replay protection'))
          .toList();

      Future<Biometry> init() => Biometry.initialize(
            token: 'test-token',
            client: mockHttpClient,
            userId: 'john-doe',
          );

      test('warns once per process when initialize() generates the phrase',
          () async {
        Biometry.clearChallenge();
        await init();
        Biometry.clearChallenge();
        await init();

        expect(warnings(), hasLength(1));
        expect(warnings().single,
            contains('/concepts/liveness-challenge/'));
        expect(warnings().single, contains('Biometry.setChallenge()'));
      });

      test('does not warn when a challenge was set', () async {
        Biometry.setChallenge('48719352');
        await init();

        expect(warnings(), isEmpty);
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
