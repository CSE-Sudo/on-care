/// 운동 그래프 링 위 기호도 회원앱 아이콘 규칙을 따른다 (#1866).
///
/// 링 12시의 기호는 위젯이 아니라 캔버스에 **글자로 직접** 찍는다 — 캔버스에
/// 직접 그리는 글자는 테마를 타지 않으므로, 아이콘 묶음이 정한 축(채움·굵기)을
/// 손으로 실어 주어야 한다. 싣지 않으면 같은 아이콘이 화면 다른 곳에서는
/// 채워지고 그래프 위에서만 빈 외곽선으로 나온다.
///
/// 축이 실렸는지는 픽셀로만 알 수 있다. 시험 화면에는 글꼴 자산이 없어 글자가
/// 모두 네모로 그려지므로 진짜 가변 글꼴을 싣고([loadMaterialSymbolsRounded]),
/// **축만 다른 두 묶음**으로 같은 화면을 그려 링 위 흰 잉크를 견준다.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:oncare/app/app_icons.dart';
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

/// 축만 다른 시험용 묶음. 링 기호의 **그림**은 화면 코드가 고르고 묶음에서는
/// 축만 가져다 쓰므로, 그림 자리는 아무 아이콘이나 채운다.
const IconData _any = AppIcons.info;

OnCareIconSet _axes({double? fill, double weight = 400}) => OnCareIconSet(
  name: 'axes',
  back: _any,
  close: _any,
  previous: _any,
  next: _any,
  disclosure: _any,
  dropdown: _any,
  calendarExpand: _any,
  calendarCollapse: _any,
  search: _any,
  add: _any,
  remove: _any,
  check: _any,
  info: _any,
  success: _any,
  caution: _any,
  error: _any,
  empty: _any,
  offline: _any,
  image: _any,
  attachImage: _any,
  send: _any,
  emote: _any,
  file: _any,
  reward: _any,
  mail: _any,
  lock: _any,
  visibility: _any,
  visibilityOff: _any,
  fill: fill,
  weight: weight,
  grade: 0,
  minOpticalSize: 20,
  maxOpticalSize: 48,
);

ThemeData _themeOf(OnCareIconSet icons) => OnCareTheme.light(
  brand: OnCareBrand.member,
  density: OnCareDensity.mobile,
  icons: icons,
);

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
    test('운동·헬스장·근력은 기본 굵기 400의 덤벨 하나를 공유한다', () {
      expect(AppIcons.exercise, Symbols.fitness_center_rounded);
      expect(AppIcons.gym, AppIcons.exercise);
      expect(AppIcons.strength, AppIcons.exercise);
      expect(AppIcons.oncare.weight, 400);
      expect(AppIcons.oncare.weightOverrides, isEmpty);
    });

    test('회원앱 테마가 회원앱 아이콘 묶음을 싣는다', () {
      expect(
        AppTheme.light().extension<OnCareTokens>()!.icons,
        AppIcons.oncare,
      );
    });

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

      final List<int> filled = await sectorWith(_themeOf(_axes(fill: 1)));
      final List<int> outline = await sectorWith(_themeOf(_axes()));
      expect(_white(outline), greaterThan(0), reason: '기호 자체는 두 묶음 모두 그린다');
      expect(_diff(filled, outline), greaterThan(0), reason: '묶음이 모양을 바꾼다');
      // 불꽃은 속이 트인 외곽선에서 꽉 찬 덩어리가 된다.
      expect(_white(filled), greaterThan((_white(outline) * 1.3).round()));
    });

    testWidgets('세 링의 기호도 묶음이 정한 굵기로 그려진다', (WidgetTester tester) async {
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

      // 근력 덤벨은 채움 축이 모양을 바꾸지 않는 선 기호다(달리기·스트레칭도
      // 같다) — 이 링에서는 묶음의 **굵기**가 실리는지로 본다.
      final List<int> regular = await sectorWith(_themeOf(_axes(fill: 1)));
      final List<int> heavy = await sectorWith(
        _themeOf(_axes(fill: 1, weight: 700)),
      );
      expect(_white(regular), greaterThan(0), reason: '기호 자체는 두 묶음 모두 그린다');
      expect(_diff(regular, heavy), greaterThan(0), reason: '묶음이 모양을 바꾼다');
      expect(_white(heavy), greaterThan(_white(regular)));
    });
  });
}
