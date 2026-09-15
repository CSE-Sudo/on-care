/// 상담 요청 완료 화면의 완료 표시 원(#1781).
///
/// 회원앱 아이콘은 배경을 두지 않지만, 이 원은 아이콘 칸이 아니라 요청이
/// 끝났음을 알리는 완료 표시라 예외로 옅은 브랜드 원(지름 80)을 그대로 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_complete_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

ConsultationRequest _request() => ConsultationRequest(
  id: 'request-complete',
  trainerId: 'trainer-complete',
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
  testWidgets('완료 표시는 옅은 브랜드 원 위의 체크다', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConsultationCompletePage(request: _request()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder check = find.byIcon(Icons.check_rounded);
    expect(check, findsOneWidget);

    final Finder badge = find
        .ancestor(of: check, matching: find.byType(Container))
        .first;
    final BoxDecoration decoration =
        tester.widget<Container>(badge).decoration! as BoxDecoration;
    expect(decoration.color, OnCareBrand.member.surface);
    expect(decoration.shape, BoxShape.circle);
    expect(tester.getSize(badge), const Size.square(80));
  });
}
