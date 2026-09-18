import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/presentation/health_focus_label.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppButton;

import '../../support/consultation_test_support.dart';

const Gym _gym = Gym(
  id: 'gym-consult',
  name: '상담 테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.7,
  rating: 4.8,
  tags: <String>['근력운동'],
);

const Trainer _trainer = Trainer(
  id: 'trainer-consult',
  gymId: 'gym-consult',
  name: '김상담',
  role: '전담 트레이너',
);

/// 트레이너가 열어 둔 빈 자리 둘. 폼은 시작까지 4시간 이상 남은 자리만 받으므로
/// 모레 저녁으로 둔다(#1873). 길이가 서로 달라야 화면이 자리의 길이를 그대로
/// 쓰는지(코드 상수가 아니라) 보인다.
List<TrainerSlot> _openSlots() {
  // 기기 시각이 아니라 KST 로 잡는다 — 목 저장소와 폼 하한이 `nowKst()` 로
  // 비교하므로, 여기만 기기 시각이면 CI(UTC)에서 9시간 어긋난다.
  final DateTime twoDays = nowKst().add(const Duration(days: 2));
  final DateTime evening = DateTime(
    twoDays.year,
    twoDays.month,
    twoDays.day,
    19,
  );
  return <TrainerSlot>[
    TrainerSlot(
      id: 'slot-evening',
      trainerId: _trainer.id,
      startsAt: evening,
      booked: false,
      sessionType: '1:1 PT',
      durationMinutes: 30,
    ),
    TrainerSlot(
      id: 'slot-late',
      trainerId: _trainer.id,
      startsAt: evening.add(const Duration(hours: 1)),
      booked: false,
      sessionType: '1:1 PT',
      // 기본 길이 60분 — 첫 자리(30분)와 달라야 화면이 자리의 길이를 쓰는지 보인다.
    ),
  ];
}

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

ConsultationRequest _request({String trainerId = 'trainer-consult'}) {
  return ConsultationRequest(
    id: 'request-$trainerId',
    trainerId: trainerId,
    trainerName: _trainer.name,
    trainerRole: _trainer.role,
    exerciseGoal: ExerciseGoal.weightLoss,
    healthPurposeType: HealthPurposeType.chronic,
    healthPurposeDetail: null,
    preferredDate: DateTime(2026, 7, 28),
    preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 14, minute: 0)),
    message: null,
    status: ConsultationStatus.pending,
    createdAt: DateTime(2026, 7, 26),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder target, double delta) {
  final Finder pageScroll = find
      .byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .last;
  return tester.scrollUntilVisible(target, delta, scrollable: pageScroll);
}

