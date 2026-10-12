/// 트레이너 대화의 전송 실패를 원인별로 다룬다. (#3346)
///
/// 전에는 글·이모티콘·사진·주간 피드백이 모두 예외를 한 갈래로 받아, 담당이
/// 해제돼 다시 보내도 절대 성공하지 않는 때에도 "다시 시도해 주세요" 만 나왔다.
/// 서버는 원인을 상태 코드로 나눠 준다 — 그 값을 저장소 한 곳에서 옮기고 화면은
/// 그 값으로 문구와 다시 보내기 여부를 고른다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/coach_send_failure_labels.dart';
import 'package:oncare/features/member_coach/presentation/controllers/coach_photo_send_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_image_attachment.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_member_coach_repository.dart';

class _MockDio extends Mock implements Dio {}

/// 1×1 투명 PNG.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

const String _chatPath = '/me/coach/chat';

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: <String, Object?>{'detail': '서버가 준 사유'},
  ),
);

DioException _offline(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

Matcher _rejected(CoachSendFailure reason) => throwsA(
  isA<CoachSendRejected>().having(
    (CoachSendRejected e) => e.reason,
    'reason',
    reason,
  ),
);

Map<String, Object?> _myMessage(String id, String text) => <String, Object?>{
  'id': id,
  'sender': 'me',
  'body': text,
  'time_label': '10:00',
  'created_at': '2026-09-14T01:00:00Z',
};

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

Widget _app(Widget home, {Locale locale = const Locale('ko')}) => MaterialApp(
  theme: AppTheme.light(),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// 알림이 사라질 때까지 흘려보낸다 — 남은 타이머가 있으면 테스트가 실패한다.
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

/// 글 전송을 정해 둔 오류로 실패시키는 데모 저장소.
class _SendFailingRepository extends MockMemberCoachRepository {
  _SendFailingRepository(this.error);

  final Object error;

  @override
  Future<void> sendMessage(String text, {String? emoteId}) async => throw error;
}

/// 실패한 사진 한 장을 들고 시작하는 전송 상태.
class _SeededPhotoController extends CoachPhotoSendController {
  _SeededPhotoController(this.failure);

  final CoachSendFailure? failure;

  @override
  List<PendingCoachPhoto> build() => <PendingCoachPhoto>[
    PendingCoachPhoto(
      requestId: 'photo-1',
      photo: MealPhoto.fromBytes(_png)!,
      status: CoachPhotoSendStatus.failed,
      failure: failure,
    ),
  ];
}

/// 사진 전송을 정해 둔 오류로 실패시키고 부른 횟수를 센다.
class _PhotoFailingRepository extends MockMemberCoachRepository {
  _PhotoFailingRepository(this.error);

  final Object error;
  int photoCalls = 0;
  int chatLoads = 0;

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) {
    chatLoads += 1;
    return super.fetchChat(before: before);
  }

  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) async {
    photoCalls += 1;
    throw error;
  }
}

/// 주간 피드백 저장을 정해 둔 오류로 실패시킨다.
class _FeedbackFailingRepository extends FakeMemberCoachRepository {
  _FeedbackFailingRepository(this.error);

  final Object error;
  int coachLoads = 0;

  @override
  Future<MemberCoach?> fetchCoach() async {
    coachLoads += 1;
    return null;
  }

  @override
  Future<MemberWeeklyFeedback> saveWeeklyFeedback({
    required DateTime weekStart,
    required WeekCondition condition,
    required WeekIntensity intensity,
    String painArea = '',
    DateTime? painOn,
    String note = '',
  }) async => throw error;
}

