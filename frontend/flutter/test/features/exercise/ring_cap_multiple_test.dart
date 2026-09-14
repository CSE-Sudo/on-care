/// 목표의 정확한 정수 배(100%, 200%, 300% …)에서 원형 그래프 캡 그림자와
/// 진행 끝 기호를 그리지 않는다 (#1462).
///
/// 이 자리에서는 원호 끝이 12시의 고정 시작 기호와 겹쳐, 캡 그림자가
/// 아이콘 뒤 검은 배경처럼 보이고 진행 끝 `>` 기호가 시작 기호와 겹쳐
/// 두 개로 보인다. 소모 칼로리 단일 도넛과 유산소·근력·스트레칭 다중 링
/// 모두 같은 규칙을 쓴다.
///
/// painter 가 private 이라 내부 필드를 볼 수 없으니, 실제로 래스터화한
/// 픽셀이 유일하게 믿을 수 있는 증거다. 두 가지를 잰다.
///
///  * 정확한 배수에서는 캡(원호 끝) 자리에 **아주 어두운**(캡 그림자
///    `0xBF000000`/`0xA6000000` 를 걷어낸) 픽셀이 하나도 없어야 한다.
///  * 배수가 아닌 값에서는 그림자·끝 기호·추가 원호가 그대로 그려져,
///    화면 전체에서 칠해진 픽셀 수(`painterInk`)가 인접한 정확한 배수보다
///    늘어나야 한다. (캡 바로 그 자리는 그림자 위에 같은 색 원호가 다시
///    덧칠돼 그림자 대부분을 가리므로, "그 자리가 어두운가" 보다 "전체
///    그림이 달라졌는가" 가 더 믿을 수 있는 잣대다.)
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
import 'package:oncare_ui/oncare_ui.dart' show ChartReveal;

import '../../helpers/painter_ink.dart';

/// 원호 끝(캡)이 설 각도. 소스의 `_DonutPainter`/`_RingsPainter` 와 같은
/// 규칙이다 — 정확한 배수([isAtRingMultiple])면 12시([over]=0), 아니면
/// 한 바퀴를 넘긴 몫만큼 12시에서 더 돈다.
double _capAngle(double filled) {
  if (filled >= 1) {
    final double over = isAtRingMultiple(filled)
        ? 0
        : filled - filled.floorToDouble();
    return -math.pi / 2 + math.pi * 2 * over;
  } else if (filled > 0) {
    return -math.pi / 2 + math.pi * 2 * filled;
  }
  return -math.pi / 2;
}

Offset _donutCapPoint(Size size, double filled) {
  final double stroke = size.width * 0.13;
  final double r = size.width / 2 - stroke / 2;
  final Offset c = Offset(size.width / 2, size.height / 2);
  final double angle = _capAngle(filled);
  return c + Offset(math.cos(angle), math.sin(angle)) * r;
}

/// [index] 번째 링(0=유산소, 1=근력, 2=스트레칭)의 반지름 — `_RingsPainter`
/// 와 같은 규칙(고정 두께, 링마다 두께+간격씩 안쪽으로)이다.
double _ringRadius(Size size, int index) {
  final double radius = size.width / 2;
  const double gap = 3;
  final double hole = radius * 0.22;
  final double stroke = (radius - gap * 2 - hole) / 3;
  double r = radius - stroke / 2;
  for (int i = 0; i < index; i++) {
    r -= stroke + gap;
  }
  return r;
}

Offset _ringCapPoint(Size size, int index, double filled) {
  final Offset c = Offset(size.width / 2, size.height / 2);
  final double r = _ringRadius(size, index);
  final double angle = _capAngle(filled);
  return c + Offset(math.cos(angle), math.sin(angle)) * r;
}

/// [painter] 를 [size] 로 그려 [point] 둘레(한 변 `half*2+1`)에서 **아주
/// 어두운**(RGB 합이 [threshold] 미만) 픽셀 수를 센다.
///
/// 가장자리 anti-aliasing 픽셀은 알파가 낮을수록 (premultiplied) RGB 값도
/// 함께 낮아져 "옅게 칠해진 밝은 색" 이 "짙은 그림자" 로 잘못 잡힌다 —
/// 알파가 충분히 높은(`alphaThreshold` 이상, 즉 거의 다 칠해진) 픽셀만 본다.
Future<int> _darkPixelsNear(
  CustomPainter painter,
  Size size,
  Offset point, {
  int half = 4,
  int threshold = 150,
  int alphaThreshold = 200,
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
  final int cx = point.dx.round();
  final int cy = point.dy.round();
  int dark = 0;
  for (int y = math.max(0, cy - half); y <= math.min(h - 1, cy + half); y++) {
    for (int x = math.max(0, cx - half); x <= math.min(w - 1, cx + half); x++) {
      final int i = (y * w + x) * 4;
      if (pixels.getUint8(i + 3) < alphaThreshold) continue;
      final int sum =
          pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2);
      if (sum < threshold) dark++;
    }
  }
  return dark;
}

