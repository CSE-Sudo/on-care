import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/points_history.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/pages/points_history_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import 'fake_benefits_repository.dart';

PointsHistoryEntry _entry(
  String id,
  PointsEntryKind kind,
  String reason,
  int delta,
  DateTime day, {
  int count = 1,
}) => PointsHistoryEntry(
  id: id,
  kind: kind,
  reason: reason,
  delta: delta,
  day: day,
  count: count,
);

/// 포인트 내역 — 날짜로 묶고, 무엇으로 얼마가 움직였는지 적는다. (#2146)
void main() {
  testWidgets('사유·부호를 적고 더 보기로 앞 날짜를 이어 붙인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final DateTime today = DateTime(2026, 9, 22);
    final FakeBenefitsRepository repo = FakeBenefitsRepository()
      ..history = PointsHistory(
        balance: 1230,
        entries: <PointsHistoryEntry>[
          _entry('a', PointsEntryKind.spend, 'ai_chat', -150, today, count: 3),
          _entry('b', PointsEntryKind.revoke, 'diet_entry', -50, today),
          _entry('c', PointsEntryKind.earn, 'diet_entry', 50, today),
        ],
        nextBefore: '2026-09-22',
      )
      ..olderHistory = PointsHistory(
        balance: 1230,
        entries: <PointsHistoryEntry>[
          _entry(
            'd',
            PointsEntryKind.spend,
            'coupon_locker_month',
            -7000,
            DateTime(2026, 9, 20),
          ),
        ],
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PointsHistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 코치 대화 3회'), findsOneWidget);
    expect(find.text('−150P'), findsOneWidget);
    expect(find.text('식단 기록 · 기록 삭제로 회수'), findsOneWidget);
    expect(find.text('+50P'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pointsHistoryMore')));
    await tester.pumpAndSettle();
    expect(find.text('개인 락커 쿠폰'), findsOneWidget);
    expect(find.text('−7,000P'), findsOneWidget);
    expect(find.byKey(const Key('pointsHistoryMore')), findsNothing);
  });
}
