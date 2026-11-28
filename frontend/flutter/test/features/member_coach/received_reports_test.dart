/// 받은 리포트 목록 — 대화를 읽지 않고 서버의 목록 하나로 선다. (#3348)
///
/// 예전에는 대화를 끝까지 읽어 그 안의 리포트 안내를 골랐다. 대화가 길수록
/// 요청이 늘었고, 담당이 해제되면 대화를 읽을 수 없어 받은 리포트가 통째로
/// 사라졌다. 여기서는 저장소(실서버·데모)·목록 규칙·컨트롤러를 층별로 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/received_report_list.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/me/coach/reports';

/// 고정한 오늘(2026-08-20 목)에서 본 지난 주들의 월요일.
final DateTime _week1 = DateTime(2026, 8, 10);
final DateTime _week2 = DateTime(2026, 8, 3);
final DateTime _week3 = DateTime(2026, 7, 27);
final DateTime _week4 = DateTime(2026, 7, 20);

Map<String, Object?> _row({
  String id = 'm1',
  String weekStart = '2026-08-10',
  String sentAt = '2026-08-16T12:05:00Z',
  Object? trainerName = '김트레이너',
  String body = '이번 주 리포트예요.',
  Object? attachment,
}) => <String, Object?>{
  'id': id,
  'week_start': weekStart,
  'sent_at': sentAt,
  'trainer_name': trainerName,
  'body': body,
  'attachment': attachment,
};

const Map<String, Object?> _pdf = <String, Object?>{
  'type': 'pdf',
  'file_name': 'report.pdf',
  'file_id': 'file-1',
  'file_size': 1200,
  'download_path': '/chat/attachments/file-1',
};

Response<Map<String, Object?>> _ok(Map<String, Object?> body) =>
    Response<Map<String, Object?>>(
      requestOptions: RequestOptions(path: _path),
      statusCode: 200,
      data: body,
    );

/// 목록을 읽지 못하다가 풀리는 대역 — 첫 쪽은 주고 그 앞 쪽에서 막힌다.
class _OlderPageFailsRepository extends FakeMemberCoachRepository {
  _OlderPageFailsRepository({super.chat});

  bool failing = true;

  @override
  Future<ReceivedReportsPage> fetchReceivedReports({DateTime? before}) {
    if (before != null && failing) {
      return Future<ReceivedReportsPage>.error(StateError('offline'));
    }
    return super.fetchReceivedReports(before: before);
  }
}

/// 대화를 부르면 터지는 대역 — 목록이 대화를 읽지 않는지 본다.
class _ChatForbiddenRepository extends FakeMemberCoachRepository {
  _ChatForbiddenRepository({super.chat, super.coach});

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) =>
      throw const CoachUnassignedException();
}

ProviderContainer _container(MemberCoachRepository repository) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  // autoDispose 라 듣는 이를 먼저 둔다 — 없으면 읽는 사이에 사라진다.
  container.listen(receivedReportsProvider, (_, _) {});
  return container;
}

