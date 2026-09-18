/// `운동 현황` 의 `전체` 카드가 보이는 구간에서 **유형별로 얼마나 했는지**를
/// 스스로 말한다 (#2061).
///
/// 막대가 유산소·근력·스트레칭 세 색으로 쌓이는데, 고른 주가 없으면 카드
/// 안에 그 색이 무엇인지도, 유형별로 얼마였는지도 없었다. 식단 탭 `전체` 는
/// 머리 숫자(하루 평균) 옆에 탄단지 하루 평균을 늘 붙여 두고 그 세 줄이 막대
/// 색의 범례를 겸한다(#1121, #2056). 운동도 같게 — 머리 숫자가 보이는 구간의
/// 주 평균이므로 그 옆에 유형별 **주 평균**을 같은 색 이름으로 적는다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

/// 실제 서체를 싣는다. 테스트 기본 서체는 모든 글자를 정사각형으로 그려 숫자·
/// 점·공백의 폭이 부풀려진다 — 폭에 따라 줄어드는지를 보려면 실제 폭이어야
/// 한다.
Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('Pretendard');
  for (final String w in <String>['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File(
        'assets/fonts/Pretendard-$w.otf',
      ).readAsBytes().then((Uint8List b) => ByteData.view(b.buffer)),
    );
  }
  await loader.load();
}

Finder _average() => find.byKey(const Key('exercise-all-average'));

Finder _chart() => find.byWidgetPredicate(
  (Widget w) => w.runtimeType.toString() == '_WeeklyBurnChart',
);

Finder _bars() => find.byWidgetPredicate(
  (Widget w) => w.runtimeType.toString() == '_BurnBar',
);

Future<void> _openAllPeriod(WidgetTester tester) async {
  useFixedKstDate();
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        memberCoachRepositoryProvider.overrideWithValue(
          MockMemberCoachRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ExercisePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey<String>('exercise-period-toggle')),
      matching: find.text('전체'),
    ),
  );
  await tester.pumpAndSettle();
}

/// 평균 칸에 적힌 유형 줄 — `(이름, 그 이름의 색, 줄 전체 글)`. 날짜 줄은
/// 리치 텍스트가 아니라 빠진다.
List<(String, Color?, String)> _lines(WidgetTester tester) {
  final List<(String, Color?, String)> out = <(String, Color?, String)>[];
  for (final Text t in tester.widgetList<Text>(
    find.descendant(of: _average(), matching: find.byType(Text)),
  )) {
    final InlineSpan? root = t.textSpan;
    if (root is! TextSpan || root.children == null) continue;
    final TextSpan name = root.children!.first as TextSpan;
    out.add((name.text!, name.style?.color, root.toPlainText()));
  }
  return out;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('고른 주가 없으면 날짜 아래에 유형별 주 평균이 막대 색 이름으로 적힌다', (
    WidgetTester tester,
  ) async {
    await _openAllPeriod(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );

    expect(_average(), findsOneWidget, reason: '전체 카드에 유형별 평균이 없다');
    final List<(String, Color?, String)> lines = _lines(tester);

    // 막대가 쌓이는 순서(진하기 순)대로, 막대와 **같은 색**으로 — 이 세 줄이
    // 막대 색의 범례를 겸한다.
    expect(
      lines.take(3).map(((String, Color?, String) e) => (e.$1, e.$2)).toList(),
      <(String, Color?)>[
        for (final ExerciseLoadKind k in ExerciseLoadKind.values)
          // 회원 앱 브랜드가 기본값이다 — 화면이 넘기는 것과 같다.
          (kindLabel(l, k), kindColor(k)),
      ],
    );
    // 각 줄에 그 유형의 원래 단위로 값이 붙는다 — 이름만 있는 범례가 아니다.
    expect(lines[0].$3, matches(RegExp(r'^유산소 \d+분$')));
    expect(lines[1].$3, matches(RegExp(r'^근력 \d+세트$')));
    expect(lines[2].$3, matches(RegExp(r'^스트레칭 \d+분$')));
    // `기타` 도 적는다 — 머리 숫자(소모 칼로리)가 기타 운동의 칼로리까지
    // 세므로 빠지면 숫자의 일부가 설명되지 않는다. 고른 주의 내역과 같이
    // 유형 색이 아니라 회색이다. 이 대역은 보이는 구간에 기타가 있다.
    expect(lines.length, 4);
    expect(lines[3].$1, l.exTypeOtherChip);
    expect(lines[3].$2, OnCareColors.textSecondary);
    expect(lines[3].$3, matches(RegExp(r'^기타 \d+분$')));

    // 자리 — 날짜 기간 바로 아래, 그래프보다 위.
    final Rect range = tester.getRect(
      find.byKey(const Key('exercise-all-range')),
    );
    expect(tester.getRect(_average()).top, lessThanOrEqualTo(range.top));
    expect(
      tester.getRect(_average()).bottom,
      lessThanOrEqualTo(tester.getRect(_chart()).top),
    );
  });

  testWidgets('평균 칸은 읽을 만한 크기로 들어간다', (WidgetTester tester) async {
    // 머리줄 높이(72)는 날짜 + 세 줄의 실측값이다. 세 줄이면 제 크기 그대로,
    // `기타` 까지 네 줄이면 고른 주의 내역처럼 목록 전체가 한 번에 조금
    // 줄어든다(약 0.8 배). 머리줄이 44 이던 때는 세 줄만으로도 0.61 배(글자
    // 7px 대)였다 — 그 회귀를 막는다.
    await _openAllPeriod(tester);
    final double scale =
        tester.getRect(_average()).height / tester.getSize(_average()).height;
    expect(scale, greaterThanOrEqualTo(0.75), reason: '평균 칸이 너무 작게 줄었다');
  });

  testWidgets('평균은 보이는 구간을 따라간다 — 머리 숫자와 같은 규칙', (WidgetTester tester) async {
    await _openAllPeriod(tester);
    final List<String> before = <String>[
      for (final (_, _, String text) in _lines(tester)) text,
    ];

    await tester.drag(
      find.descendant(of: _chart(), matching: find.byType(Scrollable)).first,
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();

    expect(
      <String>[for (final (_, _, String text) in _lines(tester)) text],
      isNot(before),
      reason: '그래프를 밀었는데 유형별 평균이 그대로다',
    );
  });

  testWidgets('주를 고르면 날짜와 평균 대신 그 주의 값이 뜨고, 그래프는 그대로다', (
    WidgetTester tester,
  ) async {
    await _openAllPeriod(tester);
    final Rect chart = tester.getRect(_chart());

    await tester.tap(_bars().last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_average(), findsNothing);
    expect(find.byKey(const Key('exercise-all-range')), findsNothing);
    expect(find.textContaining('유산소', findRichText: true), findsWidgets);
    // 머리줄은 고정 높이라(#1194) 그래프가 같은 자리·같은 크기다.
    expect(tester.getRect(_chart()), chart);

    await tester.tap(_bars().last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_average(), findsOneWidget, reason: '선택을 풀었는데 평균이 돌아오지 않는다');
    expect(tester.takeException(), isNull);
  });
}