void main() {
  // ── isAtRingMultiple 순수 함수 ──────────────────────────────────────

  group('isAtRingMultiple', () {
    test('정확한 양의 정수 배는 참', () {
      expect(isAtRingMultiple(1), isTrue);
      expect(isAtRingMultiple(2), isTrue);
      expect(isAtRingMultiple(3), isTrue);
    });

    test('배수가 아닌 값은 거짓', () {
      expect(isAtRingMultiple(0.5), isFalse);
      expect(isAtRingMultiple(1.2), isFalse);
      expect(isAtRingMultiple(627 / 300), isFalse); // 209%
    });

    test('0은 배수로 치지 않는다 — 빈 트랙 표시를 유지한다', () {
      expect(isAtRingMultiple(0), isFalse);
    });

    test('음수·무한대·NaN 은 배수가 아니다', () {
      expect(isAtRingMultiple(-1), isFalse);
      expect(isAtRingMultiple(double.infinity), isFalse);
      expect(isAtRingMultiple(double.nan), isFalse);
    });

    test('부동소수점 오차가 섞인 인접 값도 같은 자리로 본다', () {
      // 1.999999… 또는 2.000000… 처럼 계산될 수 있는 값들.
      expect(isAtRingMultiple(1 - 1e-9), isTrue);
      expect(isAtRingMultiple(1 + 1e-9), isTrue);
      expect(isAtRingMultiple(2 - 1e-9), isTrue);
      expect(isAtRingMultiple(2 + 1e-9), isTrue);
      expect(isAtRingMultiple(3 - 1e-9), isTrue);
    });

    test('허용 오차를 벗어나면 더 이상 배수가 아니다', () {
      expect(isAtRingMultiple(1 - 1e-4), isFalse);
      expect(isAtRingMultiple(1 + 1e-4), isFalse);
    });
  });

  // ── 화면 렌더링 공통 ─────────────────────────────────────────────────

  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );

  /// [child] 를 정착(settle)시킨 뒤, `ChartReveal` 바로 아래 `CustomPaint`
  /// 의 painter 와 실제 렌더 크기를 함께 돌려준다 — 도넛·링 painter 를
  /// 감싸는 자리다. `exercise_chart_animation_test.dart` 의 `chartPainter`
  /// 와 같은 자리를 짚는다.
  Future<(CustomPainter, Size)> pumpChart(
    WidgetTester tester,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
    final Finder paint = find
        .descendant(
          of: find.byType(ChartReveal),
          matching: find.byType(CustomPaint),
        )
        .first;
    final CustomPainter painter = tester.widget<CustomPaint>(paint).painter!;
    final Size size = tester.getSize(paint);
    return (painter, size);
  }

  // ── 소모 칼로리 단일 도넛 (목표 300kcal) ────────────────────────────

  Future<(CustomPainter, Size)> pumpDonut(
    WidgetTester tester,
    double calories,
  ) => pumpChart(
    tester,
    ExerciseDayLoadCard(
      load: ExerciseDayLoad(date: DateTime(2026), calories: calories),
    ),
  );

  Future<int> donutDarkAtCap(WidgetTester tester, double calories) async {
    final (CustomPainter painter, Size size) = await pumpDonut(
      tester,
      calories,
    );
    final Offset cap = _donutCapPoint(size, calories / 300);
    return (await tester.runAsync(() => _darkPixelsNear(painter, size, cap)))!;
  }

  Future<int> donutInk(WidgetTester tester, double calories) async {
    final (CustomPainter painter, Size size) = await pumpDonut(
      tester,
      calories,
    );
    return (await tester.runAsync(() => painterInk(painter, size)))!;
  }

  group('소모 칼로리 도넛 (목표 300kcal)', () {
    testWidgets('정확한 배수(100%·200%·300%)에서는 캡 자리에 검은 그림자가 없다', (
      WidgetTester tester,
    ) async {
      for (final double kcal in <double>[300, 600, 900]) {
        expect(
          await donutDarkAtCap(tester, kcal),
          0,
          reason: '$kcal kcal 는 정확한 배수라 그림자가 없어야 한다',
        );
      }
    });

    testWidgets('부동소수점 오차로 흔들린 인접 값도 정확한 배수처럼 그림자가 없다', (
      WidgetTester tester,
    ) async {
      // 1.999999… 또는 2.000000… 처럼 계산될 수 있는 값에 대응한다.
      expect(await donutDarkAtCap(tester, 300 * (1 - 1e-9)), 0);
      expect(await donutDarkAtCap(tester, 300 * (1 + 1e-9)), 0);
      expect(await donutDarkAtCap(tester, 600 * (1 - 1e-9)), 0);
    });

    testWidgets('허용 오차를 벗어난 인접 값(100%+ε)은 정확한 배수와 다르게 그려진다', (
      WidgetTester tester,
    ) async {
      final int at100 = await donutInk(tester, 300);
      final int justOver100 = await donutInk(tester, 300 * (1 + 1e-4));
      expect(
        justOver100,
        greaterThan(at100),
        reason: '허용 오차를 벗어난 값은 그림자·끝 기호가 그려져 있어야 한다',
      );
    });

    testWidgets('배수가 아닌 50%·120%·209% 는 기존처럼 그림자·끝 기호가 있다', (
      WidgetTester tester,
    ) async {
      final int at0 = await donutInk(tester, 0);
      expect(await donutInk(tester, 150), greaterThan(at0)); // 50%

      final int at100 = await donutInk(tester, 300);
      expect(await donutInk(tester, 360), greaterThan(at100)); // 120%

      final int at200 = await donutInk(tester, 600);
      expect(await donutInk(tester, 627), greaterThan(at200)); // 209%
    });

    testWidgets('0% 는 기존 빈 트랙·시작 아이콘 표시를 유지한다', (WidgetTester tester) async {
      expect(isAtRingMultiple(0), isFalse);
      expect(await donutDarkAtCap(tester, 0), 0);
      expect(await donutInk(tester, 0), greaterThan(0));
    });
  });

  // ── 유산소·근력·스트레칭 다중 링 ─────────────────────────────────────

  List<ExerciseDayLoad> weekOf({
    double cardio = 0,
    int strength = 0,
    double flex = 0,
  }) => <ExerciseDayLoad>[
    ExerciseDayLoad(
      date: DateTime(2026),
      cardioMinutes: cardio,
      strengthSets: strength,
      flexibilityMinutes: flex,
    ),
    for (int i = 1; i < 7; i++) ExerciseDayLoad(date: DateTime(2026, 1, 1 + i)),
  ];

  Future<(CustomPainter, Size)> pumpRings(
    WidgetTester tester, {
    double cardio = 0,
    int strength = 0,
    double flex = 0,
  }) => pumpChart(
    tester,
    ExerciseWeekLoadCard(
      loads: weekOf(cardio: cardio, strength: strength, flex: flex),
    ),
  );

  /// [index] 번째 링(0=유산소, 1=근력, 2=스트레칭)의 캡 자리에 어두운 픽셀이
  /// 있는지 잰다. 나머지 두 링은 0(빈 트랙)으로 둔다.
  Future<int> ringDarkAtCap(
    WidgetTester tester, {
    required int index,
    required double filled,
    required double goal,
    int threshold = 150,
  }) async {
    final double value = filled * goal;
    final (CustomPainter painter, Size size) = await pumpRings(
      tester,
      cardio: index == 0 ? value : 0,
      strength: index == 1 ? value.round() : 0,
      flex: index == 2 ? value : 0,
    );
    final Offset cap = _ringCapPoint(size, index, filled);
    return (await tester.runAsync(
      () => _darkPixelsNear(painter, size, cap, threshold: threshold),
    ))!;
  }

  group('유산소·근력·스트레칭 다중 링 (기본 목표: 근력 21세트·유산소 150분·스트레칭 60분)', () {
    testWidgets('근력 목표 21세트에서 21·42·63세트(100%·200%·300%)는 캡 그림자가 없다', (
      WidgetTester tester,
    ) async {
      for (final int sets in <int>[21, 42, 63]) {
        expect(
          await ringDarkAtCap(tester, index: 1, filled: sets / 21, goal: 21),
          0,
          reason: '$sets 세트는 정확한 배수라 그림자가 없어야 한다',
        );
      }
    });

    testWidgets('유산소 링: 부동소수점 오차가 섞인 인접 값도 정확한 배수처럼 그림자가 없다', (
      WidgetTester tester,
    ) async {
      expect(
        await ringDarkAtCap(tester, index: 0, filled: 1 - 1e-9, goal: 150),
        0,
      );
      expect(
        await ringDarkAtCap(tester, index: 0, filled: 1 + 1e-9, goal: 150),
        0,
      );
      expect(
        await ringDarkAtCap(tester, index: 0, filled: 2 - 1e-9, goal: 150),
        0,
      );
    });

    /// [index] 번째 링 캡 자리의 평균 밝기(칠해진 픽셀의 RGB 합 평균).
    ///
    /// 트랙이 불투명 토큰 색(`OnCareColors.onWhite`)이고 그림자가 순검정이 아닌
    /// 흐린 `overlayInk` 라, 고정 문턱의 "아주 어두운" 픽셀은 생기지 않는다.
    /// 그래서 정확한 배수(그림자 없음)의 캡 자리보다 **확연히 어두운지**로
    /// 그림자를 가른다(#1701).
    Future<double> ringCapBrightness(
      WidgetTester tester, {
      required int index,
      required double filled,
      required double goal,
    }) async {
      final double value = filled * goal;
      final (CustomPainter painter, Size size) = await pumpRings(
        tester,
        cardio: index == 0 ? value : 0,
        strength: index == 1 ? value.round() : 0,
        flex: index == 2 ? value : 0,
      );
      final Offset cap = _ringCapPoint(size, index, filled);
      return (await tester.runAsync(() async {
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
        final int cx = cap.dx.round();
        final int cy = cap.dy.round();
        int sum = 0;
        int count = 0;
        for (int y = math.max(0, cy - 2); y <= math.min(h - 1, cy + 2); y++) {
          for (int x = math.max(0, cx - 2); x <= math.min(w - 1, cx + 2); x++) {
            final int i = (y * w + x) * 4;
            if (pixels.getUint8(i + 3) < 200) continue;
            sum +=
                pixels.getUint8(i) +
                pixels.getUint8(i + 1) +
                pixels.getUint8(i + 2);
            count++;
          }
        }
        return count == 0 ? 765.0 : sum / count;
      }))!;
    }

    /// 그림자가 있다고 볼 밝기 차이(RGB 합). 흐린 그림자라 캡 한가운데서도
    /// 몇 단계만 어두워진다 — 같은 링의 정확한 배수보다 어둡기만 하면 된다.
    const double shadowDarkening = 2;

    testWidgets('근력 링: 배수가 아닌 값(약 119%·219%·319%)은 기존처럼 그려진다', (
      WidgetTester tester,
    ) async {
      final double exact = await ringCapBrightness(
        tester,
        index: 1,
        filled: 1,
        goal: 21,
      );
      for (final int sets in <int>[25, 46, 67]) {
        expect(
          await ringCapBrightness(
            tester,
            index: 1,
            filled: sets / 21,
            goal: 21,
          ),
          lessThan(exact - shadowDarkening),
          reason: '$sets 세트는 21세트의 배수가 아니라 캡 그림자가 있어야 한다',
        );
      }
    });

    testWidgets('스트레칭 링: 배수가 아닌 120% 는 기존처럼 그림자·끝 기호가 있다', (
      WidgetTester tester,
    ) async {
      expect(await ringDarkAtCap(tester, index: 2, filled: 1, goal: 60), 0);
      final double exact = await ringCapBrightness(
        tester,
        index: 2,
        filled: 1,
        goal: 60,
      );
      expect(
        await ringCapBrightness(tester, index: 2, filled: 1.2, goal: 60),
        lessThan(exact - shadowDarkening),
      );
    });

    testWidgets('세 링 모두 0% 인 초기 상태는 기존 빈 트랙 표시를 유지한다', (
      WidgetTester tester,
    ) async {
      final (CustomPainter painter, Size size) = await pumpRings(tester);
      expect(
        await tester.runAsync(() => painterInk(painter, size)),
        greaterThan(0),
      );
      expect(
        await tester.runAsync(
          () => _darkPixelsNear(painter, size, _ringCapPoint(size, 0, 0)),
        ),
        0,
      );
    });
  });
}
