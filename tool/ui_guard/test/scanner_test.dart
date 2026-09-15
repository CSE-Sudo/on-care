import 'package:test/test.dart';
import 'package:ui_guard/ui_guard.dart';

/// [body] 를 위젯 build 메서드 안에 넣어 검사하고 걸린 항목 id 를 돌려준다.
List<String> scan(String body, {IconPolicy iconPolicy = IconPolicy.rounded}) {
  final source =
      '''
import 'package:flutter/material.dart';

Widget build(BuildContext context) {
  return $body;
}
''';
  return scanSource(
    source,
    iconPolicy: iconPolicy,
  ).map((f) => f.rule.id).toList();
}

void main() {
  group('글자', () {
    test('숫자 fontSize·letterSpacing·줄 높이를 잡는다', () {
      expect(
        scan(
          'Text("a", style: const TextStyle(fontSize: 14, '
          'letterSpacing: -0.2, height: 1.4))',
        ),
        ['fontSize', 'letterSpacing', 'lineHeight'],
      );
    });

    test('토큰으로 계산한 크기에 숫자를 섞어도 잡는다', () {
      expect(scan('TextStyle(fontSize: AppTypography.textScale * 14)'), [
        'fontSize',
      ]);
    });

    test('토큰만 쓰면 잡지 않는다', () {
      expect(
        scan(
          'Text("a", style: AppTypography.body.copyWith('
          'fontSize: AppTypography.bodySize, height: AppTypography.lh))',
        ),
        isEmpty,
      );
    });

    test('FontWeight 를 직접 적으면 잡는다', () {
      expect(scan('style.copyWith(fontWeight: FontWeight.w600)'), [
        'fontWeight',
      ]);
      expect(
        scan('style.copyWith(fontWeight: AppTypography.semibold)'),
        isEmpty,
      );
    });

    test('copyWith 줄 높이는 잡고, SizedBox height 는 줄 높이가 아니다', () {
      expect(scan('style?.copyWith(height: 1.3)'), ['lineHeight']);
      expect(scan('SizedBox(height: AppSpacing.md, child: x)'), isEmpty);
    });

    test('주석과 문자열 속 글자는 잡지 않는다', () {
      expect(
        scan('''Text(
          // fontSize: 14, Colors.red, Icons.close
          'fontSize: 14 Colors.red BoxShadow(',
        )'''),
        isEmpty,
      );
    });
  });

  group('색', () {
    test('Color(0x…) 와 Colors.* 를 잡되 transparent 는 뺀다', () {
      expect(
        scan(
          'Container(color: const Color(0xFF3EAFDF), '
          'foregroundDecoration: BoxDecoration(color: Colors.white), '
          'decoration: BoxDecoration(color: Colors.transparent))',
        ),
        ['colorLiteral', 'materialColor'],
      );
    });

    test('Colors.grey.shade200 은 한 번만 센다', () {
      expect(scan('Colors.grey.shade200'), ['materialColor']);
    });

    test('투명도 직접 지정을 잡는다', () {
      expect(scan('AppColors.primary.withValues(alpha: 0.16)'), ['opacity']);
      expect(scan('AppColors.primary.withOpacity(0.2)'), ['opacity']);
      expect(scan('AppColors.primary.withValues(red: 0.1)'), isEmpty);
    });
  });

  group('모양·간격', () {
    test('숫자 반경을 잡고 토큰 반경은 두지 않는다', () {
      expect(scan('BoxDecoration(borderRadius: BorderRadius.circular(12))'), [
        'radius',
      ]);
      expect(scan('BorderRadius.vertical(top: Radius.circular(20))'), [
        'radius',
      ]);
      expect(scan('BorderRadius.circular(AppRadius.md)'), isEmpty);
    });

    test('EdgeInsets 는 0 이 아닌 숫자가 있을 때 호출 한 번으로 센다', () {
      expect(scan('const EdgeInsets.fromLTRB(16, 0, 16, 8)'), ['edgeInsets']);
      expect(scan('EdgeInsets.symmetric(horizontal: 12)'), ['edgeInsets']);
      expect(scan('const EdgeInsets.only(top: 0)'), isEmpty);
      expect(scan('EdgeInsets.all(AppSpacing.md)'), isEmpty);
      expect(scan('EdgeInsets.zero'), isEmpty);
    });

    test('SizedBox·Gap 크기 숫자를 잡되 자식 속 숫자는 보지 않는다', () {
      expect(scan('const SizedBox(height: 8)'), ['sizedBox']);
      expect(scan('SizedBox.square(dimension: 40)'), ['sizedBox']);
      expect(scan('const Gap(12)'), ['sizedBox']);
      expect(
        scan('SizedBox(width: double.infinity, child: Text("a", maxLines: 2))'),
        isEmpty,
      );
      expect(scan('const SizedBox(width: 0)'), isEmpty);
    });

    test('BoxShadow 를 잡는다', () {
      expect(
        scan(
          'BoxDecoration(boxShadow: [BoxShadow(color: AppColors.shadow, '
          'blurRadius: AppElevation.blur)])',
        ),
        ['boxShadow'],
      );
    });
  });

  group('애니메이션 시간', () {
    test('애니메이션 duration 은 잡는다', () {
      expect(
        scan('AnimatedContainer(duration: const Duration(milliseconds: 200))'),
        ['animationDuration'],
      );
      expect(
        scan(
          'PageRouteBuilder(transitionDuration: '
          'const Duration(milliseconds: 250))',
        ),
        ['animationDuration'],
      );
    });

    test('대기·타이머·디바운스는 애니메이션이 아니다', () {
      expect(
        scan('Future<void>.delayed(const Duration(milliseconds: 300))'),
        isEmpty,
      );
      expect(scan('Future.delayed(Duration(milliseconds: 300))'), isEmpty);
      expect(scan('Timer(const Duration(milliseconds: 400), () {})'), isEmpty);
      expect(
        scan('Debouncer(debounceDuration: Duration(milliseconds: 400))'),
        isEmpty,
      );
      expect(scan('Duration(seconds: 3)'), isEmpty);
    });

    test('변수 이름으로 대기 시간을 구분한다', () {
      final source = '''
class A {
  static const Duration chartGrow = Duration(milliseconds: 750);
  static const _loginDelay = Duration(milliseconds: 600);
}
''';
      expect(scanSource(source).map((f) => f.rule.id), ['animationDuration']);
    });
  });

  group('아이콘·원시 위젯', () {
    test('_rounded 가 아닌 아이콘만 잡는다', () {
      expect(
        scan('Row(children: [Icon(Icons.close), Icon(Icons.close_rounded)])'),
        ['nonRoundedIcon'],
      );
    });

    test('트레이너웹(rounded)은 Symbols·Icon 생성을 보지 않는다', () {
      expect(
        scan('Row(children: [Icon(Symbols.home_rounded), const Icon(x)])'),
        isEmpty,
      );
    });

    test('회원앱 화면(registry)은 목록 밖 아이콘과 Icon 생성을 잡는다', () {
      expect(
        scan(
          'Row(children: [Icon(Icons.close_rounded), '
          'const Icon(Symbols.home_rounded, size: 16), '
          'AppIcon(AppIcons.home), AppButton(leadingIcon: Icons.add)])',
          iconPolicy: IconPolicy.registry,
        ),
        [
          'rawIcon',
          'iconOutsideRegistry',
          'rawIcon',
          'iconOutsideRegistry',
          'iconOutsideRegistry',
        ],
      );
      expect(
        scan('Symbols.home_rounded.codePoint', iconPolicy: IconPolicy.registry),
        ['iconOutsideRegistry'],
      );
      expect(
        scan(
          'Row(children: [AppIcon(AppIcons.home, size: 16), '
          'AppIconButton(icon: AppIcons.close), IconTheme(data: d, child: x)])',
          iconPolicy: IconPolicy.registry,
        ),
        isEmpty,
      );
    });

    test('아이콘 목록 파일(none)은 아이콘을 보지 않는다', () {
      expect(
        scan(
          'Row(children: [Icon(Symbols.home_rounded), Icon(Icons.close)])',
          iconPolicy: IconPolicy.none,
        ),
        isEmpty,
      );
    });

    test('Material 원시 위젯·함수 직접 사용을 잡는다', () {
      expect(
        scan('''Column(children: [
          FilledButton(onPressed: null, child: x),
          TextButton.icon(onPressed: null, label: x),
          const Divider(),
          DropdownButtonFormField<int>(items: const []),
          AppButton(label: 'a'),
        ])'''),
        [
          'materialWidget',
          'materialWidget',
          'materialWidget',
          'materialWidget',
        ],
      );
      expect(
        scan(
          'showDialog<void>(context: context, builder: (_) => '
          'const AlertDialog())',
        ),
        ['materialWidget', 'materialWidget'],
      );
    });

    test('비슷한 이름은 잡지 않는다', () {
      expect(
        scan(
          'Column(children: [DialogCloseButton(), AppBarTitle(), '
          'DividerTheme(data: d, child: x)])',
        ),
        isEmpty,
      );
    });
  });

  test('위치와 원문 줄을 함께 돌려준다', () {
    const source = 'final a = 1;\nfinal s = TextStyle(\n  fontSize: 14,\n);\n';
    final findings = scanSource(source);
    expect(findings, hasLength(1));
    expect(findings.single.line, 3);
    expect(findings.single.column, 3);
    expect(findings.single.snippet, 'fontSize: 14,');
  });
}
