/// 트레이너 계정 탈퇴. (#505)
///
/// 되돌릴 수 없는 동작이라 확인 절차가 형식만 남으면 안 된다 — 담당 회원 연결과
/// 예약이 함께 사라지고 회원에게는 알림이 간다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 문구 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();

/// 탈퇴 호출을 기록하는 페이크.
class _FakeAccountRepository implements TrainerAccountRepository {
  _FakeAccountRepository({this.supportsDeletion = true, this.fails = false});

  @override
  final bool supportsDeletion;
  final bool fails;
  int deleteCalls = 0;

  @override
  bool get supportsPasswordChange => true;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> deleteAccount() async {
    if (fails) throw const ServerError(message: '지금은 탈퇴할 수 없어요');
    deleteCalls++;
  }
}

/// 탈퇴는 설정이 아니라 그 아래 고객 지원 화면에 있다(#2227) — 약관·개인정보
/// 다음, 계정을 정리하는 줄로 묶인다.
Future<_FakeAccountRepository> _pumpSettings(
  WidgetTester tester, {
  bool supportsDeletion = true,
  bool fails = false,
}) async {
  final repo = _FakeAccountRepository(
    supportsDeletion: supportsDeletion,
    fails: fails,
  );
  await pumpTrainerApp(
    tester,
    token: 'demo-token',
    at: '${AppRoutes.my}?t=support',
    extraOverrides: <Override>[
      trainerAccountRepositoryProvider.overrideWithValue(repo),
    ],
  );
  return repo;
}

/// 화면이 길어 탈퇴 행이 뷰포트 밖일 수 있다 — 탭 전에 보이게 한다.
Future<void> _tapDelete(WidgetTester tester) async {
  final button = find.byKey(const ValueKey<String>('delete-account'));
  await tester.ensureVisible(button);
  await settle(tester);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  testWidgets('고객 지원에 탈퇴 진입점이 있다', (tester) async {
    await _pumpSettings(tester);

    expect(find.text(_ko.myDeleteAccount), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('delete-account')),
      findsOneWidget,
    );
  });

  testWidgets('지울 계정이 없는 빌드에서는 비활성이고 사유를 보여 준다', (tester) async {
    await _pumpSettings(tester, supportsDeletion: false);

    expect(find.text(_ko.myDeleteDemo), findsOneWidget);
    final button = tester.widget<AppButton>(
      find.byKey(const ValueKey<String>('delete-account')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('이름을 정확히 입력해야 탈퇴가 진행된다', (tester) async {
    final repo = await _pumpSettings(tester);

    await _tapDelete(tester);
    expect(find.text(_ko.myDeleteTitle), findsOneWidget);

    // 이름이 맞기 전에는 눌리지 않는다 — 예/아니오만으로는 실수를 못 거른다.
    final submit = find.byKey(const ValueKey<String>('delete-account-submit'));
    expect(tester.widget<AppButton>(submit).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey<String>('delete-account-confirm')),
      '틀린 이름',
    );
    await settle(tester);
    expect(tester.widget<AppButton>(submit).onPressed, isNull);
    expect(repo.deleteCalls, 0);

    await tester.enterText(
      find.byKey(const ValueKey<String>('delete-account-confirm')),
      seedTrainerProfile.name,
    );
    await settle(tester);
    expect(tester.widget<AppButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await settle(tester);
    expect(repo.deleteCalls, 1);
  });

  testWidgets('취소하면 아무 일도 일어나지 않는다', (tester) async {
    final repo = await _pumpSettings(tester);

    await _tapDelete(tester);
    await tester.tap(find.text(_ko.actionCancel));
    await settle(tester);

    expect(repo.deleteCalls, 0);
  });

  testWidgets('실패하면 사유를 알린다', (tester) async {
    await _pumpSettings(tester, fails: true);

    await _tapDelete(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('delete-account-confirm')),
      seedTrainerProfile.name,
    );
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('delete-account-submit')),
    );
    await settle(tester);

    expect(find.text('지금은 탈퇴할 수 없어요'), findsOneWidget);
  });
}
