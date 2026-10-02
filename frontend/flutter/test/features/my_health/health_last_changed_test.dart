/// MY 건강 목표의 `마지막 변경` 은 구획 제목 줄 끝에 구획마다 따로 선다. (#2942)
///
/// 목표 칩과 건강상태·주의사항은 같은 `conditions` 칸이지만 기록은 따로다 —
/// 주의사항만 고친 저장이 칩 줄을 움직이지 않는다. 트레이너가 고친 주의사항은
/// 알림이 오지 않아 회원은 이 줄로 안다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

Future<void> _open(WidgetTester tester, UserProfile profile) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(profile: profile),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthGoalsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inHeader(String title, Key key) => find.descendant(
  of: find.ancestor(
    of: find.text(title),
    matching: find.byType(AppSectionHeader),
  ),
  matching: find.byKey(key),
);

void main() {
  testWidgets('목표 칩과 주의사항의 마지막 변경이 각 구획 제목 줄 끝에 따로 선다', (tester) async {
    await _open(
      tester,
      UserProfile(
        id: 'user-last-changed',
        name: '기록',
        email: 'changed@oncare.com',
        conditions: '체중 감량, 왼쪽 무릎 수술 이력',
        focusChangedBy: UserProfile.focusChangedByMember,
        focusChangedAt: DateTime(2026, 9, 30, 10),
        notesChangedBy: UserProfile.focusChangedByTrainer,
        notesChangedAt: DateTime(2026, 10, 2, 9),
      ),
    );

    final Finder focus = _inHeader(
      '주로 관리하고 싶은 항목',
      const Key('goalFocusLastChanged'),
    );
    final Finder notes = _inHeader(
      '건강상태·주의사항',
      const Key('goalConditionsLastChanged'),
    );
    expect(focus, findsOneWidget);
    expect(notes, findsOneWidget);
    expect(tester.widget<Text>(focus).data, contains('9월 30일'));
    expect(tester.widget<Text>(notes).data, contains('트레이너'));
    expect(tester.widget<Text>(notes).data, contains('10월 2일'));
  });

  testWidgets('바꾼 적이 없으면 제목 줄 끝이 비어 있다', (tester) async {
    await _open(
      tester,
      const UserProfile(
        id: 'user-never-changed',
        name: '처음',
        email: 'never@oncare.com',
        conditions: '체중 감량, 허리 디스크',
      ),
    );

    expect(find.byKey(const Key('goalFocusLastChanged')), findsNothing);
    expect(find.byKey(const Key('goalConditionsLastChanged')), findsNothing);
  });

  test('응답의 notes_changed_* 를 목표 칩 기록과 따로 읽는다', () {
    final UserProfile profile = UserProfile.fromJson(<String, Object?>{
      'id': 'u1',
      'name': '지수',
      'email': 'jisu@oncare.com',
      'conditions': '재활, 무릎 통증 주의',
      'focus_changed_by': null,
      'notes_changed_by': 'trainer',
      'notes_changed_at': '2026-10-02T00:00:00Z',
    });

    expect(profile.focusChangedBy, isNull);
    expect(profile.notesChangedBy, UserProfile.focusChangedByTrainer);
    expect(profile.notesChangedAt, isNotNull);
  });
}
