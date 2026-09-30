/// 운동 탭의 `다음 PT` 배지는 오늘 이미 지난 일정을 적지 않는다. (#2636)
///
/// 오늘 오전 10시에 PT 를 받고 오후에 앱을 열면, 배지가 `오늘 오전 10:00` 을
/// 다음 PT 로 적고 내일 일정을 가렸다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';

const Gym _gym = Gym(
  id: 'gym-next-pt',
  name: '다음PT 테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['PT'],
);

const Trainer _trainer = Trainer(
  id: 'trainer-next-pt',
  gymId: 'gym-next-pt',
  name: '김트레이너',
  role: '전담 트레이너',
);

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-next-pt',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '다음PT 테스트 헬스장',
  goal: '',
);

/// 2026-08-20(목) 14:00 KST — 오전 PT 는 이미 끝났다.
final DateTime _afternoon = DateTime(2026, 8, 20, 14);

CoachSession _session(String id, DateTime date, String time) => CoachSession(
  id: id,
  date: date,
  time: time,
  type: '1:1 PT',
  durationMinutes: 50,
  status: '예정',
);

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required List<CoachSession> sessions,
}) async {
  useFixedKstDate(_afternoon);
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost',
            useMockApi: true,
          ),
        ),
        myGymProvider.overrideWith((ref) async => _gym),
        myTrainerProvider.overrideWith((ref) async => _trainer),
        myReservationsProvider.overrideWith(
          (ref) async => const <MyReservation>[],
        ),
        memberCoachProvider.overrideWith((ref) async => _coach),
        coachSessionsProvider.overrideWith((ref) async => sessions),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ExercisePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(ExercisePage)));
}

/// 배지 문구 그대로 — 화면이 쓰는 날짜·시각 형식을 따른다.
String _badge(WidgetTester tester, AppLocalizations l, DateTime at) {
  final String time = MaterialLocalizations.of(
    tester.element(find.byType(ExercisePage)),
  ).formatTimeOfDay(TimeOfDay.fromDateTime(at));
  return l.exNextPtSchedule('${DateFormat.MMMEd('ko').format(at)} $time');
}

void main() {
  testWidgets('오늘 오전에 끝난 일정만 있으면 아직 일정이 없다고 말한다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      sessions: <CoachSession>[_session('am', DateTime(2026, 8, 20), '10:00')],
    );

    expect(find.text(l.exNextPtNone), findsOneWidget);
  });

  testWidgets('오늘 지난 일정 대신 내일 일정을 다음 PT 로 적는다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      sessions: <CoachSession>[
        _session('am', DateTime(2026, 8, 20), '10:00'),
        _session('tomorrow', DateTime(2026, 8, 21), '19:00'),
      ],
    );

    expect(find.text(l.exNextPtNone), findsNothing);
    expect(
      find.text(_badge(tester, l, DateTime(2026, 8, 21, 19))),
      findsOneWidget,
    );
    expect(
      find.text(_badge(tester, l, DateTime(2026, 8, 20, 10))),
      findsNothing,
      reason: '이미 끝난 오늘 오전 PT 가 다음 PT 로 남았다',
    );
  });

  testWidgets('오늘 저녁 일정은 아직 오지 않았으니 그대로 다음 PT 다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      sessions: <CoachSession>[
        _session('pm', DateTime(2026, 8, 20), '19:00'),
        _session('tomorrow', DateTime(2026, 8, 21), '19:00'),
      ],
    );

    expect(find.text(l.exNextPtNone), findsNothing);
    expect(
      find.text(_badge(tester, l, DateTime(2026, 8, 20, 19))),
      findsOneWidget,
    );
  });
}
