/// 기간을 바꾸면 AI 맞춤 조언도 바뀐다. (#1017)
///
/// 예전에는 조언이 오늘 기준 하나뿐이라, 이번 주를 보고 있는데 "오늘 점심이
/// 짰어요" 를 읽게 됐다. 그래프만 갈아 끼우고 조언이 남으면 지금 화면과 무관한
/// 말이 되어 신뢰를 잃는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

/// 기간 조언을 붙잡아 두거나 실패시키는 대역. 나머지 동작은 그대로 쓴다.
class _AdviceRepository extends FakeDietRepository {
  _AdviceRepository({
    this.pending = const <String>{},
    this.failing = const <String>{},
  });

  final Set<String> pending;
  final Set<String> failing;

  /// 기간별 요청 횟수 — 다시 시도가 정말 그 기간을 다시 부르는지 본다.
  final Map<String, int> calls = <String, int>{};

  @override
  Future<String> fetchAdvice(String period) {
    calls[period] = (calls[period] ?? 0) + 1;
    if (pending.contains(period)) return Completer<String>().future;
    if (failing.contains(period)) {
      return Future<String>.error(StateError('advice unavailable'));
    }
    return super.fetchAdvice(period);
  }
}

Widget _app([DietRepository? repo]) => ProviderScope(
  overrides: <Override>[
    dietRepositoryProvider.overrideWithValue(repo ?? FakeDietRepository()),
    accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DietRecordPage(),
  ),
);

void main() {
  testWidgets('오늘 / 이번 주 / 전체가 각각 다른 조언을 보여 준다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    String advice() {
      final Finder card = find.byType(PeriodAiAdviceCard);
      return tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .map((Text t) => t.data ?? '')
          .join(' ');
    }

    final String today = advice();
    expect(today, isNotEmpty);

    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
    final String week = advice();
    expect(week, isNot(today), reason: '이번 주인데 오늘 조언이 그대로다');
    expect(week, contains('이번 주'));

    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();
    final String all = advice();
    expect(all, isNot(week), reason: '전체인데 이번 주 조언이 그대로다');
  });

  testWidgets('이번 주 조언을 기다리는 동안 오늘 조언으로 되돌아가지 않는다 (#1574)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _AdviceRepository repo = _AdviceRepository(pending: <String>{'week'});
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final String todayAdvice = _shellText(tester);
    expect(todayAdvice, isNotEmpty);

    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('ai-advice-loading')), findsOne);
    // 오늘 조언도, 하루 응답이 들고 온 문장도 이 자리를 대신 채우지 않는다.
    expect(_shellText(tester), isNot(contains(todayAdvice)));
  });

  testWidgets('실패한 기간은 실패했다고 말하고 다시 시도할 길을 준다 (#1574)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _AdviceRepository repo = _AdviceRepository(failing: <String>{'all'});
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    final String todayAdvice = _shellText(tester);

    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('ai-advice-error')), findsOne);
    expect(_shellText(tester), isNot(contains(todayAdvice)));

    final int before = repo.calls['all']!;
    await tester.tap(find.byKey(const ValueKey<String>('ai-advice-retry')));
    await tester.pumpAndSettle();
    expect(repo.calls['all'], before + 1);
  });
}

/// 조언 카드가 지금 보여 주는 글자 전부 — 로딩·실패 상태도 이 그릇 안에 있다.
String _shellText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AiAdviceShell),
        matching: find.byType(Text),
      ),
    )
    .map((Text t) => t.data ?? '')
    .join(' ');
