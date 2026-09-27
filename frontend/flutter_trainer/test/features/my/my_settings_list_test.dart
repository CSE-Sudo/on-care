/// 트레이너 내 정보·설정 개편. (#2264)
///
/// 설정은 회원 앱처럼 한 장짜리 목록이고 알림·계정·고객 지원은 하위 화면으로,
/// 프로필 수정은 내 정보 본문과 떨어진 별도 화면으로 연다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

/// 쓰기가 늘 실패하는 저장소 — 끊긴 네트워크 대신이다.
class _FailingRepository implements TrainerSettingsRepository {
  const _FailingRepository();

  @override
  Future<TrainerSettings> load() async => const TrainerSettings();

  @override
  Future<TrainerSettings> save(TrainerSettings settings) async {
    throw const NetworkError(message: 'offline');
  }
}

Future<void> _openSettings(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
}) {
  return pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.mySection('settings'),
    extraOverrides: overrides,
  );
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settle(tester);
}

void main() {
  group('설정 목록', () {
    testWidgets('알림·화면 언어·계정·고객 지원·로그아웃 순서의 한 장이다', (tester) async {
      await _openSettings(tester);

      final List<double> ys =
          <String>[
                'my-notifications-entry',
                'my-language-button',
                'my-account-entry',
                'my-support-entry',
                'my-logout-button',
              ]
              .map((k) => tester.getCenter(find.byKey(ValueKey<String>(k))).dy)
              .toList();
      for (int i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]));
      }
      // 카드를 쌓던 예전 모양에는 알림 스위치가 목록에 바로 있었다.
      expect(find.byType(Switch), findsNothing);
    });

    for (final (String key, String section, String title)
        in <(String, String, String)>[
          ('my-notifications-entry', 'notifications', _ko.myNotifications),
          ('my-account-entry', 'account', _ko.myAccount),
          ('my-support-entry', 'support', _ko.mySupportTitle),
        ]) {
      testWidgets('$title 줄은 하위 화면을 열고, 뒤로 가면 목록이다', (tester) async {
        await _openSettings(tester);

        await _tapKey(tester, key);
        expect(currentLocation(tester), AppRoutes.mySection(section));
        // 하위 화면에는 내 정보/설정 토글이 없다.
        expect(
          find.byWidgetPredicate((w) => w is AppSegmentedToggle),
          findsNothing,
        );

        await tester.tap(find.byTooltip('뒤로'));
        await settle(tester);
        expect(currentLocation(tester), AppRoutes.mySection('settings'));
      });
    }
  });

  group('알림 설정', () {
    testWidgets('끌 수 있는 새 메시지와 항상 오는 알림을 함께 보인다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('notifications'),
      );

      expect(find.text(_ko.myNotifNewMessage), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text(_ko.myNotifConsultation), findsOneWidget);
      expect(find.text(_ko.myNotifReservation), findsOneWidget);
      expect(find.text(_ko.myNotifMemberUpdates), findsOneWidget);
      expect(find.text(_ko.myNotifAlwaysOn), findsNWidgets(3));
      expect(find.text(_ko.myNotifAlwaysOnNote), findsOneWidget);
    });

    testWidgets('저장이 실패하면 스위치를 되돌리고 토스트로 알린다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('notifications'),
        extraOverrides: <Override>[
          trainerSettingsRepositoryProvider.overrideWithValue(
            const _FailingRepository(),
          ),
        ],
      );

      final Finder toggle = find.byKey(
        const ValueKey<String>('my-notif-new-message'),
      );
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await settle(tester);

      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(find.text(_ko.mySettingsSaveFailed), findsOneWidget);
    });
  });

  group('계정', () {
    testWidgets('로그인 계정과 비밀번호 변경이 있다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('account'),
      );

      expect(find.text(_ko.myLoginAccount), findsOneWidget);
      expect(find.text('trainer@oncare.com'), findsOneWidget);
      expect(find.text(_ko.myChangePassword), findsOneWidget);
    });
  });

  group('프로필 수정', () {
    testWidgets('내 정보 본문은 읽기 전용이고, 수정은 따로 연다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('profile'),
      );

      // 본문에는 입력 칸이 없다.
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text(_ko.myEditProfile));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('edit'));
      expect(
        find.byKey(const ValueKey<String>('profile-phone')),
        findsOneWidget,
      );
    });

    testWidgets('고친 뒤 뒤로 가면 버릴지 묻고, 나가면 입력을 버린다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('edit'),
      );

      final Finder phone = find.byKey(const ValueKey<String>('profile-phone'));
      await tester.enterText(phone, '010-9999-8888');
      await tester.tap(find.byTooltip('뒤로'));
      await settle(tester);

      // 계속 수정하면 그대로 남는다.
      expect(find.text(_ko.myDiscardTitle), findsOneWidget);
      await tester.tap(find.text(_ko.myKeepEditing));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('edit'));
      expect(find.text('010-9999-8888'), findsOneWidget);

      await tester.tap(find.byTooltip('뒤로'));
      await settle(tester);
      await tester.tap(find.text(_ko.myDiscardAction));
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));

      await tester.tap(find.text(_ko.myEditProfile));
      await settle(tester);
      expect(find.text('010-9999-8888'), findsNothing);
    });

    testWidgets('고친 것이 없으면 묻지 않고 돌아간다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('edit'),
      );

      await tester.tap(find.byTooltip('뒤로'));
      await settle(tester);
      expect(find.text(_ko.myDiscardTitle), findsNothing);
      expect(currentLocation(tester), AppRoutes.mySection('profile'));
    });

    testWidgets('회원에게 보이는 정보라고 먼저 알린다', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('edit'),
      );

      expect(find.text(_ko.myEditVisibleTitle), findsOneWidget);
    });
  });

  group('넓은 화면', () {
    void useWideView(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('설정은 목록 옆에 고른 항목을 연다 — 처음에는 알림', (tester) async {
      useWideView(tester);
      await _openSettings(tester);

      final Finder list = find.byKey(
        const ValueKey<String>('my-support-entry'),
      );
      final Finder detail = find.byKey(
        const ValueKey<String>('my-notif-new-message'),
      );
      expect(detail, findsOneWidget);
      expect(
        tester.getCenter(detail).dx,
        greaterThan(tester.getCenter(list).dx),
      );

      await tester.tap(list);
      await settle(tester);
      expect(currentLocation(tester), AppRoutes.mySection('support'));
      // 목록은 그대로 있고 오른쪽만 바뀐다 — 뒤로 가기 대신 토글이 남는다.
      expect(
        find.byKey(const ValueKey<String>('my-logout-button')),
        findsOneWidget,
      );
      expect(find.text(_ko.mySupportFaq), findsOneWidget);
      expect(find.byTooltip('뒤로'), findsNothing);
    });

    testWidgets('내 정보는 프로필 요약 옆에 소속·자격을 둔다', (tester) async {
      useWideView(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('profile'),
      );

      final double name = tester.getCenter(find.text('trainer@oncare.com')).dx;
      final double gym = tester.getCenter(find.text(_ko.myGym)).dx;
      expect(gym, greaterThan(name));
      // 두 판이 한 줄에 선다 — 이번 달 지표가 프로필 아래로 밀리지 않는다.
      expect(
        tester.getTopLeft(find.text(_ko.myStatClients)).dy,
        lessThan(tester.getCenter(find.text('trainer@oncare.com')).dy),
      );
    });
  });
}
