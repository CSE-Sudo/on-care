import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 가변 글꼴 묶음을 흉내 내는 시험용 아이콘. 자리마다 코드포인트가 달라 어느
// 자리의 아이콘이 그려졌는지 가려낼 수 있다.
const IconData _back = IconData(0xe001, fontFamily: 'TestSymbols');
const IconData _close = IconData(0xe002, fontFamily: 'TestSymbols');
const IconData _previous = IconData(0xe003, fontFamily: 'TestSymbols');
const IconData _next = IconData(0xe004, fontFamily: 'TestSymbols');
const IconData _disclosure = IconData(0xe005, fontFamily: 'TestSymbols');
const IconData _dropdown = IconData(0xe006, fontFamily: 'TestSymbols');
const IconData _search = IconData(0xe007, fontFamily: 'TestSymbols');
const IconData _add = IconData(0xe008, fontFamily: 'TestSymbols');
const IconData _remove = IconData(0xe009, fontFamily: 'TestSymbols');
const IconData _check = IconData(0xe00a, fontFamily: 'TestSymbols');
const IconData _info = IconData(0xe00b, fontFamily: 'TestSymbols');
const IconData _success = IconData(0xe00c, fontFamily: 'TestSymbols');
const IconData _caution = IconData(0xe00d, fontFamily: 'TestSymbols');
const IconData _error = IconData(0xe00e, fontFamily: 'TestSymbols');
const IconData _empty = IconData(0xe00f, fontFamily: 'TestSymbols');
const IconData _offline = IconData(0xe010, fontFamily: 'TestSymbols');
const IconData _image = IconData(0xe011, fontFamily: 'TestSymbols');
const IconData _attachImage = IconData(0xe012, fontFamily: 'TestSymbols');
const IconData _emote = IconData(0xE9F0, fontFamily: 'X');
const IconData _send = IconData(0xe013, fontFamily: 'TestSymbols');
const IconData _file = IconData(0xe014, fontFamily: 'TestSymbols');
const IconData _glyph = IconData(0xe015, fontFamily: 'TestSymbols');
const IconData _thin = IconData(0xe016, fontFamily: 'TestSymbols');
const IconData _calendarExpand = IconData(0xe017, fontFamily: 'TestSymbols');
const IconData _calendarCollapse = IconData(0xe018, fontFamily: 'TestSymbols');
const IconData _reward = IconData(0xe019, fontFamily: 'TestSymbols');
const IconData _mail = IconData(0xe01a, fontFamily: 'TestSymbols');
const IconData _lock = IconData(0xe01b, fontFamily: 'TestSymbols');
const IconData _visibility = IconData(0xe01c, fontFamily: 'TestSymbols');
const IconData _visibilityOff = IconData(0xe01d, fontFamily: 'TestSymbols');

const OnCareIconSet _symbols = OnCareIconSet(
  name: 'test',
  back: _back,
  close: _close,
  previous: _previous,
  next: _next,
  disclosure: _disclosure,
  dropdown: _dropdown,
  calendarExpand: _calendarExpand,
  calendarCollapse: _calendarCollapse,
  search: _search,
  add: _add,
  remove: _remove,
  check: _check,
  info: _info,
  success: _success,
  caution: _caution,
  error: _error,
  empty: _empty,
  offline: _offline,
  image: _image,
  attachImage: _attachImage,
  send: _send,
  emote: _emote,
  file: _file,
  reward: _reward,
  mail: _mail,
  lock: _lock,
  visibility: _visibility,
  visibilityOff: _visibilityOff,
  fill: 1,
  weight: 400,
  grade: 0,
  minOpticalSize: 20,
  maxOpticalSize: 48,
  weightOverrides: <OnCareIconWeight>[OnCareIconWeight(_thin, 300)],
);

Future<void> _pump(
  WidgetTester tester,
  List<Widget> children, {
  OnCareIconSet icons = OnCareIconSet.material,
  OnCareBrand brand = OnCareBrand.member,
  OnCareDensity density = OnCareDensity.mobile,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: OnCareTheme.light(brand: brand, density: density, icons: icons),
      home: Scaffold(body: ListView(children: children)),
    ),
  );
}

List<Widget> _components() => <Widget>[
  const Row(children: <Widget>[AppBackButton(), AppCloseButton()]),
  const AppBanner(title: '안내'),
  const AppBanner(title: '주의', tone: AppBannerTone.caution),
  const AppEmptyState(title: '비어 있음', placement: AppStatePlacement.card),
  Center(
    child: AppNavAddButton(tooltip: '기록 추가', onPressed: () {}),
  ),
  const SizedBox(height: 80, child: AppImageFrame()),
];

Icon _iconOf(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon));

