import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 미래 시작일로 받은 개인운동의 예정 한 줄. (#3106)
///
/// 오늘 목록 아래 `8/22(토)부터 · 빠르게 걷기 · 런지 · 플랭크 외 1개` 가 서고,
/// 오늘 걸린 것이 없어도 카드가 남는다. 지난 날짜에는 두지 않는다.

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-1',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '온케어짐',
  goal: '체중 감량',
);

const CoachRoutine _walk = CoachRoutine(
  id: 'walk',
  name: '저강도 걷기',
  minutes: 30,
  type: '유산소',
  reason: '',
  source: 'trainer',
);

// 2026-08-22 는 토요일이다.
final UpcomingRoutines _upcoming = UpcomingRoutines(
  startsOn: DateTime(2026, 8, 22),
  sentOn: DateTime(2026, 8, 20),
  names: const <String>['빠르게 걷기', '런지', '플랭크', '사이드 플랭크'],
);

/// 시작일 전에는 예정, 시작일부터는 오늘 목록에 그 운동을 주는 저장소.
class _StartingRepository extends MockMemberCoachRepository {
  bool started = false;

  @override
  Future<List<CoachRoutine>> fetchRoutines() async => <CoachRoutine>[
    _walk,
    if (started)
      const CoachRoutine(
        id: 'fast-walk',
        name: '빠르게 걷기',
        minutes: 30,
        type: '유산소',
        reason: '',
        source: 'trainer',
        deliveryKind: 'routine_only',
      ),
  ];

  @override
  Future<UpcomingRoutines?> fetchUpcomingRoutines() async =>
      started ? null : _upcoming;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<CoachRoutine> routines,
  UpcomingRoutines? upcoming,
  DateTime? day,
  Locale locale = const Locale('ko'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((ref) async => _coach),
        coachRoutinesProvider.overrideWith((ref) async => routines),
        coachRoutinesOnDayProvider.overrideWith((ref, _) async => routines),
        coachUpcomingRoutinesProvider.overrideWith((ref) async => upcoming),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: AiCoachingCard(day: day)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('오늘 목록 아래 예정 한 줄 — 앞의 셋과 나머지 개수', (tester) async {
    await _pump(
      tester,
      routines: const <CoachRoutine>[_walk],
      upcoming: _upcoming,
    );

    expect(find.byKey(const Key('coachUpcomingRoutines')), findsOneWidget);
    expect(
      find.textContaining(
        '8/22(토)부터 · 빠르게 걷기 · 런지 · 플랭크 외 1개',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // 오늘 목록은 그대로다 — 예정 줄은 체크할 수 없다.
    expect(find.text('저강도 걷기'), findsOneWidget);
    expect(find.textContaining('사이드 플랭크', findRichText: true), findsNothing);
  });

  testWidgets('오늘 걸린 것이 없어도 예정이 있으면 카드가 남는다', (tester) async {
    await _pump(tester, routines: const <CoachRoutine>[], upcoming: _upcoming);

    expect(find.byKey(const Key('aiCoachingCard')), findsOneWidget);
    expect(find.byKey(const Key('coachUpcomingRoutines')), findsOneWidget);
  });

  testWidgets('오늘 걸린 것도 예정도 없으면 카드를 그리지 않는다', (tester) async {
    await _pump(tester, routines: const <CoachRoutine>[]);

    expect(find.byKey(const Key('aiCoachingCard')), findsNothing);
    expect(find.byKey(const Key('coachUpcomingRoutines')), findsNothing);
  });

  testWidgets('지난 날짜에는 예정 줄을 두지 않는다', (tester) async {
    await _pump(
      tester,
      routines: const <CoachRoutine>[_walk],
      upcoming: _upcoming,
      day: DateTime(2026, 8, 18),
    );

    expect(find.byKey(const Key('aiCoachingCardPast')), findsOneWidget);
    expect(find.byKey(const Key('coachUpcomingRoutines')), findsNothing);
  });

  testWidgets('영어는 `From Sat 8/22 · … +1 more`', (tester) async {
    await _pump(
      tester,
      routines: const <CoachRoutine>[_walk],
      upcoming: _upcoming,
      locale: const Locale('en'),
    );

    expect(
      find.textContaining('From Sat 8/22 · ', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('+1 more', findRichText: true), findsOneWidget);
  });

  testWidgets('시작일에 오늘 목록을 다시 읽으면 예정이 빠지고 오늘 목록으로 넘어온다', (tester) async {
    final _StartingRepository repo = _StartingRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(repo),
        memberCoachProvider.overrideWith((ref) async => _coach),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: AiCoachingCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coachUpcomingRoutines')), findsOneWidget);
    expect(find.text('빠르게 걷기'), findsNothing);

    // 시작일 — 앱 복귀처럼 오늘 목록만 다시 읽는다. 예정도 함께 다시 읽힌다.
    repo.started = true;
    container.invalidate(coachRoutinesProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coachUpcomingRoutines')), findsNothing);
    expect(find.text('빠르게 걷기'), findsOneWidget);
  });

  group('upcomingRoutinesFromJson', () {
    test('시작일·보낸 날·운동 이름을 읽는다', () {
      final UpcomingRoutines? up = upcomingRoutinesFromJson(<String, Object?>{
        'starts_on': '2026-08-22',
        'sent_on': '2026-08-20',
        'names': <Object?>['빠르게 걷기', ' ', '런지'],
      });
      expect(up, isNotNull);
      expect(up!.startsOn, DateTime(2026, 8, 22));
      expect(up.sentOn, DateTime(2026, 8, 20));
      expect(up.names, <String>['빠르게 걷기', '런지']);
    });

    test('날짜가 깨지거나 운동이 없으면 예정이 없다', () {
      expect(
        upcomingRoutinesFromJson(<String, Object?>{
          'starts_on': 'x',
          'names': <Object?>['걷기'],
        }),
        isNull,
      );
      expect(
        upcomingRoutinesFromJson(<String, Object?>{
          'starts_on': '2026-08-22',
          'names': <Object?>[],
        }),
        isNull,
      );
    });
  });
}
