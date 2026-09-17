import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/presentation/health_focus_label.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart'
    show AppButton, AppTimeRangePickerDialog, OnCareColors;

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

/// 희망 시각을 범위 선택기 기본값(10:00–11:00)으로 확정한다.
///
/// "시간 협의"가 없어진 뒤(#1587) 폼을 끝까지 채우려면 이 단계가 반드시
/// 필요하다 — 선택기 내부 조작은 `consult_time_range_picker_test.dart` 의
/// 몫이라 여기서는 열고 확인만 누른다. 시작·종료를 한 창에서 고르므로
/// (#1779) 확인은 한 번이다 — 창 아래 두 버튼(취소 / 확인)의 오른쪽이다.
Future<void> _pickPreferredTime(WidgetTester tester) async {
  await _revealInForm(tester, find.byKey(const Key('consult-time')), 180);
  await tester.tap(find.byKey(const Key('consult-time')));
  await tester.pumpAndSettle();
  final Finder dialog = find.byType(AppTimeRangePickerDialog);
  expect(dialog, findsOneWidget);
  await tester.tap(
    find.descendant(of: dialog, matching: find.byType(AppButton)).last,
  );
  await tester.pumpAndSettle();
}

AppLocalizations _localizations(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
}

void main() {
  late ProviderContainer container;
  late GoRouter router;

  Future<void> pumpRoute(
    WidgetTester tester,
    String location, {
    bool hasMyGym = true,
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
        matching: find.text(_trainer.name),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.exConsultRequestTitle), findsOneWidget);
    expect(find.text(_trainer.name), findsOneWidget);
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

    expect(find.text(_trainer.name), findsOneWidget);
    expect(find.text(_trainer.role!), findsOneWidget);
    expect(find.textContaining(_gym.name), findsOneWidget);
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

  testWidgets('time is always required and no enum text leaks (#1256, #1587)', (
    WidgetTester tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.consultationRequestPath(gymId: _gym.id, trainerId: _trainer.id),
    );
    final AppLocalizations l = _localizations(tester);

    await _revealInForm(tester, find.text(l.exSendConsultRequest), 250);
    await tester.tap(find.text(l.exSendConsultRequest));
    await tester.pump();
    await _revealInForm(tester, find.text(l.exTimeRequired), -100);
    expect(find.text(l.exTimeRequired), findsOneWidget);
    // 정확한 시각 대신 코드 원문(`PreferredTimeSlot.flexible` 같은)이 화면에
    // 새어 나오면 안 된다.
    expect(find.textContaining('PreferredTimeSlot'), findsNothing);

    // "시간 협의"는 없앴다(#1587) — 시각을 채우는 길은 범위 선택기뿐이다.
    expect(find.byKey(const Key('consult-time-flexible')), findsNothing);
    expect(find.text(l.exTimeFlexible), findsNothing);

    await _pickPreferredTime(tester);
    await _revealInForm(tester, find.byKey(const Key('consult-time')), -100);
    expect(find.text(l.exTimeRequired), findsNothing);
    expect(find.byKey(const Key('consult-time')), findsOneWidget);
    // 고른 값이 필드에 그대로 보인다(선택기 기본값 10:00–11:00).
    expect(find.text('10:00–11:00'), findsOneWidget);
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
    await _revealInForm(tester, find.text(l.exSelectDate), 180);
    // 날짜 칸은 입력창과 같은 흰 채움이다 — 고르기 전후로 모양이 같다
    // (#1701, #1776).
    Finder dateMaterial = find
        .ancestor(
          of: find.byIcon(AppIcons.calendar),
          matching: find.byType(Material),
        )
        .first;
    expect(
      tester.widget<Material>(dateMaterial).color,
      OnCareColors.surfaceCard,
    );
    await tester.tap(find.text(l.exSelectDate));
    await tester.pumpAndSettle();
    // 공용 날짜 선택창(입력칸 + 달력, #1778)이 뜬다.
    final Finder datePickerDialog = find.byKey(const Key('portraitDatePicker'));
    expect(datePickerDialog, findsOneWidget);
    await tester.tap(find.byKey(const Key('portraitDatePickerConfirm')));
    await tester.pumpAndSettle();
    expect(find.text(l.exSelectDate), findsNothing);
    dateMaterial = find
        .ancestor(
          of: find.byIcon(AppIcons.calendar),
          matching: find.byType(Material),
        )
        .first;
    expect(
      tester.widget<Material>(dateMaterial).color,
      OnCareColors.surfaceCard,
    );
    // 희망 시각은 필수다(#1587). 선택기 자체의 조작(다이얼·직접 입력)은
    // `consult_time_range_picker_test.dart` 가 따로 다루므로, 여기서는 기본값
    // (10:00–11:00)을 그대로 확정한다.
    await _pickPreferredTime(tester);

    await _revealInForm(tester, find.text(l.exSendConsultRequest), 220);
    await tester.tap(find.text(l.exSendConsultRequest));
    await tester.pumpAndSettle();

    expect(find.text(l.exConsultReceived), findsOneWidget);
    final List<ConsultationRequest> requests = container.read(
      consultationRequestControllerProvider,
    );
    expect(requests, hasLength(1));
    expect(requests.single.status, ConsultationStatus.pending);

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
