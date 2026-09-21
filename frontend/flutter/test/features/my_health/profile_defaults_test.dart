/// 내 프로필의 기본값 (#1140).
///
/// 고르지 않은 채로 두면 "이 회원이 무엇을 골랐는지" 와 "아직 안 골랐는지" 가
/// 화면에서 같아 보인다. 데모 회원(김민수)은 트레이너 앱이 보여 주는 사람과
/// 같은 사람이라 성별·목표도 같은 값이어야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<AppLocalizations> _openProfile(
  WidgetTester tester, {
  UserProfile? profile,
  bool editing = true,
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(
          profile == null
              ? MockAccountRepository()
              : MockAccountRepository(profile: profile),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProfileSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (editing) {
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
  }
  return AppLocalizations.of(tester.element(find.byType(ProfileSettingsPage)));
}

void main() {
  testWidgets('보기로 열고 연필로 수정한 뒤 저장하면 갱신된 보기로 돌아온다', (tester) async {
    final l = await _openProfile(tester, editing: false);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l.mySave), findsNothing);
    expect(find.text('김민수'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileEditButton')), findsNothing);
    final field = find.byKey(const ValueKey<String>('my-profile-name'));
    expect(
      Theme.of(
        tester.element(
          find.descendant(of: field, matching: find.byType(TextField)),
        ),
      ).inputDecorationTheme.fillColor,
      OnCareColors.surfaceInput,
    );
    await tester.enterText(field, '새이름');
    await tester.tap(find.text(l.mySave));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSettingsPage), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l.mySave), findsNothing);
    expect(find.text('새이름'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      '새이름',
    );
  });

  testWidgets('수정 전후 항목 위치를 유지하고 취소하면 저장 없이 보기로 돌아온다', (tester) async {
    final l = await _openProfile(tester, editing: false);
    final labels = <String>[
      l.myFieldName,
      l.myFieldEmail,
      l.myFieldPhone,
      l.myFieldBirth,
      l.myFieldGender,
      l.myFieldHeight,
      l.myFieldWeight,
    ];
    final positions = <Offset>[
      for (final label in labels) tester.getTopLeft(find.text(label)),
    ];
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
    for (var i = 0; i < labels.length; i++) {
      expect(tester.getTopLeft(find.text(labels[i])), positions[i]);
    }
    final name = find.byKey(const ValueKey<String>('my-profile-name'));
    await tester.enterText(name, '취소할이름');
    await tester.tap(find.text(l.myCancel));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSettingsPage), findsOneWidget);
    expect(find.text('김민수'), findsOneWidget);
    expect(find.text('취소할이름'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: name, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      '김민수',
    );
  });

  testWidgets('데모 회원은 성별이 이미 채워져 있다', (WidgetTester tester) async {
    final AppLocalizations l = await _openProfile(tester);

    expect(find.text(l.onboardGenderMale), findsOneWidget);
    // 자유 입력 운동 목표는 `건강 목표` 화면으로 옮겼다(#1471) — 내 프로필
    // 수정에는 기본 신체·계정 정보만 남는다.
    expect(find.text('혈압 관리 · 체중 감량'), findsNothing);
  });

  testWidgets('성별을 고른 적 없는 회원도 빈 칸으로 두지 않는다', (WidgetTester tester) async {
    final AppLocalizations l = await _openProfile(
      tester,
      profile: const UserProfile(
        id: 'no-gender',
        name: '성별없음',
        email: 'none@oncare.com',
      ),
    );

    expect(find.text(l.onboardGenderMale), findsOneWidget);
  });
}
