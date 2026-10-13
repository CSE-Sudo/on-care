// 헬스장 상세 맨 아래의 문의 자리. (#3357)
//
// 상담은 소속 트레이너 한 사람에게 간다. 주변 검색·이름 검색으로만 찾은 헬스장에는
// 가입한 트레이너가 없어, 상담 버튼이 늘 "아직 소속 트레이너가 없어요" 시트로
// 끝났다. 소속 트레이너가 없으면 버튼 대신 안내 한 줄과 전화 문의를 둔다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/connection_disconnect.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppButton;

/// 등록된 헬스장 — 평점·태그·영업시간·전화가 모두 있다.
const Gym _gym = Gym(
  id: 'gym-inquiry',
  name: '문의 테스트 헬스장',
  address: '서울시 테스트구 문의로 1',
  distanceKm: 0.7,
  rating: 4.8,
  tags: <String>['근력운동'],
  weekdayHours: '06:00 - 23:00',
  weekendHours: '09:00 - 18:00',
  phone: '02-123-4567',
);

/// 외부 장소 검색에서만 찾은 헬스장 — 평점·태그·영업시간이 없다.
const Gym _externalGym = Gym(
  id: '328969863',
  name: '광안리 바다짐',
  address: '부산 수영구 광안해변로 1',
  distanceKm: 320,
  rating: 0,
  tags: <String>[],
  phone: '051-111-2222',
);

/// 전화번호도 모르는 외부 헬스장.
const Gym _externalNoPhone = Gym(
  id: '328969864',
  name: '송정 파도짐',
  address: '부산 해운대구 송정해변로 1',
  distanceKm: 330,
  rating: 0,
  tags: <String>[],
);

