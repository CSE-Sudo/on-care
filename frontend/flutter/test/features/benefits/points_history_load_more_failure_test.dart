/// 포인트 내역 `더 보기` 가 실패하면 알리고 다시 시도하게 한다 — #2641.
///
/// 예전에는 이어 받기가 실패해도 오류 표시를 내역이 비어 있을 때만 그려, 버튼의
/// 로딩이 사라질 뿐 아무 말이 없었다. 눌렀는데 반응이 없거나 더 앞의 내역이
/// 원래 없는 것처럼 보였다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/points_history.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/pages/points_history_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';

const Key _more = Key('pointsHistoryMore');

PointsHistoryEntry _entry(String id, int delta, DateTime day) =>
    PointsHistoryEntry(
      id: id,
      kind: delta > 0 ? PointsEntryKind.earn : PointsEntryKind.spend,
      reason: 'diet_entry',
      delta: delta,
      day: day,
    );

FakeBenefitsRepository _repo({
  int olderFailures = 1,
  String? olderNextBefore,
}) => FakeBenefitsRepository()
  ..history = PointsHistory(
    balance: 1230,
    entries: <PointsHistoryEntry>[_entry('a', 50, DateTime(2026, 9, 22))],
    nextBefore: '2026-09-22',
  )
  ..olderHistory = PointsHistory(
    balance: 1230,
    entries: <PointsHistoryEntry>[_entry('b', -30, DateTime(2026, 9, 20))],
    nextBefore: olderNextBefore,
  )
  ..olderFailures = olderFailures;

Future<AppLocalizations> _pump(
  WidgetTester tester,
  FakeBenefitsRepository repo, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[benefitsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PointsHistoryPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(PointsHistoryPage)));
}

String _buttonLabel(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(_more)).label;

Future<void> _tapMore(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_more));
  await tester.tap(find.byKey(_more));
  await tester.pump();
  await tester.pump();
}

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastErrorVisible);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('더 보기가 실패하면 토스트로 알린다', (WidgetTester tester) async {
    final FakeBenefitsRepository repo = _repo();
    final AppLocalizations l = await _pump(tester, repo);

    await _tapMore(tester);

    expect(find.text(l.myPointsHistoryMoreFailed), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('실패하면 버튼이 같은 자리에서 다시 시도로 바뀌고 받아 둔 내역은 남는다', (
    WidgetTester tester,
  ) async {
    final FakeBenefitsRepository repo = _repo();
    final AppLocalizations l = await _pump(tester, repo);
    expect(_buttonLabel(tester), l.myPointsHistoryMore);

    await _tapMore(tester);
    await _drainToast(tester);

    expect(find.byKey(_more), findsOneWidget);
    expect(_buttonLabel(tester), l.actionRetry);
    expect(
      find.byKey(const ValueKey<String>('points-entry-a')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('points-entry-b')), findsNothing);
    expect(find.byKey(const Key('pointsHistoryBalance')), findsOneWidget);
    // 첫 쪽 실패 화면(카드 오류 상태)은 나오지 않는다.
    expect(find.text(l.myPointsHistoryLoadFailed), findsNothing);
  });

  testWidgets('다시 시도는 같은 커서로 이어 받고, 성공하면 내역을 붙인다', (WidgetTester tester) async {
    final FakeBenefitsRepository repo = _repo();
    final AppLocalizations l = await _pump(tester, repo);

    await _tapMore(tester);
    await _drainToast(tester);
    await _tapMore(tester);
    await tester.pumpAndSettle();

    expect(repo.historyRequests, <String?>[null, '2026-09-22', '2026-09-22']);
    expect(
      find.byKey(const ValueKey<String>('points-entry-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('points-entry-b')),
      findsOneWidget,
    );
    // 더 받을 것이 없으면 버튼이 사라진다.
    expect(find.byKey(_more), findsNothing);
    expect(find.text(l.myPointsHistoryMoreFailed), findsNothing);
  });

  testWidgets('다시 시도가 성공하고 더 남아 있으면 버튼이 더 보기로 돌아온다', (
    WidgetTester tester,
  ) async {
    final FakeBenefitsRepository repo = _repo(olderNextBefore: '2026-09-20');
    final AppLocalizations l = await _pump(tester, repo);

    await _tapMore(tester);
    await _drainToast(tester);
    expect(_buttonLabel(tester), l.actionRetry);

    await _tapMore(tester);
    await tester.pumpAndSettle();

    expect(_buttonLabel(tester), l.myPointsHistoryMore);
  });

  testWidgets('다시 시도가 또 실패하면 다시 알리고 다시 시도로 남는다', (WidgetTester tester) async {
    final FakeBenefitsRepository repo = _repo(olderFailures: 2);
    final AppLocalizations l = await _pump(tester, repo);

    await _tapMore(tester);
    await _drainToast(tester);
    await _tapMore(tester);

    expect(find.text(l.myPointsHistoryMoreFailed), findsOneWidget);
    await _drainToast(tester);
    expect(_buttonLabel(tester), l.actionRetry);
    expect(
      find.byKey(const ValueKey<String>('points-entry-a')),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면에서도 실패 문구와 다시 시도가 영어다', (WidgetTester tester) async {
    final FakeBenefitsRepository repo = _repo();
    final AppLocalizations l = await _pump(
      tester,
      repo,
      locale: const Locale('en'),
    );

    await _tapMore(tester);
    expect(find.text("Couldn't load more. Please try again"), findsOneWidget);
    await _drainToast(tester);
    expect(_buttonLabel(tester), l.actionRetry);
  });

  testWidgets('첫 쪽이 실패하면 지금처럼 카드 오류 상태를 그리고 토스트는 없다', (
    WidgetTester tester,
  ) async {
    final FakeBenefitsRepository repo = _FailingFirstPageRepo();
    final AppLocalizations l = await _pump(tester, repo);

    expect(find.text(l.myPointsHistoryLoadFailed), findsOneWidget);
    expect(find.text(l.myPointsHistoryMoreFailed), findsNothing);
    expect(find.byKey(_more), findsNothing);
  });
}

/// 첫 쪽부터 실패하는 저장소.
class _FailingFirstPageRepo extends FakeBenefitsRepository {
  @override
  Future<PointsHistory> fetchPointsHistory({String? before}) async {
    throw StateError('네트워크 없음');
  }
}
