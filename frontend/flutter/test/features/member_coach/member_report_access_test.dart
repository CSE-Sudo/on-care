/// 회원은 받았거나 산 주의 리포트만 연다. (#3366)
///
/// 서버가 `GET /me/coach/weekly-report` 에서 판정하고, 받지도 사지도 않은 주는
/// 403 이다. 여기서는 앱 쪽 두 가지를 본다 — 데모가 서버와 **같은 두 근거**(받은
/// 리포트 목록, 포인트로 산 주)로 판정하는지, 그리고 403 을 "다시 시도" 가
/// 아니라 아직 받지 않은 리포트로 안내하는지.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_report_purchase.dart';
import 'package:oncare/features/member_coach/data/repositories/member_report_sheet_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_report_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_opener.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_report/oncare_report.dart';

import '../../helpers/fake_member_coach_repository.dart';

final DateTime _lastWeek = DateTime(2026, 9, 14);
final DateTime _twoWeeksAgo = DateTime(2026, 9, 7);
final DateTime _threeWeeksAgo = DateTime(2026, 8, 31);

Future<WeeklyReportPurchases> Function() _bought([
  List<DateTime> weeks = const <DateTime>[],
]) =>
    () async => WeeklyReportPurchases(
      weeks: weeks,
      nextWeekStart: _lastWeek,
      cost: 300,
    );

Future<WeeklyReportPurchases> _offline() async => throw Exception('offline');

/// 받은 리포트 목록을 읽지 못하는 저장소.
class _NoReportsRepository extends FakeMemberCoachRepository {
  @override
  Future<ReceivedReportsPage> fetchReceivedReports({DateTime? before}) async =>
      throw Exception('offline');
}

/// 대화를 읽을 수 없는 저장소 — 담당이 해제된 회원. 받은 리포트는 남는다.
class _UnassignedRepository extends FakeMemberCoachRepository {
  _UnassignedRepository({super.chat}) : super(coach: null);

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      throw const CoachUnassignedException();
}

class _StubProfile extends ProfileController {
  @override
  Future<UserProfile> build() async => const UserProfile(
    id: 'user-7d4e9a2c5f18',
    name: '김민수',
    email: 'minsu@oncare.com',
  );
}

/// 서버가 403 으로 답하는 주를 흉내 낸다.
class _ForbiddenRepository implements MemberReportSheetRepository {
  int calls = 0;

  @override
  Future<ReportSheetInputs> fetch({
    required DateTime weekStart,
    ReportSheetGoals goals = const ReportSheetGoals(),
    String? messageId,
  }) async {
    calls++;
    throw const ForbiddenError(detail: '아직 받지 않은 주간 리포트예요.');
  }
}

class _UnusedGenerator extends MemberReportPdfGenerator {
  _UnusedGenerator();