void main() {
  setUp(() => useFixedKstDate());

  group('응답 읽기', () {
    test('한 줄을 주·보낸 시각·트레이너·글·첨부로 읽는다', () {
      final ReceivedReportsPage page = receivedReportsPageFromJson(
        <String, Object?>{
          'reports': <Object?>[_row(attachment: _pdf)],
          'next_before': null,
        },
      );

      final ReceivedReport report = page.reports.single;
      expect(report.id, 'm1');
      expect(report.weekStart, DateTime(2026, 8, 10));
      expect(report.sentAt, DateTime.utc(2026, 8, 16, 12, 5));
      expect(report.trainerName, '김트레이너');
      expect(report.body, '이번 주 리포트예요.');
      expect(report.attachment?.downloadPath, '/chat/attachments/file-1');
      expect(page.nextBefore, isNull);
    });

    test('탈퇴한 트레이너의 리포트는 이름 없이 읽는다', () {
      final ReceivedReportsPage page = receivedReportsPageFromJson(
        <String, Object?>{
          'reports': <Object?>[_row(trainerName: null)],
        },
      );

      expect(page.reports.single.trainerName, isNull);
      expect(page.reports.single.attachment, isNull);
    });

    test('빈 이름은 이름이 없는 것으로 본다', () {
      final ReceivedReportsPage page = receivedReportsPageFromJson(
        <String, Object?>{
          'reports': <Object?>[_row(trainerName: '')],
        },
      );

      expect(page.reports.single.trainerName, isNull);
    });

    test('다음 커서를 날짜로 읽는다', () {
      final ReceivedReportsPage page = receivedReportsPageFromJson(
        <String, Object?>{
          'reports': <Object?>[_row()],
          'next_before': '2026-08-10',
        },
      );

      expect(page.nextBefore, DateTime(2026, 8, 10));
    });

    test('목록이 없는 응답은 받아들이지 않는다', () {
      expect(
        () => receivedReportsPageFromJson(const <String, Object?>{}),
        throwsFormatException,
      );
    });

    test('주를 모르는 줄은 지어내지 않는다', () {
      expect(
        () => receivedReportsPageFromJson(<String, Object?>{
          'reports': <Object?>[_row(weekStart: 'someday')],
        }),
        throwsFormatException,
      );
    });

    test('보낸 시각을 모르는 줄은 지어내지 않는다', () {
      expect(
        () => receivedReportsPageFromJson(<String, Object?>{
          'reports': <Object?>[_row(sentAt: 'later')],
        }),
        throwsFormatException,
      );
    });

    test('모양이 어긋난 줄은 받아들이지 않는다', () {
      expect(
        () => receivedReportsPageFromJson(const <String, Object?>{
          'reports': <Object?>['not a row'],
        }),
        throwsFormatException,
      );
    });

    test('목록의 한 줄은 대화의 리포트 안내와 같은 모양으로 열린다', () {
      final ReceivedReport report = receivedReportsPageFromJson(
        <String, Object?>{
          'reports': <Object?>[_row(attachment: _pdf)],
        },
      ).reports.single;

      final CoachMessage notice = report.notice;
      expect(notice.id, 'm1');
      expect(notice.sender, CoachSender.trainer);
      expect(notice.body, '이번 주 리포트예요.');
      expect(notice.reportWeekStart, DateTime(2026, 8, 10));
      expect(notice.attachment?.fileName, 'report.pdf');
    });
  });

  group('실서버 저장소', () {
    late _MockDio dio;
    late DioMemberCoachRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioMemberCoachRepository(dio);
    });

    test('받은 리포트 목록 하나를 부른다 — 대화는 부르지 않는다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, Object?>{
          'reports': <Object?>[_row(), _row(id: 'm2', weekStart: '2026-08-03')],
          'next_before': null,
        }),
      );

      final ReceivedReportsPage page = await repo.fetchReceivedReports();

      expect(page.reports.map((ReceivedReport r) => r.id).toList(), <String>[
        'm1',
        'm2',
      ]);
      verify(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
      verifyNever(
        () => dio.get<List<dynamic>>(
          '/me/coach/chat',
          queryParameters: any(named: 'queryParameters'),
        ),
      );
    });

    test('커서는 주 월요일을 날짜로 넘긴다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok(const <String, Object?>{'reports': <Object?>[]}),
      );

      await repo.fetchReceivedReports(before: DateTime(2026, 8, 3));

      verify(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: <String, Object?>{'before': '2026-08-03'},
        ),
      ).called(1);
    });

    test('서버 오류는 앱 오류로 바뀐다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: _path),
            statusCode: 500,
          ),
        ),
      );

      await expectLater(repo.fetchReceivedReports(), throwsA(isA<AppError>()));
    });

    test('담당이 없다는 신호로 바꾸지 않는다', () async {
      // 대화의 404 는 해제 신호지만, 이 목록은 담당 여부를 묻지 않는다.
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: _path),
            statusCode: 404,
          ),
        ),
      );

      await expectLater(
        repo.fetchReceivedReports(),
        throwsA(isNot(isA<CoachUnassignedException>())),
      );
    });

    test('빈 응답은 받아들이지 않는다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: _path),
          statusCode: 200,
        ),
      );

      await expectLater(repo.fetchReceivedReports(), throwsFormatException);
    });
  });

  group('목록 규칙', () {
    test('리포트 안내만 고르고 같은 주는 마지막 것 하나만 남긴다', () {
      final List<ReceivedReport> reports = foldReceivedReports(<CoachMessage>[
        plainMessage(),
        reportNotice(_week2, id: 'old', createdAt: DateTime(2026, 8, 9, 9)),
        reportNotice(_week2, id: 'new', createdAt: DateTime(2026, 8, 9, 21)),
        reportNotice(_week1, id: 'r1'),
      ], trainerName: '김트레이너');

      expect(reports.map((ReceivedReport r) => r.id).toList(), <String>[
        'r1',
        'new',
      ]);
      expect(reports.first.trainerName, '김트레이너');
    });

    test('시각이 붙은 주도 그날 자정으로 맞춘다', () {
      final List<ReceivedReport> reports = foldReceivedReports(<CoachMessage>[
        reportNotice(DateTime(2026, 8, 10, 9, 30)),
      ]);

      expect(reports.single.weekStart, _week1);
    });

    test('한 쪽이 다 차면 마지막 줄의 주가 다음 커서다', () {
      final List<ReceivedReport> all = foldReceivedReports(<CoachMessage>[
        reportNotice(_week1, id: 'r1'),
        reportNotice(_week2, id: 'r2'),
        reportNotice(_week3, id: 'r3'),
      ]);

      final ReceivedReportsPage first = pageReceivedReports(all, size: 2);

      expect(first.reports.map((ReceivedReport r) => r.id).toList(), <String>[
        'r1',
        'r2',
      ]);
      expect(first.nextBefore, _week2);

      final ReceivedReportsPage second = pageReceivedReports(
        all,
        before: first.nextBefore,
        size: 2,
      );
      expect(second.reports.single.id, 'r3');
      expect(second.nextBefore, isNull);
    });

    test('딱 한 쪽이면 다음 커서가 없다', () {
      final ReceivedReportsPage page = pageReceivedReports(
        foldReceivedReports(<CoachMessage>[
          reportNotice(_week1, id: 'r1'),
          reportNotice(_week2, id: 'r2'),
        ]),
        size: 2,
      );

      expect(page.reports, hasLength(2));
      expect(page.nextBefore, isNull);
    });
  });

  group('데모 저장소', () {
    test('데모 대화에 남은 리포트를 목록으로 준다', () async {
      final MockMemberCoachRepository coach = MockMemberCoachRepository();

      final ReceivedReportsPage page = await coach.fetchReceivedReports();

      expect(page.reports, isNotEmpty);
      expect(page.reports.first.trainerName, isNotEmpty);
      final List<DateTime> weeks = <DateTime>[
        for (final ReceivedReport r in page.reports) r.weekStart,
      ];
      expect(weeks.toSet(), hasLength(weeks.length), reason: '같은 주가 두 줄이다');
    });

    test('트레이너를 끊어도 받은 리포트는 남는다', () async {
      final MockGymRepository gym = MockGymRepository();
      final MockMemberCoachRepository coach = MockMemberCoachRepository(
        linked: () => gym.hasTrainer,
      );
      final List<String> before = <String>[
        for (final ReceivedReport r
            in (await coach.fetchReceivedReports()).reports)
          r.id,
      ];

      await gym.disconnectMyTrainer();

      await expectLater(
        coach.fetchChat(),
        throwsA(isA<CoachUnassignedException>()),
      );
      expect(<String>[
        for (final ReceivedReport r
            in (await coach.fetchReceivedReports()).reports)
          r.id,
      ], before);
    });
  });

  group('컨트롤러', () {
    test('첫 요청 하나로 목록이 선다 — 대화 길이와 무관하다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(_week3, id: 'r3'),
          for (int i = 0; i < 180; i++) chatLine(i),
          reportNotice(_week1, id: 'r1'),
        ],
      );
      final ProviderContainer container = _container(repository);

      final ReceivedReportsState state = await container.read(
        receivedReportsProvider.future,
      );

      expect(
        state.reports.map((ReceivedReport r) => r.weekStart).toList(),
        <DateTime>[_week1, _week3],
      );
      expect(state.hasMore, isFalse);
      expect(repository.reportCursors, <DateTime?>[null]);
      expect(repository.chatCursors, isEmpty, reason: '대화를 읽었다');
    });

    test('담당이 없어 대화를 읽을 수 없어도 목록은 선다', () async {
      final ProviderContainer container = _container(
        _ChatForbiddenRepository(
          coach: null,
          chat: <CoachMessage>[reportNotice(_week1, id: 'r1')],
        ),
      );

      final ReceivedReportsState state = await container.read(
        receivedReportsProvider.future,
      );

      expect(state.reports.single.id, 'r1');
      expect(state.reports.single.trainerName, isNull);
    });

    test('더 보기는 커서로 앞 쪽을 받아 뒤에 잇는다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(_week1, id: 'r1'),
          reportNotice(_week2, id: 'r2'),
          reportNotice(_week3, id: 'r3'),
          reportNotice(_week4, id: 'r4'),
        ],
      )..reportPageSize = 2;
      final ProviderContainer container = _container(repository);
      final ReceivedReportsState first = await container.read(
        receivedReportsProvider.future,
      );
      expect(first.reports, hasLength(2));
      expect(first.hasMore, isTrue);

      await container.read(receivedReportsProvider.notifier).loadMore();

      final ReceivedReportsState next = container
          .read(receivedReportsProvider)
          .requireValue;
      expect(next.reports.map((ReceivedReport r) => r.id).toList(), <String>[
        'r1',
        'r2',
        'r3',
        'r4',
      ]);
      expect(next.hasMore, isFalse);
      expect(next.loadingMore, isFalse);
      expect(repository.reportCursors, <DateTime?>[null, _week2]);
    });

    test('끝까지 받았으면 더 부르지 않는다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[reportNotice(_week1, id: 'r1')],
      );
      final ProviderContainer container = _container(repository);
      await container.read(receivedReportsProvider.future);

      await container.read(receivedReportsProvider.notifier).loadMore();

      expect(repository.reportCursors, <DateTime?>[null]);
    });

    test('앞 쪽을 못 읽어도 받아 둔 목록은 그대로고 다시 누를 수 있다', () async {
      final _OlderPageFailsRepository repository = _OlderPageFailsRepository(
        chat: <CoachMessage>[
          reportNotice(_week1, id: 'r1'),
          reportNotice(_week2, id: 'r2'),
          reportNotice(_week3, id: 'r3'),
        ],
      )..reportPageSize = 2;
      final ProviderContainer container = _container(repository);
      await container.read(receivedReportsProvider.future);

      await container.read(receivedReportsProvider.notifier).loadMore();

      final ReceivedReportsState failed = container
          .read(receivedReportsProvider)
          .requireValue;
      expect(failed.reports, hasLength(2));
      expect(failed.hasMore, isTrue);
      expect(failed.loadingMore, isFalse);

      repository.failing = false;
      await container.read(receivedReportsProvider.notifier).loadMore();

      expect(
        container.read(receivedReportsProvider).requireValue.reports,
        hasLength(3),
      );
    });

    test('목록을 못 읽으면 오류로 남는다', () async {
      final ProviderContainer container = _container(_ListFailsRepository());

      await expectLater(
        container.read(receivedReportsProvider.future),
        throwsStateError,
      );
    });
  });
}

/// 목록을 읽지 못하는 대역.
class _ListFailsRepository extends FakeMemberCoachRepository {
  @override
  Future<ReceivedReportsPage> fetchReceivedReports({DateTime? before}) =>
      Future<ReceivedReportsPage>.error(StateError('reports unavailable'));
}
