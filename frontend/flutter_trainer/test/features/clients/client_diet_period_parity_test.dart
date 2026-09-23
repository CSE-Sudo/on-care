/// 기간 영양 그래프가 회원 앱 식단 탭과 **같은 기준**인지 (#2156).
///
/// 회원 앱이 바꾼 것(#1879, #1986, #2009, #1981, #1984)을 트레이너 화면이 따라가지
/// 않아, 같은 회원의 같은 기간을 두 앱이 다른 숫자로 말했다 — 목표선은 회원이
/// 정한 값이 아니라 2,000kcal 였고, `하루 평균` 은 30일 창으로 셌다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

ClientDietPeriod _period(ClientPeriodKey key) {
  final ClientDateRange range = clientRangeFor(key.period, key.day);
  return ClientDietPeriod(
    range: range,
    days: <ClientDietDay>[
      for (final DateTime d in clientRangeDates(range))
        ClientDietDay(
          date: d,
          calories: 1700,
          carbsG: 220,
          proteinG: 80,
          fatG: 50,
        ),
    ],
  );
}

Widget _app(ClientPeriod period, {MemberHealthProfile? profile}) =>
    ProviderScope(
      overrides: <Override>[
        clientDietPeriodProvider.overrideWith((ref, key) async => _period(key)),
        memberHealthProfileProvider.overrideWith(
          (ref, clientId) async =>
              profile ??
              MemberHealthProfile(memberId: clientId, memberName: '테스트회원'),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ClientDietPeriodCard(clientId: 'c1', period: period),
          ),
        ),
      ),
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    ClientPeriod period, {
    MemberHealthProfile? profile,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(period, profile: profile));
    await tester.pumpAndSettle();
  }

  testWidgets('목표선은 회원 프로필의 하루 칼로리다', (tester) async {
    // 1,700kcal 는 기본 목표(2,000) 안쪽이지만 회원이 정한 1,600 은 넘는다 —
    // 회원 폰에서 빨간 숫자가 트레이너 화면에서도 빨개야 한다.
    await pump(
      tester,
      ClientPeriod.month,
      profile: const MemberHealthProfile(
        memberId: 'c1',
        memberName: '테스트회원',
        dailyCalories: 1600,
      ),
    );

    expect(find.textContaining('/ 1,600 kcal', findRichText: true), findsOne);
    expect(
      find.textContaining('/ 2,000 kcal', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('프로필에 목표가 없으면 회원 앱 기본값 2,000kcal 이다', (tester) async {
    await pump(tester, ClientPeriod.week);

    expect(find.textContaining('/ 2,000 kcal', findRichText: true), findsOne);
  });

  testWidgets('`전체` 는 한 화면에 24일 — 회원 앱과 같은 평균 구간', (tester) async {
    await pump(tester, ClientPeriod.month);

    expect(
      tester
          .widget<PeriodScrollChart>(find.byType(PeriodScrollChart))
          .daysPerScreen,
      24,
    );
  });

  testWidgets('날짜 기간은 카드 안에, 고른 날은 월·일만 적는다', (tester) async {
    await pump(tester, ClientPeriod.month);

    final Finder card = find.byKey(
      const ValueKey<String>('client-diet-period-card'),
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(
          const ValueKey<String>('client-diet-period-range'),
        ),
      ),
      findsOneWidget,
    );

    // 오늘(마지막 칸)을 고른다 — 그래프는 오늘 쪽 끝에서 시작한다.
    final ClientDateRange range = clientRangeFor(
      ClientPeriod.month,
      todayKst(),
    );
    final List<DateTime> dates = clientRangeDates(range).toList();
    await tester.tap(find.byKey(Key('client-diet-bar-${dates.length - 1}')));
    await tester.pumpAndSettle();

    final String md = DateFormat.Md('ko').format(dates.last);
    expect(find.text(md), findsOneWidget);
    expect(find.text(DateFormat.yMd('ko').format(dates.last)), findsNothing);
    // 날을 고르면 날짜 기간은 빠진다 — 머리 문구가 이미 그날을 말한다.
    expect(
      find.byKey(const ValueKey<String>('client-diet-period-range')),
      findsNothing,
    );
  });

  testWidgets('기간을 바꾸면 고른 날이 풀린다 (회원 앱 #1984)', (tester) async {
    await pump(tester, ClientPeriod.month);
    final int last =
        clientRangeDates(
          clientRangeFor(ClientPeriod.month, todayKst()),
        ).length -
        1;
    await tester.tap(find.byKey(Key('client-diet-bar-$last')));
    await tester.pumpAndSettle();

    // 같은 State 가 이번 주(7칸)로 넘어간다 — 84칸의 인덱스가 남아 있으면
    // `values[picked]` 가 범위를 벗어난다.
    await tester.pumpWidget(_app(ClientPeriod.week));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('하루 평균'), findsOneWidget);
  });
}
