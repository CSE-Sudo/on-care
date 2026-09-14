/// 내 상담 요청 화면의 소제목과 취소 확인창의 색 계약 (#1429).
///
/// 카드의 `취소` 는 파괴적 색인데 확인창의 확정 `취소` 만 기본 색이면, 되돌릴
/// 수 없는 쪽과 요청을 그대로 두는 쪽이 같은 색으로 보인다. 확정 버튼은 카드와
/// 같은 파괴적 토큰을, `유지` 는 중립 색을 쓴다.
///
/// `지난 요청` 소제목은 두지 않는다 — 완료·취소는 카드가 상태로 말한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_history_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/consultation_request_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../support/consultation_test_support.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

ConsultationRequest _pending() => ConsultationRequest(
  id: 'request-cancel',
  trainerId: 'trainer-cancel',
  trainerName: '김상담',
  trainerRole: '전담 트레이너',
  exerciseGoal: ExerciseGoal.weightLoss,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  preferredDate: DateTime(2026, 7, 28),
  preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 14, minute: 0)),
  message: null,
  status: ConsultationStatus.pending,
  createdAt: DateTime(2026, 7, 26),
);

void main() {
  late ConsultationRequestController controller;

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    controller = newTestConsultationController();
    expect(await seedPending(controller, _pending()), isTrue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          consultationRequestControllerProvider.overrideWith((_) => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ConsultationHistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 확인창 안의 버튼. 카드의 취소 버튼은 확인창이 덮고 있어도 트리에
  /// 남으므로, 다이얼로그 안으로 범위를 좁혀 찾는다.
  Finder dialogButton(String label) => find.descendant(
    of: find.byType(AppDialog),
    matching: find.widgetWithText(AppButton, label),
  );

  Future<void> openConfirm(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('cancel-consultation-request-cancel')),
    );
    await tester.pumpAndSettle();
    expect(find.text('상담 요청을 취소할까요?'), findsOneWidget);
  }

  testWidgets('확정 취소는 붉은색, 유지는 중립색이다', (WidgetTester tester) async {
    await pumpHistory(tester);
    await openConfirm(tester);

    // 카드의 취소는 파괴적 글자 버튼이다.
    expect(
      tester
          .widget<AppButton>(
            find.byKey(
              const ValueKey<String>('cancel-consultation-request-cancel'),
            ),
          )
          .variant,
      AppButtonVariant.destructiveText,
    );
    // 확정은 같은 파괴적 토큰의 채움, 유지는 중립 버튼이다.
    expect(
      tester.widget<AppButton>(dialogButton('취소')).variant,
      AppButtonVariant.destructive,
    );
    expect(
      tester.widget<AppButton>(dialogButton('유지')).variant,
      AppButtonVariant.secondary,
    );
  });

  testWidgets('유지를 누르면 요청 상태가 그대로다', (WidgetTester tester) async {
    await pumpHistory(tester);
    await openConfirm(tester);

    await tester.tap(dialogButton('유지'));
    await tester.pumpAndSettle();

    expect(controller.state.single.status, ConsultationStatus.pending);
  });

  testWidgets('지난 요청 소제목은 표시되지 않는다', (WidgetTester tester) async {
    await pumpHistory(tester);

    // 요청 하나를 취소해 `지난 요청` 쪽으로 옮긴다.
    await openConfirm(tester);
    await tester.tap(dialogButton('취소'));
    await tester.pumpAndSettle();

    expect(controller.state.single.status, isNot(ConsultationStatus.pending));
    expect(find.text('지난 요청'), findsNothing);
    expect(find.byType(ConsultationRequestCard), findsOneWidget);
  });

  testWidgets('확정하면 요청이 취소 상태가 된다', (WidgetTester tester) async {
    await pumpHistory(tester);
    await openConfirm(tester);

    await tester.tap(dialogButton('취소'));
    await tester.pumpAndSettle();

    expect(controller.state.single.status, isNot(ConsultationStatus.pending));
  });
}