/// 상담 요청 폼 안에서 대상을 화면(뷰포트) 안까지 스크롤해 실제로 탭 가능한
/// 상태로 만든다.
///
/// `_scrollTo` 가 잡는 "마지막 `Scrollable`" 은 이 화면에 있는 `문의 내용`
/// `TextField` 가 내부적으로 쓰는 편집 스크롤(`restorationId: "editable"`,
/// 스크롤 범위 항상 0)을 집어버려 아무 것도 스크롤하지 못한다 — 상담 폼은
/// `consult-form` 키로 직접 잡아야 한다는 것을 그 위젯 코멘트(#640)가 이미
/// 말하고 있다. `.first` 로 폼 자신의 `Scrollable` 을 고른다(`.last` 를 쓰면
/// 트리 순회가 더 깊이 들어간 `TextField` 내부 스크롤을 집는다).
///
/// 두 단계로 나뉜다: `scrollUntilVisible` 은 대상이 위젯 트리에 **지어지는**
/// 순간(= cacheExtent 안)에 멈추므로, 화면 안까지 마저 스크롤하는
/// `Scrollable.ensureVisible` 을 이어서 부른다. 정렬은 가운데(0.5)로 둔다 —
/// 기본 정렬(0.0, 위쪽 끝맞춤)은 대상을 AppBar 바로 아래 경계에 딱 붙여,
/// 반올림 오차로 몇 픽셀만 가려져도 탭이 빗나간다. 마지막 `pump` 가 없으면
/// `ensureVisible` 의 스크롤이 다음 프레임에야 반영되어 같은 문제가 난다.
///
/// 상단 데이터 공유 안내(#935)로 폼이 길어지기 전까지는 대부분의 항목이 초기
/// 뷰포트+cacheExtent 안에 있어 이 구분이 드러나지 않았을 뿐이다.
Future<void> _revealInForm(
  WidgetTester tester,
  Finder target,
  double delta,
) async {
  final Finder formScrollable = find
      .descendant(
        of: find.byKey(const Key('consult-form')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(target, delta, scrollable: formScrollable);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
}

/// 첫 번째 빈 자리를 고른다. (#1873)
///
/// 희망 날짜·시각을 입력하던 두 칸은 없어졌다 — 트레이너가 열어 둔 자리 중
/// 하나를 누르는 것이 시각을 정하는 유일한 길이다.
Future<void> _pickSlot(WidgetTester tester) async {
  await _revealInForm(
    tester,
    find.byKey(const Key('consult-slot-slot-evening')),
    180,
  );
  await tester.tap(find.byKey(const Key('consult-slot-slot-evening')));
  await tester.pumpAndSettle();
}

/// 접수를 서버 한도로 거절하는 저장소. (#1628)
class _LimitedRepository implements ConsultationRepository {
  _LimitedRepository(this.error);

  final Exception error;

  @override
  Future<String> create(ConsultationDraft draft) async => throw error;

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async => const <ConsultationRequest>[];

  @override
  Future<void> cancel(String consultationId) async {}

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

AppLocalizations _localizations(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
}

/// 상담 대상 카드의 `이름 직함` 한 글줄. 두 글씨가 한 문단이라(#2082) 이름만
/// 따로 `find.text` 로 잡히지 않는다.
String _targetNameRole(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('consult-target-name-role')))
    .textSpan!
    .toPlainText();

void main() {
  late ProviderContainer container;
  late GoRouter router;

  Future<void> pumpRoute(
    WidgetTester tester,
    String location, {
    bool hasMyGym = true,
    List<TrainerSlot>? slots,
    ConsultationRepository? repository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container = ProviderContainer(
      overrides: <Override>[
        // gymRepository·consultationRepository 가 이 값으로 mock/실 API 를 고른다.
        appConfigProvider.overrideWithValue(_config),
        nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
        // 헬스장 상세·찾기는 제휴 + 카카오를 합친 provider 를 본다(#329).
        gymFinderResultsProvider.overrideWith((ref) async => const <Gym>[_gym]),
        myGymProvider.overrideWith((ref) async => hasMyGym ? _gym : null),
        myTrainerProvider.overrideWith(
          (ref) async => hasMyGym ? _trainer : null,
        ),
        trainerProvider(_trainer.id).overrideWith((ref) async => _trainer),
        gymTrainersProvider(
          _gym.id,
        ).overrideWith((ref) async => const <Trainer>[_trainer]),
        // 폼이 보여 줄 자리(#1873). 목 헬스장 저장소는 이 테스트의 트레이너를
        // 모르므로 직접 준다.
        consultationSlotsProvider(
          _trainer.id,
        ).overrideWith((ref) async => slots ?? _openSlots()),
        if (repository != null)
          consultationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'controller blocks a duplicate trainer but not a different one',
    () async {
      final ConsultationRequestController controller =
          newTestConsultationController();

      expect(await seedPending(controller, _request()), isTrue);
      expect(await seedPending(controller, _request()), isFalse);
      // 답이 없는 트레이너 한 명이 회원을 묶어 두면 안 된다.
      expect(
        await seedPending(controller, _request(trainerId: 'trainer-other')),
        isTrue,
      );
      expect(controller.state, hasLength(2));
    },
  );

  testWidgets('gym CTA picks a trainer before opening the form', (
    WidgetTester tester,
  ) async {
    await pumpRoute(tester, AppRoutes.gymDetailPath(_gym.id), hasMyGym: false);
    final AppLocalizations l = _localizations(tester);
    await _scrollTo(tester, find.text(l.exGymConsultRequest), 250);
    await tester.tap(find.text(l.exGymConsultRequest));
    await tester.pumpAndSettle();

    // 헬스장에서 시작해도 요청은 트레이너 한 사람 앞으로 간다 — 고르기 전에는
    // 폼으로 넘어가지 않는다.
    expect(find.text(l.exGymConsultPickTrainer), findsOneWidget);
    expect(find.text(l.exConsultRequestTitle), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('gym-consult-trainer-picker')),
        matching: find.textContaining(_trainer.name),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.exConsultRequestTitle), findsOneWidget);
    expect(_targetNameRole(tester), contains(_trainer.name));
    expect(find.textContaining(_gym.name), findsOneWidget);
  });

  testWidgets('trainer detail CTA opens the form for that trainer', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.trainerDetailPath(_trainer.id),
      hasMyGym: false,
    );
    final AppLocalizations l = _localizations(tester);
    await _scrollTo(tester, find.text(l.exTrainerConsultRequest), 250);
    await tester.tap(find.text(l.exTrainerConsultRequest));
    await tester.pumpAndSettle();

    // 이름과 직함은 한 글줄이다 — 직함이 이름 아래 줄로 내려가지 않는다
    // (#2082). 소속 헬스장은 그 아래 제 줄에 따로 선다.
    final Finder nameRole = find.byKey(const Key('consult-target-name-role'));
    expect(nameRole, findsOneWidget);
    expect(tester.widget<Text>(nameRole).maxLines, 1);
    expect(
      _targetNameRole(tester),
      allOf(contains(_trainer.name), contains(_trainer.role!)),
    );
    expect(find.text(_trainer.role!), findsNothing);
    final Finder gymLine = find.textContaining(_gym.name);
    expect(gymLine, findsOneWidget);
    expect(
      tester.getTopLeft(gymLine).dy,
      greaterThan(tester.getBottomLeft(nameRole).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows what gets shared with the trainer once the request is accepted (#935)',
    (WidgetTester tester) async {
      await pumpRoute(
        tester,
        AppRoutes.consultationRequestPath(
          gymId: _gym.id,
          trainerId: _trainer.id,
        ),
      );
      final AppLocalizations l = _localizations(tester);

      expect(
        find.byKey(const Key('consult-data-sharing-notice')),
        findsOneWidget,
      );
      expect(find.text(l.exConsultDataSharingNotice), findsOneWidget);
    },
  );

  testWidgets(
    'validation requires a goal, and "기타" requires a message detail (#1112)',
    (WidgetTester tester) async {
      await pumpRoute(
        tester,
        AppRoutes.consultationRequestPath(
          gymId: _gym.id,
          trainerId: _trainer.id,
        ),
      );
      final AppLocalizations l = _localizations(tester);

      await _revealInForm(tester, find.text(l.exSendConsultRequest), 250);
      await tester.tap(find.text(l.exSendConsultRequest));
      await tester.pump();
      // 맨 아래에서 제출한 뒤라 상단의 에러 문구가 캐시 범위 밖으로 빠져 있다 —
      // 다시 위로 스크롤해야 트리에 지어진다.
      await _revealInForm(tester, find.text(l.exGoalRequired), -250);
      expect(find.text(l.exGoalRequired), findsOneWidget);

      // 운동 목표 하나만 고른다 — 건강관리 목적은 더는 따로 없다(#1112).
      await tester.tap(find.text(l.exOptionOther));
      await tester.pump();
      await _revealInForm(tester, find.text(l.exOtherGoalDetailRequired), 200);
      expect(find.text(l.exOtherGoalDetailRequired), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('consult-message')),
        '무릎 통증 관리',
      );
      await tester.pump();
      expect(find.text(l.exOtherGoalDetailRequired), findsNothing);
    },
  );

  testWidgets('운동 목표 선택지가 온보딩 건강 목표와 같다 (#1992)', (WidgetTester tester) async {
    await pumpRoute(
      tester,
      AppRoutes.consultationRequestPath(gymId: _gym.id, trainerId: _trainer.id),
    );
    final AppLocalizations l = _localizations(tester);

    // 온보딩·MY 가 고르는 건강 목표 여덟 종이 같은 문구·같은 순서로 서고, 그
    // 뒤에 `기타` 가 붙는다. 두 화면이 선택지를 한 곳에서 읽는지 보는 자리다.
    final List<String> expected = <String>[
      for (final String focus in kHealthFocusOptions)
        healthFocusLabel(l, focus),
      l.exOptionOther,
    ];
    for (final (int i, String label) in expected.indexed) {
      final Finder chip = find.byKey(ValueKey<String>('consult-goal-$i'));
      await _revealInForm(tester, chip, 100);
      expect(
        find.descendant(of: chip, matching: find.text(label)),
        findsOneWidget,
        reason: '$i 번째 칩은 "$label" 이어야 한다',
      );
    }
    // 목록이 더 길지 않다 — 없앤 `건강 관리` 가 남아 있으면 여기서 걸린다.
    expect(
      find.byKey(ValueKey<String>('consult-goal-${expected.length}')),
      findsNothing,
    );
    expect(find.text(l.exGoalHealth), findsNothing);
  });

  testWidgets('자리를 골라야 신청되고, 고른 자리의 길이를 그대로 보인다 (#1873)', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.consultationRequestPath(gymId: _gym.id, trainerId: _trainer.id),
    );
    final AppLocalizations l = _localizations(tester);

    // 희망 날짜·시각을 적는 두 칸은 없어졌다 — 시각은 트레이너가 연 자리에서만 온다.
    expect(find.byKey(const Key('consult-date')), findsNothing);
    expect(find.byKey(const Key('consult-time')), findsNothing);

    await _revealInForm(tester, find.text(l.exSendConsultRequest), 250);
    await tester.tap(find.text(l.exSendConsultRequest));
    await tester.pump();
    await _revealInForm(tester, find.text(l.exConsultSlotRequired), -100);
    expect(find.text(l.exConsultSlotRequired), findsOneWidget);

    // 길이는 트레이너가 자리를 열 때 정한 값이다 — 코드 상수 30분을 더하지 않는다.
    // 두 번째 자리는 60분이라 종료가 한 시간 뒤다.
    final List<TrainerSlot> slots = _openSlots();
    String hm(DateTime v) =>
        '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    final DateTime late = slots[1].startsAt;
    expect(
      find.textContaining(
        '${hm(late)}–${hm(late.add(const Duration(minutes: 60)))}',
      ),
      findsOneWidget,
    );

    await _pickSlot(tester);
    await _revealInForm(
      tester,
      find.byKey(const Key('consult-slot-slot-evening')),
      -100,
    );
    expect(find.text(l.exConsultSlotRequired), findsNothing);
  });

  testWidgets('열린 자리가 없으면 신청할 수 없고 헬스장 전화를 안내한다 (#1873)', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.consultationRequestPath(gymId: _gym.id, trainerId: _trainer.id),
      slots: const <TrainerSlot>[],
    );
    final AppLocalizations l = _localizations(tester);

    // 앱은 없는 시간을 만들어 내지 않는다 — 전화로 내보낸다.
    await _revealInForm(
      tester,
      find.byKey(const Key('consult-slots-empty')),
      180,
    );
    expect(find.text(l.exConsultSlotsEmptyTitle), findsOneWidget);
    expect(find.byKey(const Key('consult-slots-empty-cta')), findsOneWidget);

    await _revealInForm(tester, find.byKey(const Key('consult-submit')), 220);
    final AppButton submit = tester.widget<AppButton>(
      find.byKey(const Key('consult-submit')),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('valid submission stores pending and history shows status', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.consultationRequestPath(gymId: _gym.id, trainerId: _trainer.id),
    );
    final AppLocalizations l = _localizations(tester);

    // 데이터 공유 동의 없이는 보낼 수 없다 (#1022) — 수락되는 순간 넘어가는
    // 것이 회원의 건강 기록이라 신청 화면에서 동의를 받는다. 동의 줄은 대상
    // 카드 바로 아래(=화면 위쪽)에 있다.
    await tester.tap(find.byKey(const Key('consultDataSharingConsent')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.healthFocusWeightLoss));
    // 희망 날짜·시각을 입력하는 대신 트레이너가 열어 둔 자리를 고른다(#1873).
    await _pickSlot(tester);

    await _revealInForm(tester, find.text(l.exSendConsultRequest), 220);
    await tester.tap(find.text(l.exSendConsultRequest));
    await tester.pumpAndSettle();

    expect(find.text(l.exConsultReceived), findsOneWidget);
    final List<ConsultationRequest> requests = container.read(
      consultationRequestControllerProvider,
    );
    expect(requests, hasLength(1));
    expect(requests.single.status, ConsultationStatus.pending);
    // 고른 자리가 그대로 실린다 — 상담 내역이 확정 일시를 그리는 값이다.
    expect(requests.single.slotStartsAt, _openSlots().first.startsAt);
    expect(requests.single.slotDurationMinutes, 30);

    await tester.tap(find.text(l.exReturnExercise));
    await tester.pumpAndSettle();
    // 운동 탭 본문에는 상담 요약을 다시 만들지 않는다(#1287). 내역 화면이
    // 요청 상태를 확인하는 한 곳이다.
    expect(find.text(l.exConsultStatusSection), findsNothing);
    expect(find.text(l.exConsultPendingStatus), findsNothing);

    router.go(AppRoutes.consultationHistory);
    await tester.pumpAndSettle();
    expect(find.text(l.exConsultHistoryTitle), findsOneWidget);
    expect(find.text(l.exConsultPendingStatus), findsOneWidget);

    router.go(AppRoutes.gymDetailPath(_gym.id));
    await tester.pumpAndSettle();
    expect(find.text(l.exConsultPendingCta), findsNothing);
    expect(find.text(l.exGymConsultRequest), findsNothing);
  });

  for (final (
        String name,
        Exception error,
        String Function(AppLocalizations) message,
      )
      in <(String, Exception, String Function(AppLocalizations))>[
        (
          '대기 상한',
          const TooManyPendingConsultations(limit: 3),
          (AppLocalizations l) => l.exConsultTooManyPending(3),
        ),
        (
          '24시간 한도',
          const ConsultationRateLimited(retryAfter: Duration(hours: 5)),
          (AppLocalizations l) => l.exConsultRateLimitedHours(5),
        ),
      ]) {
    testWidgets('$name에 걸리면 안내하고 대기 중으로 표시하지 않는다 (#1628)', (
      WidgetTester tester,
    ) async {
      await pumpRoute(
        tester,
        AppRoutes.consultationRequestPath(
          gymId: _gym.id,
          trainerId: _trainer.id,
        ),
        repository: _LimitedRepository(error),
      );
      final AppLocalizations l = _localizations(tester);
      await tester.tap(find.byKey(const Key('consultDataSharingConsent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.healthFocusWeightLoss));
      await _pickSlot(tester);

      await _revealInForm(tester, find.text(l.exSendConsultRequest), 220);
      await tester.tap(find.text(l.exSendConsultRequest));
      await tester.pump();

      expect(find.text(message(l)), findsOneWidget);
      // 이 트레이너에게는 신청한 적이 없다 — "이미 대기 중" 으로 잠그면 한도가
      // 풀린 뒤에도 신청하지 못한다.
      expect(container.read(consultationRequestControllerProvider), isEmpty);
      expect(find.text(l.exConsultReceived), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  }

  testWidgets('invalid target type and gym id show a safe state', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      '${AppRoutes.consultationRequest}?targetType=invalid&gymId=missing',
    );
    final AppLocalizations l = _localizations(tester);
    expect(find.text(l.exConsultTargetNotFound), findsOneWidget);
    expect(tester.takeException(), isNull);

    router.go(
      AppRoutes.consultationRequestPath(
        gymId: 'missing',
        trainerId: _trainer.id,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l.exConsultTargetNotFound), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