void main() {
  group('아이콘 묶음(#1803)', () {
    test('테마에 묶음이 실리고, 비우면 Material Icons 기본 묶음이다', () {
      final OnCareTokens trainer = OnCareTheme.light(
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
      ).extension<OnCareTokens>()!;
      final OnCareTokens member = OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
        icons: _symbols,
      ).extension<OnCareTokens>()!;
      expect(trainer.icons, OnCareIconSet.material);
      expect(member.icons, _symbols);
      expect(member, isNot(member.copyWith(icons: OnCareIconSet.material)));
      expect(member.copyWith().icons, _symbols);
    });

    testWidgets('기본 묶음은 지금 아이콘 그대로이고 글꼴 변형을 싣지 않는다', (tester) async {
      await _pump(
        tester,
        _components(),
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
      );
      for (final IconData icon in <IconData>[
        Icons.chevron_left_rounded,
        Icons.close_rounded,
        Icons.info_rounded,
        Icons.warning_rounded,
        Icons.inbox_rounded,
        Icons.add_rounded,
        Icons.image_rounded,
      ]) {
        final Icon widget = _iconOf(tester, icon);
        expect(widget.fill, isNull, reason: '$icon');
        expect(widget.weight, isNull, reason: '$icon');
        expect(widget.grade, isNull, reason: '$icon');
        expect(widget.opticalSize, isNull, reason: '$icon');
      }
    });

    testWidgets('앱이 넣은 묶음으로 공용 컴포넌트 아이콘이 바뀐다', (tester) async {
      await _pump(tester, _components(), icons: _symbols);
      for (final IconData icon in <IconData>[
        _back,
        _close,
        _info,
        _caution,
        _empty,
        _add,
        _image,
      ]) {
        expect(find.byIcon(icon), findsOneWidget, reason: '$icon');
      }
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      expect(find.byIcon(Icons.inbox_rounded), findsNothing);
    });

    testWidgets('채움·굵기·등급을 싣고 광학 크기는 그리는 크기를 따른다', (tester) async {
      await _pump(tester, <Widget>[
        const AppIcon(_glyph, key: Key('16'), size: 16),
        const AppIcon(_glyph, key: Key('24'), size: 24),
        const AppIcon(_glyph, key: Key('40'), size: 40),
        const AppIcon(_glyph, key: Key('56'), size: 56),
        const AppIcon(_thin, size: 24),
        AppIconButton(icon: _search, tooltip: '검색', onPressed: () {}),
      ], icons: _symbols);

      Icon keyed(String key) => tester.widget<Icon>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Icon)),
      );
      // 광학 크기 축(20~48) 밖의 크기는 끝값으로 자른다.
      expect(keyed('16').opticalSize, 20);
      expect(keyed('24').opticalSize, 24);
      expect(keyed('40').opticalSize, 40);
      expect(keyed('56').opticalSize, 48);
      final Icon regular = keyed('24');
      expect(regular.fill, 1);
      expect(regular.weight, 400);
      expect(regular.grade, 0);

      // 예외로 둔 아이콘만 굵기가 다르다.
      expect(_iconOf(tester, _thin).weight, 300);

      // 크기를 적지 않으면 버튼이 정한 아이콘 크기로 광학 크기를 고른다.
      expect(
        _iconOf(tester, _search).opticalSize,
        OnCareDensity.mobile.iconButtonIcon.clamp(20, 48),
      );
    });

    testWidgets('토스트 적립 표시의 별을 묶음에서 고른다', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: OnCareTheme.light(
            brand: OnCareBrand.member,
            density: OnCareDensity.mobile,
            icons: _symbols,
          ),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                captured = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      showAppToast(captured, '저장했어요', rewardLabel: '+50P');
      await tester.pump(OnCareMotion.toastEnter);

      final Finder badge = find.byKey(const ValueKey<String>('appToastReward'));
      expect(
        find.descendant(of: badge, matching: find.byIcon(_reward)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });
  });

  group('캔버스에 직접 찍는 아이콘(#1866)', () {
    test('묶음이 정한 축을 [Icon] 과 같은 값으로 싣는다', () {
      expect(_symbols.fontVariationsFor(_glyph, 24), <FontVariation>[
        const FontVariation('FILL', 1),
        const FontVariation('wght', 400),
        const FontVariation('GRAD', 0),
        const FontVariation('opsz', 24),
      ]);
      // 굵기 예외와 광학 크기 자르기도 위젯과 똑같이 따른다.
      expect(
        _symbols.fontVariationsFor(_thin, 56),
        contains(const FontVariation('wght', 300)),
      );
      expect(
        _symbols.fontVariationsFor(_glyph, 56),
        contains(const FontVariation('opsz', 48)),
      );
      // 축이 없는 기본 묶음(Material Icons)은 아무것도 싣지 않는다.
      expect(
        OnCareIconSet.material.fontVariationsFor(Icons.star_rounded, 24),
        isEmpty,
      );
    });

    test('글자로 찍어도 위젯으로 그린 것과 같은 모양이다', () {
      final TextPainter tp = AppIcon.glyphPainter(
        _symbols,
        _glyph,
        size: 24,
        color: const Color(0xFF123456),
      );
      final TextStyle style = (tp.text! as TextSpan).style!;
      expect(
        (tp.text! as TextSpan).text,
        String.fromCharCode(_glyph.codePoint),
      );
      expect(style.fontFamily, _glyph.fontFamily);
      expect(style.fontSize, 24);
      expect(style.color, const Color(0xFF123456));
      expect(style.fontVariations, _symbols.fontVariationsFor(_glyph, 24));
      // 재어 둔 상태로 돌려준다 — 받는 쪽이 바로 자리를 잡을 수 있다.
      expect(tp.width, greaterThan(0));
    });
  });
}