  int calls = 0;

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required ReportSheetInputs inputs,
    required MemberReportFeedback feedback,
    DateTime? today,
  }) async {
    calls++;
    return Uint8List(0);
  }
}

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  group('데모의 열람 판정', () {
    test('트레이너가 리포트를 보낸 주는 열린다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: FakeMemberCoachRepository(
          chat: <CoachMessage>[reportNotice(_lastWeek)],
        ),
        purchases: _bought(),
      );

      expect(opens, isTrue);
    });

    test('포인트로 산 주는 열린다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: FakeMemberCoachRepository(),
        purchases: _bought(<DateTime>[_lastWeek]),
      );

      expect(opens, isTrue);
    });

    test('받지도 사지도 않은 주는 열리지 않는다', () async {
      final bool opens = await demoReportWeekOpens(
        _threeWeeksAgo,
        coach: FakeMemberCoachRepository(
          chat: <CoachMessage>[reportNotice(_lastWeek)],
        ),
        purchases: _bought(<DateTime>[_twoWeeksAgo]),
      );

      expect(opens, isFalse);
    });

    test('리포트가 아닌 대화는 받은 근거가 아니다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: FakeMemberCoachRepository(chat: <CoachMessage>[plainMessage()]),
        purchases: _bought(),
      );

      expect(opens, isFalse);
    });

    test('다른 주의 리포트 안내는 이 주를 열지 않는다', () async {
      final FakeMemberCoachRepository coach = FakeMemberCoachRepository(
        chat: <CoachMessage>[reportNotice(_twoWeeksAgo)],
      );

      expect(
        await demoReportWeekOpens(
          _lastWeek,
          coach: coach,
          purchases: _bought(),
        ),
        isFalse,
      );
      expect(
        await demoReportWeekOpens(
          _twoWeeksAgo,
          coach: coach,
          purchases: _bought(),
        ),
        isTrue,
      );
    });

    test('시각이 붙은 날짜도 같은 날이면 같은 주다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: FakeMemberCoachRepository(
          chat: <CoachMessage>[reportNotice(DateTime(2026, 9, 14, 9, 30))],
        ),
        purchases: _bought(),
      );

      expect(opens, isTrue);
    });

    test('받은 목록을 읽지 못해도 산 주는 열린다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: _NoReportsRepository(),
        purchases: _bought(<DateTime>[_lastWeek]),
      );

      expect(opens, isTrue);
    });

    test('산 주를 읽지 못해도 받은 주는 열린다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: FakeMemberCoachRepository(
          chat: <CoachMessage>[reportNotice(_lastWeek)],
        ),
        purchases: _offline,
      );

      expect(opens, isTrue);
    });

    test('둘 다 읽지 못하면 열리지 않는다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: _NoReportsRepository(),
        purchases: _offline,
      );

      expect(opens, isFalse);
    });

    // 받은 리포트는 대화가 아니라 회원에게 남는 기록이다(#3348).
    test('담당이 해제되어 대화를 읽을 수 없어도 받은 주는 열린다', () async {
      final bool opens = await demoReportWeekOpens(
        _lastWeek,
        coach: _UnassignedRepository(
          chat: <CoachMessage>[reportNotice(_lastWeek)],
        ),
        purchases: _bought(),
      );

      expect(opens, isTrue);
    });

    test('받은 목록의 첫 쪽 밖에 있는 주도 찾는다', () async {
      final FakeMemberCoachRepository coach = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(_lastWeek, id: 'r1'),
          reportNotice(_twoWeeksAgo, id: 'r2'),
          reportNotice(_threeWeeksAgo, id: 'r3'),
        ],
      )..reportPageSize = 1;

      expect(
        await demoReportWeekOpens(
          _threeWeeksAgo,
          coach: coach,
          purchases: _bought(),
        ),
        isTrue,
      );
      expect(coach.reportCursors, <DateTime?>[null, _lastWeek, _twoWeeksAgo]);
    });

    test('찾는 주를 지나치면 더 넘기지 않는다', () async {
      final FakeMemberCoachRepository coach = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(_lastWeek, id: 'r1'),
          reportNotice(_threeWeeksAgo, id: 'r3'),
          reportNotice(DateTime(2026, 8, 24), id: 'r4'),
        ],
      )..reportPageSize = 1;

      expect(
        await demoReportWeekOpens(
          _twoWeeksAgo,
          coach: coach,
          purchases: _bought(),
        ),
        isFalse,
      );
      // 첫 쪽(지난주) 다음 쪽이 3주 전이라, 2주 전은 없다는 것이 거기서 갈린다.
      expect(coach.reportCursors, <DateTime?>[null, _lastWeek]);
    });

    test('긴 대화의 앞쪽에 있는 리포트 안내도 찾는다', () async {
      // 대화 길이는 목록과 무관하다 — 대화를 끝까지 읽지 않아도 선다.
      final FakeMemberCoachRepository coach = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(
            _threeWeeksAgo,
            id: 'old-report',
            createdAt: DateTime(2026, 9, 6, 21),
          ),
          for (int i = 0; i < 120; i++)
            CoachMessage(
              id: 'p$i',
              sender: CoachSender.trainer,
              body: '메시지 $i',
              timeLabel: '',
              createdAt: DateTime(2026, 9, 10).add(Duration(minutes: i)),
            ),
        ],
      );

      expect(
        await demoReportWeekOpens(
          _threeWeeksAgo,
          coach: coach,
          purchases: _bought(),
        ),
        isTrue,
      );
    });
  });

  group('열지 못했을 때의 안내', () {
    test('403 은 아직 받지 않은 리포트라고 알린다', () {
      expect(
        reportOpenFailureText(ko, const ForbiddenError()),
        ko.coachReportNotReceived,
      );
    });

    test('그 밖의 실패는 다시 시도를 권한다', () {
      for (final Object error in <Object>[
        const NetworkError(),
        const ServerError(statusCode: 500),
        const NotFoundError(),
        Exception('boom'),
      ]) {
        expect(
          reportOpenFailureText(ko, error),
          ko.coachChatPdfOpenFailed,
          reason: '$error',
        );
      }
    });

    test('두 안내는 서로 다른 문장이다', () {
      expect(ko.coachReportNotReceived, isNot(ko.coachChatPdfOpenFailed));
    });

    test('첨부 없는 리포트가 403 이면 그 오류가 여는 쪽까지 올라온다', () async {
      final _ForbiddenRepository repository = _ForbiddenRepository();
      final _UnusedGenerator generator = _UnusedGenerator();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberReportSheetRepositoryProvider.overrideWithValue(repository),
          memberReportPdfGeneratorProvider.overrideWithValue(generator),
          profileProvider.overrideWith(_StubProfile.new),
        ],
      );
      addTearDown(container.dispose);

      Object? caught;
      try {
        await loadCoachReportPdf(
          container.read,
          l: ko,
          message: reportNotice(_lastWeek),
          weekStart: _lastWeek,
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<ForbiddenError>());
      expect(reportOpenFailureText(ko, caught!), ko.coachReportNotReceived);
      expect(repository.calls, 1);
      // 받지 않은 주로는 문서를 굽지 않는다.
      expect(generator.calls, 0);
    });
  });
}
