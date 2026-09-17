/// 분석 완료 시트의 동작 버튼과 분석 중 화면. (#1564)
///
/// 시연은 `사진 찍기` → 분석 중 → 분석 완료 순으로 흐른다. 데모 응답이 즉시
/// 오더라도 분석 중 화면이 보여야 하고, 완료 시트의 닫기는 머리의 X 가 아니라
/// `저장` 옆 `취소` 하나로 모인다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async =>
      MealPhoto.fromBytes(_jpegBytes)!;
}

Future<void> _pumpApp(
  WidgetTester tester,
  FakeDietRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
        dietRepositoryProvider.overrideWithValue(repository),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDietAddSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `사진 찍기` 까지 눌러 분석을 시작한다. 결과를 기다리지는 않는다.
Future<void> _startAnalyze(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('사진 찍기'));
}

void main() {
  testWidgets('응답이 즉시 와도 분석 중 화면이 잠시 보인다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _pumpApp(tester, FakeDietRepository());
    await _startAnalyze(tester);

    // 대역은 곧바로 답하지만 시트는 아직 분석 중이다 — 이 화면이 없으면
    // 촬영 직후 결과가 튀어나와 AI 가 무엇을 했는지 보이지 않는다.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('diet-result-analyzing')), findsOneWidget);
    expect(find.text('저장'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diet-result-analyzing')), findsNothing);
    expect(find.text('저장'), findsOneWidget);
  });

  testWidgets('완료 시트는 저장·취소·수정을 갖고 X 는 없다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _pumpApp(tester, FakeDietRepository());
    await _startAnalyze(tester);
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.text('저장')),
    );
    expect(find.text(l.dietSave), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    expect(find.byKey(const Key('diet-result-edit')), findsOneWidget);
    // 체크 아이콘과 머리의 X 는 지웠다 — 닫는 자리는 `취소` 하나다.
    expect(find.byIcon(AppIcons.check), findsNothing);
    expect(find.byIcon(AppIcons.close), findsNothing);

    // 두 버튼은 한 행에 서고 크기가 같다.
    final Size save = tester.getSize(
      find.ancestor(of: find.text('저장'), matching: find.byType(AppButton)),
    );
    final Size cancel = tester.getSize(
      find.ancestor(of: find.text('취소'), matching: find.byType(AppButton)),
    );
    expect(save.height, cancel.height);
    // 폭은 반반이다 — 앱의 모든 하단 두 버튼과 같다(#1690).
    expect(save.width, cancel.width);
  });

  testWidgets('완료 시트는 머리에 아바타·연필을 두고 버튼을 스크롤 안에 둔다', (
    WidgetTester tester,
  ) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _pumpApp(tester, FakeDietRepository());
    await _startAnalyze(tester);
    await tester.pumpAndSettle();

    // AI 가 읽은 결과를 말하는 시트라, 홈의 AI 조언 카드와 같은 아바타를 쓴다.
    expect(find.byType(OniAvatar), findsOneWidget);

    // 연필은 인식된 음식 줄이 아니라 머리에 선다 — 걸린 범위가 음식 한 줄이
    // 아니라 시트 전체다.
    final double pencil = tester
        .getCenter(find.byKey(const Key('diet-result-edit')))
        .dy;
    final double recognized = tester
        .getTopLeft(find.byKey(const Key('diet-result-recognized')))
        .dy;
    expect(pencil, lessThan(recognized));

    // 강조는 인식된 음식 하나뿐이라 거기에만 옅은 브랜드 채움이 남는다.
    // 구획을 여럿 쌓으면 카드가 온통 옅은 파랑이 된다(`0389e572`).
    final AppTile tile = tester.widget<AppTile>(
      find.byKey(const Key('diet-result-recognized')),
    );
    expect(tile.tone, AppTileTone.brand);

    // 버튼이 스크롤 영역 안에 있어야 코멘트 마지막 줄을 덮지 않는다. 바닥에
    // 고정하면 글자 중간에서 잘린다.
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text('저장'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('취소는 저장 없이 시트를 닫는다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await _pumpApp(tester, FakeDietRepository());
    await _startAnalyze(tester);
    await tester.pumpAndSettle();

    // 시트가 길어 버튼이 접힌 화면에서는 스크롤해야 닿는다.
    await tester.ensureVisible(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('저장'), findsNothing);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.text('open')),
    );
    expect(find.text(l.dietSaved), findsNothing);
  });
}
