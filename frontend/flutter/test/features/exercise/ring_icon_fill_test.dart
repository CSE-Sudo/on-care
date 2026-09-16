/// 운동 그래프 링 위 기호도 회원앱 아이콘 규칙(채움)을 따른다 (#1866).
///
/// 링 12시의 기호는 위젯이 아니라 캔버스에 **글자로 직접** 찍는다 — 테마를
/// 타지 않으므로 아이콘 묶음이 정한 축(FILL·wght)을 손으로 실어 주어야 한다.
/// 싣지 않으면 같은 아이콘이 화면 다른 곳에서는 채워지고 그래프 위에서만 빈
/// 외곽선으로 나온다.
///
/// 채워졌는지는 픽셀로만 알 수 있다. 시험 화면에는 글꼴 자산이 없어 글자가
/// 모두 네모로 그려지므로 진짜 가변 글꼴을 싣고([loadMaterialSymbolsRounded]),
/// **같은 화면을 두 테마로** 그려 링 위에 남은 흰 잉크를 견준다. 회원앱 묶음
/// (FILL 1)과 축이 없는 기본 묶음의 차이가 곧 채움이다.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/symbols_font.dart';

/// 도넛 지름 대비 두께와 링 사이 간격·구멍 — `_DonutPainter`·`_RingsPainter` 와
/// 같은 값이다.
const double _kDonutStrokeFactor = 0.13;
const double _kRingGap = 3;
const double _kRingHoleFactor = 0.22;

/// 축을 하나도 싣지 않는 테마 — 고치기 전의 링 기호와 같은 모양이 된다.
ThemeData _plainIcons() =>
    OnCareTheme.light(brand: OnCareBrand.member, density: OnCareDensity.mobile);

/// [painter] 를 그려 12시 언저리 **링 띠 안**의 픽셀을 훑어 온다.
///
/// 띠 밖(카드 흰 바탕·가운데 구멍)은 빼고 본다 — 보는 것은 링 위에 얹힌
/// 기호뿐이다. 두 테마에서 같은 순서로 훑으므로 자리끼리 그대로 견줄 수 있다.
Future<List<int>> _ringSector(
  CustomPainter painter,
  Size size, {
  required double radius,
  required double stroke,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final ui.Image image = await recorder.endRecording().toImage(
    size.width.ceil(),
    size.height.ceil(),
  );
  final ByteData pixels = (await image.toByteData())!;
  final int w = image.width;
  final int h = image.height;
  image.dispose();
  final Offset c = Offset(size.width / 2, size.height / 2);
  final List<int> out = <int>[];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final Offset p = Offset(x + 0.5, y + 0.5) - c;
      final double d = p.distance;
      if (d < radius - stroke / 2 || d > radius + stroke / 2) continue;
      // 12시에서 ±25도. 원호 끝의 `>` 기호는 반대편(6시)에 있다.
      final double angle = math.atan2(p.dy, p.dx) + math.pi / 2;
      if (angle.abs() > 25 * math.pi / 180) continue;
      final int i = (y * w + x) * 4;
      out.add(pixels.getUint32(i));
    }
  }
  return out;
}

/// 기호가 칠한 흰 픽셀 수 — 채운 기호일수록 많다.
int _white(List<int> sector) => sector
    .where(
      (int v) =>
          (v & 0xFF) >= 200 &&
          (v >> 24 & 0xFF) >= 245 &&
          (v >> 16 & 0xFF) >= 245 &&
          (v >> 8 & 0xFF) >= 245,
    )
    .length;

/// 두 그림이 서로 다른 자리 수.
int _diff(List<int> a, List<int> b) {
  expect(a.length, b.length, reason: '같은 자리를 훑어야 견줄 수 있다');
  int n = 0;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMaterialSymbolsRounded();
  });

  Widget wrap(Widget child, ThemeData theme) => MaterialApp(
    theme: theme,
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );

  Future<(CustomPainter, Size)> pumpChart(
    WidgetTester tester,
    Widget child,
    ThemeData theme,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(child, theme));
    await tester.pumpAndSettle();
    final Finder paint = find
        .descendant(
          of: find.byType(ChartReveal),
          matching: find.byType(CustomPaint),
        )
        .first;
    return (tester.widget<CustomPaint>(paint).painter!, tester.getSize(paint));
  }

  /// 소모 칼로리 도넛 — 목표의 절반이라 12시는 칠해진 원호 위다.
  Widget donut() => ExerciseDayLoadCard(
    load: ExerciseDayLoad(date: DateTime(2026), calories: 150),
  );

  /// 이번 주 세 링 — 셋 다 목표의 절반쯤 채운다.
  Widget rings() => ExerciseWeekLoadCard(
    loads: <ExerciseDayLoad>[
      ExerciseDayLoad(
        date: DateTime(2026),
        cardioMinutes: 75,
        strengthSets: 6,
        flexibilityMinutes: 30,
      ),
      for (int i = 1; i < 7; i++)
        ExerciseDayLoad(date: DateTime(2026, 1, 1 + i)),
    ],
  );

  group('링 위 기호의 채움', () {
    testWidgets('소모 칼로리 도넛의 불꽃이 채워진다', (WidgetTester tester) async {
      Future<List<int>> sectorWith(ThemeData theme) async {
        final (CustomPainter painter, Size size) = await pumpChart(
          tester,
          donut(),
          theme,
        );
        final double stroke = size.width * _kDonutStrokeFactor;
        return (await tester.runAsync(
          () => _ringSector(
            painter,
            size,
            radius: size.width / 2 - stroke / 2,
            stroke: stroke,
          ),
        ))!;
      }

      final List<int> filled = await sectorWith(AppTheme.light());
      final List<int> plain = await sectorWith(_plainIcons());
      expect(_white(plain), greaterThan(0), reason: '기호 자체는 두 테마 모두 그린다');
      expect(_diff(filled, plain), greaterThan(0), reason: '묶음이 모양을 바꾼다');
      // 불꽃은 속이 트인 외곽선에서 꽉 찬 덩어리가 된다.
      expect(_white(filled), greaterThan((_white(plain) * 1.3).round()));
    });

    testWidgets('근력 링의 덤벨도 같은 규칙을 따른다', (WidgetTester tester) async {
      Future<List<int>> sectorWith(ThemeData theme) async {
        final (CustomPainter painter, Size size) = await pumpChart(
          tester,
          rings(),
          theme,
        );
        // 가운데 링(근력) 자리 — `_RingsPainter` 와 같은 규칙이다.
        final double radius = size.width / 2;
        final double hole = radius * _kRingHoleFactor;
        final double stroke = (radius - _kRingGap * 2 - hole) / 3;
        return (await tester.runAsync(
          () => _ringSector(
            painter,
            size,
            radius: radius - stroke / 2 - (stroke + _kRingGap),
            stroke: stroke,
          ),
        ))!;
      }

      final List<int> filled = await sectorWith(AppTheme.light());
      final List<int> plain = await sectorWith(_plainIcons());
      expect(_white(plain), greaterThan(0), reason: '기호 자체는 두 테마 모두 그린다');
      expect(_diff(filled, plain), greaterThan(0), reason: '묶음이 모양을 바꾼다');
      // 덤벨은 채우면서 굵기도 한 단계 얇아진다(운동 아이콘 예외) — 넓어지되
      // 불꽃만큼 크게 벌어지지는 않는다.
      expect(_white(filled), greaterThan(_white(plain)));
    });
  });
}