void main() {
  setUpAll(() {
    registerFallbackValue(FormData());
    registerFallbackValue(Options());
  });

  group('거절 이유 매핑', () {
    test('전송 경로의 상태 코드마다 이유가 하나다', () {
      expect(
        CoachSendRejected.fromStatus(404)?.reason,
        CoachSendFailure.unassigned,
      );
      expect(
        CoachSendRejected.fromStatus(402)?.reason,
        CoachSendFailure.emoteLocked,
      );
      expect(
        CoachSendRejected.fromStatus(409)?.reason,
        CoachSendFailure.conflict,
      );
      expect(
        CoachSendRejected.fromStatus(413)?.reason,
        CoachSendFailure.photoTooLarge,
      );
      expect(
        CoachSendRejected.fromStatus(415)?.reason,
        CoachSendFailure.photoUnsupported,
      );
      expect(
        CoachSendRejected.fromStatus(400)?.reason,
        CoachSendFailure.invalid,
      );
      expect(
        CoachSendRejected.fromStatus(422)?.reason,
        CoachSendFailure.invalid,
      );
    });

    test('다시 보내면 되는 실패는 거절이 아니다', () {
      for (final int? status in <int?>[null, 401, 403, 429, 500, 502, 503]) {
        expect(CoachSendRejected.fromStatus(status), isNull, reason: '$status');
      }
    });

    test('거절이 아닌 오류에서는 이유를 읽지 않는다', () {
      expect(CoachSendRejected.reasonOf(const NetworkError()), isNull);
      expect(CoachSendRejected.reasonOf(StateError('x')), isNull);
      expect(
        CoachSendRejected.reasonOf(
          const CoachSendRejected(CoachSendFailure.unassigned),
        ),
        CoachSendFailure.unassigned,
      );
    });
  });

  group('Dio 저장소', () {
    late _MockDio dio;
    late DateTime clock;
    late DioMemberCoachRepository repo;

    void stubSend(Future<Response<Map<String, Object?>>> Function() answer) {
      when(
        () =>
            dio.post<Map<String, Object?>>(_chatPath, data: any(named: 'data')),
      ).thenAnswer((_) => answer());
    }

    void stubThread(List<Map<String, Object?>> rows) {
      when(
        () => dio.get<List<dynamic>>(
          _chatPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _ok<List<dynamic>>(rows, _chatPath));
    }

    List<String?> sentKeys() =>
        verify(
              () => dio.post<Map<String, Object?>>(
                _chatPath,
                data: captureAny(named: 'data'),
              ),
            ).captured
            .cast<Map<String, Object?>>()
            .map((Map<String, Object?> body) => body['client_request_id'])
            .cast<String?>()
            .toList();

    setUp(() {
      dio = _MockDio();
      clock = DateTime(2026, 9, 14, 10);
      int n = 0;
      repo = DioMemberCoachRepository(
        dio,
        requestIdFactory: () => 'req-${++n}',
        now: () => clock,
      );
    });

    test('담당이 해제된 뒤의 글 전송(404)은 해제 거절이다', () async {
      stubSend(() async => throw _httpError(404, _chatPath));

      await expectLater(
        repo.sendMessage('안녕하세요'),
        _rejected(CoachSendFailure.unassigned),
      );
    });

    test('이용권이 끝난 이모티콘(402)은 잠김 거절이다', () async {
      stubSend(() async => throw _httpError(402, _chatPath));

      await expectLater(
        repo.sendMessage('', emoteId: 'thumbs_up'),
        _rejected(CoachSendFailure.emoteLocked),
      );
    });

    test('없는 이모티콘·빈 글(400)과 너무 긴 글(422)은 값 거절이다', () async {
      stubSend(() async => throw _httpError(400, _chatPath));
      await expectLater(
        repo.sendMessage('', emoteId: 'nope'),
        _rejected(CoachSendFailure.invalid),
      );

      stubSend(() async => throw _httpError(422, _chatPath));
      await expectLater(
        repo.sendMessage('긴 글'),
        _rejected(CoachSendFailure.invalid),
      );
    });

    test('망 오류는 거절이 아니라 다시 보낼 수 있는 실패다', () async {
      stubSend(() async => throw _offline(_chatPath));

      await expectLater(
        repo.sendMessage('안녕하세요'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('서버 장애(503)도 거절이 아니다', () async {
      stubSend(() async => throw _httpError(503, _chatPath));

      await expectLater(repo.sendMessage('안녕하세요'), throwsA(isA<ServerError>()));
    });

    test('사진 전송도 같은 매핑을 쓴다', () async {
      Future<void> expectPhoto(int status, CoachSendFailure reason) async {
        when(
          () => dio.post<Map<String, Object?>>(
            '/me/coach/chat/image',
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(_httpError(status, '/me/coach/chat/image'));
        await expectLater(
          repo.sendPhoto(
            _png,
            fileName: 'photo.png',
            mimeType: 'image/png',
            clientRequestId: 'photo-1',
          ),
          _rejected(reason),
          reason: '$status',
        );
      }

      await expectPhoto(404, CoachSendFailure.unassigned);
      await expectPhoto(409, CoachSendFailure.conflict);
      await expectPhoto(413, CoachSendFailure.photoTooLarge);
      await expectPhoto(415, CoachSendFailure.photoUnsupported);
    });

    test('주간 피드백 전송도 같은 매핑을 쓴다', () async {
      Future<void> expectSave(int status, CoachSendFailure reason) async {
        when(
          () => dio.put<Map<String, Object?>>(
            '/me/coach/weekly-feedback',
            data: any(named: 'data'),
          ),
        ).thenThrow(_httpError(status, '/me/coach/weekly-feedback'));
        await expectLater(
          repo.saveWeeklyFeedback(
            weekStart: DateTime(2026, 9, 7),
            condition: WeekCondition.ok,
            intensity: WeekIntensity.right,
          ),
          _rejected(reason),
          reason: '$status',
        );
      }

      await expectSave(404, CoachSendFailure.unassigned);
      // 아직 오지 않은 주.
      await expectSave(422, CoachSendFailure.invalid);
    });

    group('전송 키 수명', () {
      test('응답을 못 받은 글은 곧바로 다시 보낼 때 같은 키를 쓴다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          if (calls == 1) throw _offline(_chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });

        await expectLater(repo.sendMessage('네'), throwsA(isA<AppError>()));
        clock = clock.add(const Duration(minutes: 1));
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-1']);
      });

      test('한참 뒤 같은 문장은 새 메시지다 — 옛 키를 다시 쓰지 않는다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          if (calls == 1) throw _offline(_chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });

        await expectLater(repo.sendMessage('네'), throwsA(isA<AppError>()));
        clock = clock.add(DioMemberCoachRepository.pendingRequestTtl);
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-2']);
      });

      test('대화에서 저장이 확인된 글의 키는 버린다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          // 서버는 받았는데 응답만 끊겼다.
          if (calls == 1) throw _offline(_chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });
        stubThread(<Map<String, Object?>>[_myMessage('m-1', '네')]);

        await expectLater(repo.sendMessage('네'), throwsA(isA<AppError>()));
        await repo.fetchChat();
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-2']);
      });

      test('키를 만들기 전부터 있던 같은 글은 저장 확인이 아니다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          if (calls == 1) throw _offline(_chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });
        // 어제도 `네` 라고 보냈다.
        stubThread(<Map<String, Object?>>[_myMessage('m-old', '네')]);

        await repo.fetchChat();
        await expectLater(repo.sendMessage('네'), throwsA(isA<AppError>()));
        await repo.fetchChat();
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-1']);
      });

      test('트레이너가 보낸 같은 글은 저장 확인이 아니다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          if (calls == 1) throw _offline(_chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });
        stubThread(<Map<String, Object?>>[
          <String, Object?>{..._myMessage('t-1', '네'), 'sender': 'trainer'},
        ]);

        await expectLater(repo.sendMessage('네'), throwsA(isA<AppError>()));
        await repo.fetchChat();
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-1']);
      });

      test('옛 쪽을 더 받는 것으로는 키를 버리지 않는다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          if (calls == 1) throw _offline(_chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });
        stubThread(<Map<String, Object?>>[_myMessage('m-older', '네')]);

        await expectLater(repo.sendMessage('네'), throwsA(isA<AppError>()));
        await repo.fetchChat(
          before: CoachMessage(
            id: 'cursor',
            sender: CoachSender.me,
            body: '커서',
            timeLabel: '10:00',
            createdAt: DateTime(2026, 9, 14, 10),
          ),
        );
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-1']);
      });

      test('거절된 키는 버린다 — 다음 전송은 새 키로 간다', () async {
        int calls = 0;
        stubSend(() async {
          calls += 1;
          if (calls == 1) throw _httpError(409, _chatPath);
          return _ok<Map<String, Object?>>(<String, Object?>{
            'id': 'x',
          }, _chatPath);
        });

        await expectLater(
          repo.sendMessage('네'),
          _rejected(CoachSendFailure.conflict),
        );
        await repo.sendMessage('네');

        expect(sentKeys(), <String>['req-1', 'req-2']);
      });
    });
  });

  group('데모 저장소', () {
    test('담당이 끊기면 글·사진·주간 피드백이 해제 거절이다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        linked: () => false,
      );

      await expectLater(
        repo.sendMessage('해제 뒤 인사'),
        _rejected(CoachSendFailure.unassigned),
      );
      await expectLater(
        repo.sendPhoto(
          _png,
          fileName: 'photo.png',
          mimeType: 'image/png',
          clientRequestId: 'photo-1',
        ),
        _rejected(CoachSendFailure.unassigned),
      );
      await expectLater(
        repo.saveWeeklyFeedback(
          weekStart: DateTime(2026, 9, 7),
          condition: WeekCondition.ok,
          intensity: WeekIntensity.right,
        ),
        _rejected(CoachSendFailure.unassigned),
      );
    });

    test('이용권이 없는 이모티콘은 잠김 거절이고 대화에 붙지 않는다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        emoteUnlocked: (String _) => false,
      );
      final int before = (await repo.fetchChat()).length;

      await expectLater(
        repo.sendMessage('', emoteId: AppEmotes.all.first),
        _rejected(CoachSendFailure.emoteLocked),
      );
      expect((await repo.fetchChat()).length, before);
    });

    test('이용권이 있는 이모티콘은 그대로 간다', () async {
      final String emote = AppEmotes.all.first;
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        emoteUnlocked: (String id) => id == emote,
      );

      await repo.sendMessage('', emoteId: emote);

      expect((await repo.fetchChat()).last.emoteId, emote);
    });

    test('모르는 이모티콘은 이용권을 묻기 전에 값 거절이다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        emoteUnlocked: (String _) => true,
      );

      await expectLater(
        repo.sendMessage('', emoteId: 'no-such-emote'),
        _rejected(CoachSendFailure.invalid),
      );
    });

    test('같은 키에 다른 글을 실은 사진은 충돌 거절이다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();
      await repo.sendPhoto(
        _png,
        fileName: 'photo.png',
        mimeType: 'image/png',
        clientRequestId: 'photo-1',
        text: '오늘 점심',
      );

      await expectLater(
        repo.sendPhoto(
          _png,
          fileName: 'photo.png',
          mimeType: 'image/png',
          clientRequestId: 'photo-1',
          text: '오늘 저녁',
        ),
        _rejected(CoachSendFailure.conflict),
      );
    });

    test('서버 한도보다 큰 사진은 용량 거절이다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();

      await expectLater(
        repo.sendPhoto(
          Uint8List(CoachPhotoSendController.maxBytes + 1),
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          clientRequestId: 'big-1',
        ),
        _rejected(CoachSendFailure.photoTooLarge),
      );
    });
  });

  group('문구', () {
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    test('닿지 못한 실패는 지금처럼 다시 시도를 권한다', () {
      expect(
        coachSendFailureText(ko, CoachSendKind.message, null),
        ko.coachChatSendFailed,
      );
      expect(
        coachSendFailureText(ko, CoachSendKind.emote, null),
        ko.emoteSendFailed,
      );
      expect(
        coachSendFailureText(ko, CoachSendKind.photo, null),
        ko.coachPhotoSendFailed,
      );
      expect(
        coachSendFailureText(ko, CoachSendKind.weeklyFeedback, null),
        ko.weeklyFeedbackSendFailed,
      );
    });

    test('담당 해제는 무엇을 보냈든 해제를 말하고 재시도를 권하지 않는다', () {
      for (final AppLocalizations l in <AppLocalizations>[ko, en]) {
        for (final CoachSendKind kind in CoachSendKind.values) {
          final String text = coachSendFailureText(
            l,
            kind,
            CoachSendFailure.unassigned,
          );
          expect(
            text,
            kind == CoachSendKind.weeklyFeedback
                ? l.weeklyFeedbackSendUnassigned
                : l.coachChatUnassigned,
          );
          expect(text, isNot(contains('다시 시도')));
          expect(text.toLowerCase(), isNot(contains('try again')));
        }
      }
    });

    test('이용권이 끝난 이모티콘은 만료를 말한다', () {
      expect(
        coachSendFailureText(
          ko,
          CoachSendKind.emote,
          CoachSendFailure.emoteLocked,
        ),
        ko.emoteSendLocked,
      );
      expect(ko.emoteSendLocked, isNot(ko.emoteSendFailed));
      expect(en.emoteSendLocked, isNot(en.emoteSendFailed));
    });

    test('값이 거절된 실패는 다시 시도가 아니라 내용을 가리킨다', () {
      expect(
        coachSendFailureText(
          ko,
          CoachSendKind.message,
          CoachSendFailure.invalid,
        ),
        ko.coachChatSendRejected,
      );
      expect(
        coachSendFailureText(ko, CoachSendKind.emote, CoachSendFailure.invalid),
        ko.emoteSendRejected,
      );
      expect(
        coachSendFailureText(
          ko,
          CoachSendKind.photo,
          CoachSendFailure.photoUnsupported,
        ),
        ko.coachPhotoSendRejected,
      );
      expect(
        coachSendFailureText(
          ko,
          CoachSendKind.photo,
          CoachSendFailure.photoTooLarge,
        ),
        ko.dietPhotoTooLarge,
      );
      expect(
        coachSendFailureText(
          ko,
          CoachSendKind.weeklyFeedback,
          CoachSendFailure.invalid,
        ),
        ko.weeklyFeedbackSendRejected,
      );
    });

    test('글의 키 충돌은 다시 보내면 된다 — 저장소가 그 키를 버렸다', () {
      expect(
        coachSendFailureText(
          ko,
          CoachSendKind.message,
          CoachSendFailure.conflict,
        ),
        ko.coachChatSendFailed,
      );
    });
  });

  group('사진 전송 상태', () {
    ProviderContainer container(MemberCoachRepository repo) {
      int n = 0;
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repo),
          coachPhotoRequestIdProvider.overrideWithValue(() => 'photo-${++n}'),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('서버가 거절한 사진은 이유와 함께 남고 다시 보내지 않는다', () async {
      final _PhotoFailingRepository repo = _PhotoFailingRepository(
        const CoachSendRejected(CoachSendFailure.photoUnsupported),
      );
      final ProviderContainer c = container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      expect(await ctrl.send(MealPhoto.fromBytes(_png)!), isFalse);

      final PendingCoachPhoto pending = c.read(coachPhotoSendProvider).single;
      expect(pending.status, CoachPhotoSendStatus.failed);
      expect(pending.failure, CoachSendFailure.photoUnsupported);
      expect(pending.canRetry, isFalse);

      expect(await ctrl.retry('photo-1'), isFalse);
      expect(repo.photoCalls, 1);
    });

    test('망 오류로 실패한 사진은 지금처럼 다시 보낼 수 있다', () async {
      final _PhotoFailingRepository repo = _PhotoFailingRepository(
        const NetworkError(),
      );
      final ProviderContainer c = container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      expect(await ctrl.send(MealPhoto.fromBytes(_png)!), isFalse);

      final PendingCoachPhoto pending = c.read(coachPhotoSendProvider).single;
      expect(pending.failure, isNull);
      expect(pending.canRetry, isTrue);

      await ctrl.retry('photo-1');
      expect(repo.photoCalls, 2);
    });

    test('담당 해제로 거절되면 대화를 다시 읽는다', () async {
      final _PhotoFailingRepository repo = _PhotoFailingRepository(
        const CoachSendRejected(CoachSendFailure.unassigned),
      );
      final ProviderContainer c = container(repo);
      final ProviderSubscription<AsyncValue<List<CoachMessage>>> chat = c
          .listen(coachChatProvider, (_, _) {});
      addTearDown(chat.close);
      await c.read(coachChatProvider.future);
      final int loads = repo.chatLoads;

      await c
          .read(coachPhotoSendProvider.notifier)
          .send(MealPhoto.fromBytes(_png)!);
      await c.read(coachChatProvider.future);

      expect(repo.chatLoads, greaterThan(loads));
    });

    test('거절된 사진도 지울 수 있다', () async {
      final ProviderContainer c = container(
        _PhotoFailingRepository(
          const CoachSendRejected(CoachSendFailure.conflict),
        ),
      );
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );
      await ctrl.send(MealPhoto.fromBytes(_png)!);

      ctrl.discard('photo-1');

      expect(c.read(coachPhotoSendProvider), isEmpty);
    });
  });

  group('대화방', () {
    Future<void> pumpChat(
      WidgetTester tester,
      MemberCoachRepository repo, {
      List<Override> overrides = const <Override>[],
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_demo),
            memberCoachRepositoryProvider.overrideWithValue(repo),
            ...overrides,
          ],
          child: _app(const TrainerChatPage(trainerName: '김트레이너')),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.byIcon(AppIcons.send));
      await tester.pumpAndSettle();
    }

    testWidgets('담당이 해제된 뒤 보내면 해제 안내가 뜨고 입력이 닫힌다', (WidgetTester tester) async {
      bool linked = true;
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        linked: () => linked,
      );
      await pumpChat(tester, repo);
      // 대화를 열어 둔 사이 담당이 해제됐다.
      linked = false;

      await send(tester, '오늘 운동 끝냈어요');

      expect(find.text('담당이 해제되어 더 이상 메시지를 보낼 수 없어요'), findsWidgets);
      expect(find.text('메시지를 보내지 못했어요. 다시 시도해 주세요'), findsNothing);
      expect(
        tester.widget<AppChatInputBar>(find.byType(AppChatInputBar)).enabled,
        isFalse,
      );
      // 대화도 다시 읽혀 해제 안내로 바뀐다.
      expect(
        find.byKey(const ValueKey<String>('coach-chat-unassigned')),
        findsOneWidget,
      );
      await _drainToasts(tester);
    });

    testWidgets('망 오류는 지금처럼 다시 시도를 권하고 입력을 열어 둔다', (WidgetTester tester) async {
      await pumpChat(tester, _SendFailingRepository(const NetworkError()));

      await send(tester, '다시 보낼 메시지');

      expect(find.text('메시지를 보내지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(
        tester.widget<AppChatInputBar>(find.byType(AppChatInputBar)).enabled,
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '다시 보낼 메시지',
      );
      await _drainToasts(tester);
    });

    testWidgets('값이 거절된 글은 내용을 확인하라고 알린다', (WidgetTester tester) async {
      await pumpChat(
        tester,
        _SendFailingRepository(
          const CoachSendRejected(CoachSendFailure.invalid),
        ),
      );

      await send(tester, '보낼 수 없는 글');

      expect(find.text('보낼 수 없는 메시지예요. 내용을 확인해 주세요'), findsOneWidget);
      expect(find.text('메시지를 보내지 못했어요. 다시 시도해 주세요'), findsNothing);
      await _drainToasts(tester);
    });

    testWidgets('서버가 거절한 사진에는 다시 보내기가 없고 삭제만 있다', (WidgetTester tester) async {
      await pumpChat(
        tester,
        MockMemberCoachRepository(),
        overrides: <Override>[
          coachPhotoSendProvider.overrideWith(
            () => _SeededPhotoController(CoachSendFailure.photoUnsupported),
          ),
        ],
      );

      expect(find.text('보낼 수 없는 사진이에요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('coach-pending-photo-retry')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('coach-pending-photo-discard')),
        findsOneWidget,
      );
    });

    testWidgets('망 오류로 실패한 사진에는 다시 보내기가 그대로 있다', (WidgetTester tester) async {
      await pumpChat(
        tester,
        MockMemberCoachRepository(),
        overrides: <Override>[
          coachPhotoSendProvider.overrideWith(
            () => _SeededPhotoController(null),
          ),
        ],
      );

      expect(find.text('사진을 보내지 못했어요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('coach-pending-photo-retry')),
        findsOneWidget,
      );
    });
  });

  group('받은 사진 다시 불러오기', () {
    const CoachAttachment image = CoachAttachment(
      kind: CoachAttachmentKind.image,
      fileName: 'pose.png',
      fileId: 'file-1',
      fileSize: 1024,
      downloadPath: '/chat/attachments/file-1',
    );

    testWidgets('불러오지 못한 사진은 눌러서 다시 받는다', (WidgetTester tester) async {
      int loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            coachImageProvider(image.downloadPath).overrideWith((ref) async {
              loads += 1;
              // 첫 번째는 받지 못한다.
              return loads == 1 ? null : _png;
            }),
          ],
          child: _app(
            const Scaffold(body: CoachImageAttachment(attachment: image)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('눌러서 다시 불러오기'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('coach-image-retry')));
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(find.text('사진을 불러오지 못했어요'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('coach-image-file-1')),
        findsOneWidget,
      );
    });

    testWidgets('다시 받아도 실패하면 또 누를 수 있다', (WidgetTester tester) async {
      int loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            coachImageProvider(image.downloadPath).overrideWith((ref) async {
              loads += 1;
              return null;
            }),
          ],
          child: _app(
            const Scaffold(body: CoachImageAttachment(attachment: image)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('coach-image-retry')));
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(
        find.byKey(const ValueKey<String>('coach-image-retry')),
        findsOneWidget,
      );
    });

    testWidgets('영어 화면에서도 다시 받기를 안내한다', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            coachImageProvider(
              image.downloadPath,
            ).overrideWith((ref) async => null),
          ],
          child: _app(
            const Scaffold(body: CoachImageAttachment(attachment: image)),
            locale: const Locale('en'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tap to load again'), findsOneWidget);
    });
  });

  group('주간 피드백 시트', () {
    final DateTime week = DateTime(2026, 9, 14);

    Future<_FeedbackFailingRepository> pumpSheet(
      WidgetTester tester,
      Object error,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final _FeedbackFailingRepository repo = _FeedbackFailingRepository(error);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            memberCoachRepositoryProvider.overrideWithValue(repo),
          ],
          child: _app(
            Scaffold(
              body: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () =>
                      openWeeklyFeedbackSheet(context, weekStart: week),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'weekly-feedback-condition-${WeekCondition.tired.wire}',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'weekly-feedback-intensity-${WeekIntensity.tooHard.wire}',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('weekly-feedback-send')),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('담당이 해제됐으면 해제를 알리고 시트를 닫는다', (WidgetTester tester) async {
      final _FeedbackFailingRepository repo = await pumpSheet(
        tester,
        const CoachSendRejected(CoachSendFailure.unassigned),
      );

      expect(find.text('담당이 해제되어 주간 피드백을 보낼 수 없어요'), findsOneWidget);
      expect(find.text('주간 피드백을 보내지 못했어요. 다시 시도해 주세요'), findsNothing);
      expect(find.byType(WeeklyFeedbackSheet), findsNothing);
      // 아래 화면은 그대로다.
      expect(find.text('열기'), findsOneWidget);
      // 담당 코치도 다시 읽는다.
      expect(repo.coachLoads, greaterThanOrEqualTo(1));
      await _drainToasts(tester);
    });

    testWidgets('받지 않는 주는 다시 시도를 권하지 않고 시트를 남긴다', (WidgetTester tester) async {
      await pumpSheet(
        tester,
        const CoachSendRejected(CoachSendFailure.invalid),
      );

      expect(find.text('이 주에는 주간 피드백을 보낼 수 없어요'), findsOneWidget);
      expect(find.byType(WeeklyFeedbackSheet), findsOneWidget);
      await _drainToasts(tester);
    });

    testWidgets('망 오류는 지금처럼 다시 시도를 권하고 시트를 남긴다', (WidgetTester tester) async {
      await pumpSheet(tester, const NetworkError());

      expect(find.text('주간 피드백을 보내지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(find.byType(WeeklyFeedbackSheet), findsOneWidget);
      await _drainToasts(tester);
    });
  });
}