const Trainer _trainer = Trainer(
  id: 'trainer-inquiry',
  gymId: 'gym-inquiry',
  name: '김문의',
  role: '전담 트레이너',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const Key _consult = Key('gym-consult-start');
const Key _notice = Key('gym-inquiry-no-trainers');
const Key _call = Key('gym-call-inquiry');

void main() {
  /// 단건 조회가 불린 헬스장 id.
  late List<String> singleCalls;

  setUp(() => singleCalls = <String>[]);

  Future<void> pumpDetail(
    WidgetTester tester,
    Gym gym, {
    Future<List<Trainer>> Function()? trainers,
    bool listed = true,
    bool isMyGym = false,
    Gym? extra,
    Size size = const Size(360, 640),
    double textScale = 1,
    Locale locale = const Locale('ko'),
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.gymDetailPath(gym.id), extra: extra);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          nearbyGymsProvider.overrideWith(
            (ref) async => <Gym>[if (listed) gym],
          ),
          gymFinderResultsProvider.overrideWith(
            (ref) async => <Gym>[if (listed) gym],
          ),
          myGymProvider.overrideWith((ref) async => isMyGym ? gym : null),
          myTrainerProvider.overrideWith((ref) async => null),
          gymProvider(gym.id).overrideWith((ref) async {
            singleCalls.add(gym.id);
            return null;
          }),
          gymTrainersProvider(gym.id).overrideWith(
            (ref) =>
                trainers?.call() ??
                Future<List<Trainer>>.value(const <Trainer>[]),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // 끝나지 않는 조회가 있어 로딩 표시가 계속 돈다 — 정해진 만큼만 흘린다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  /// 상세 목록을 [target] 이 지어질 때까지 내린다.
  Future<void> scrollTo(WidgetTester tester, Finder target) =>
      tester.scrollUntilVisible(
        target,
        200,
        scrollable: find
            .byWidgetPredicate(
              (Widget widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );

  group('소속 트레이너가 없는 헬스장', () {
    testWidgets('상담 버튼 대신 안내와 전화 문의가 선다', (WidgetTester tester) async {
      await pumpDetail(tester, _gym);
      final AppLocalizations l = l10n(tester);

      await scrollTo(tester, find.byKey(_call));
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.text(l.exGymNoTrainersCallHint), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_call),
          matching: find.text(l.exGymCallInquiry),
        ),
        findsOneWidget,
      );
      expect(tester.widget<AppButton>(find.byKey(_call)).onPressed, isNotNull);
      // 눌러도 갈 곳이 없는 버튼은 두지 않는다.
      expect(find.byKey(_consult), findsNothing);
      expect(find.text(l.exGymConsultRequest), findsNothing);
    });

    testWidgets('전화 문의를 누르면 번호 시트가 뜬다', (WidgetTester tester) async {
      await pumpDetail(tester, _gym);
      final AppLocalizations l = l10n(tester);

      await scrollTo(tester, find.byKey(_call));
      await Scrollable.ensureVisible(
        tester.element(find.byKey(_call)),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.byKey(_call));
      await tester.pumpAndSettle();

      // 시트는 전화·복사를 고르게 한다 — 누르자마자 외부 앱을 열지 않는다.
      expect(find.text(l.exGymCall), findsOneWidget);
      expect(find.byTooltip(l.exGymCopyPhone), findsOneWidget);
      // 상담 트레이너를 고르는 시트가 아니다.
      expect(find.text(l.exGymConsultPickTrainer), findsNothing);
      expect(find.text(l.exGymConsultNoTrainers), findsNothing);
    });

    testWidgets('번호도 모르면 안내만 두고 전화 버튼은 없다', (WidgetTester tester) async {
      await pumpDetail(tester, _externalNoPhone);
      final AppLocalizations l = l10n(tester);

      await scrollTo(tester, find.byKey(_notice));
      expect(find.text(l.exGymNoTrainersHint), findsOneWidget);
      // 걸 번호가 없는데 전화하라고 하지 않는다.
      expect(find.text(l.exGymNoTrainersCallHint), findsNothing);
      expect(find.byKey(_call), findsNothing);
      expect(find.byKey(const Key('gym-detail-phone')), findsNothing);
      expect(find.byKey(_consult), findsNothing);
    });

    testWidgets('내 헬스장이면 문의 자리 없이 연결 해제만 둔다', (WidgetTester tester) async {
      await pumpDetail(tester, _gym, isMyGym: true);

      await scrollTo(tester, find.byType(DisconnectButton));
      expect(find.byType(DisconnectButton), findsOneWidget);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_call), findsNothing);
      expect(find.byKey(_consult), findsNothing);
    });

    testWidgets('영어에서도 안내와 전화 문의가 선다', (WidgetTester tester) async {
      await pumpDetail(tester, _gym, locale: const Locale('en'));
      final AppLocalizations l = l10n(tester);

      await scrollTo(tester, find.byKey(_call));
      expect(find.text(l.exGymNoTrainersCallHint), findsOneWidget);
      expect(find.text(l.exGymCallInquiry), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('좁은 화면·큰 글자에서도 안내가 넘치지 않는다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        _gym,
        size: const Size(320, 640),
        textScale: 1.3,
      );

      await scrollTo(tester, find.byKey(_call));
      expect(
        tester.getBottomRight(find.byKey(_notice)).dx,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('소속 트레이너가 있는 헬스장', () {
    testWidgets('지금처럼 상담 신청이 트레이너 선택 시트를 연다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        _gym,
        trainers: () => Future<List<Trainer>>.value(const <Trainer>[_trainer]),
      );
      final AppLocalizations l = l10n(tester);

      await scrollTo(tester, find.byKey(_consult));
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_call), findsNothing);
      // 번호 줄은 그대로 있다.
      expect(find.byKey(const Key('gym-detail-phone')), findsOneWidget);

      await Scrollable.ensureVisible(
        tester.element(find.byKey(_consult)),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.byKey(_consult));
      await tester.pumpAndSettle();

      expect(find.text(l.exGymConsultPickTrainer), findsOneWidget);
      expect(
        find.byKey(Key('gym-consult-trainer-${_trainer.id}')),
        findsOneWidget,
      );
    });
  });

  group('소속 트레이너 조회가 끝나지 않았을 때', () {
    testWidgets('읽는 중에는 "없음" 으로 단정하지 않는다', (WidgetTester tester) async {
      final Completer<List<Trainer>> pending = Completer<List<Trainer>>();
      await pumpDetail(
        tester,
        _gym,
        trainers: () => pending.future,
        settle: false,
      );

      await scrollTo(tester, find.byKey(_consult));
      expect(find.byKey(_consult), findsOneWidget);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_call), findsNothing);

      // 조회가 '없음' 으로 끝나면 그제야 안내로 바뀐다.
      pending.complete(const <Trainer>[]);
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(_notice));
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.byKey(_consult), findsNothing);
    });

    testWidgets('조회가 실패하면 상담 버튼을 남겨 시트에서 다시 시도하게 한다', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        _gym,
        trainers: () => Future<List<Trainer>>.error(StateError('offline')),
      );

      await scrollTo(tester, find.byKey(_consult));
      expect(find.byKey(_consult), findsOneWidget);
      // 못 읽은 것을 "가입한 트레이너가 없다" 고 말하지 않는다.
      expect(find.byKey(_notice), findsNothing);
    });
  });

  group('검색 결과로 들어온 외부 헬스장', () {
    testWidgets('평점·태그·영업시간 없이도 주소와 전화 문의로 선다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        _externalGym,
        listed: false,
        extra: _externalGym,
      );
      final AppLocalizations l = l10n(tester);

      expect(find.text(_externalGym.name), findsOneWidget);
      expect(find.text(_externalGym.address), findsOneWidget);
      // 모르는 값의 칸은 그리지 않는다.
      expect(find.text(l.exSpecialty), findsNothing);
      expect(find.text(l.exHours), findsNothing);
      expect(find.text(l.exAffiliatedTrainer), findsNothing);
      // 받아 온 값으로 그린다 — 서버에 없는 헬스장을 id 로 다시 읽지 않는다.
      expect(singleCalls, isEmpty);

      await scrollTo(tester, find.byKey(_call));
      expect(find.text(l.exGymNoTrainersCallHint), findsOneWidget);
      expect(find.byKey(const Key('gym-detail-phone')), findsOneWidget);
      expect(find.byKey(_consult), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('번호도 없으면 주소와 안내만 남는다', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        _externalNoPhone,
        listed: false,
        extra: _externalNoPhone,
      );
      final AppLocalizations l = l10n(tester);

      expect(find.text(_externalNoPhone.name), findsOneWidget);
      expect(find.text(_externalNoPhone.address), findsOneWidget);
      await scrollTo(tester, find.byKey(_notice));
      expect(find.text(l.exGymNoTrainersHint), findsOneWidget);
      expect(find.byKey(_call), findsNothing);
      expect(find.byKey(_consult), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
