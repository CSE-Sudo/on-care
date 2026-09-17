/// 식단 저장 알림의 적립 표시와 MY 잔액 다시 읽기. (#1786)
///
/// 사진 분석으로 끼니가 저장되면 포인트를 받는다. 받은 만큼 저장 알림에
/// ★ +50P 가 붙고, 하루 한도를 넘어 0 이면 저장 알림만 뜬다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
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

/// 분석 결과에 정해 둔 적립을 싣는 대역.
class _AwardingDietRepository extends FakeDietRepository {
  _AwardingDietRepository(this.award);

  final PointsAward award;

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) async {
    final DietAnalysisResult r = await super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: idempotencyKey,
    );
    return DietAnalysisResult(
      entryId: r.entryId,
      foods: r.foods,
      totalCalories: r.totalCalories,
      totalSodiumMg: r.totalSodiumMg,
      totalSugarG: r.totalSugarG,
      coachComment: r.coachComment,
      totalCarbsG: r.totalCarbsG,
      totalProteinG: r.totalProteinG,
      totalFatG: r.totalFatG,
      points: award,
    );
  }
}

class _CountingHealthRepository implements MyHealthRepository {
  int calls = 0;

  @override
  Future<MyHealthState> fetchState() {
    calls++;
    return const MockMyHealthRepository().fetchState();
  }
}

final Finder _badge = find.byKey(const ValueKey<String>('appToastReward'));

void main() {
  late _CountingHealthRepository health;

  Future<void> saveMeal(WidgetTester tester, PointsAward award) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    health = _CountingHealthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
          dietRepositoryProvider.overrideWithValue(
            _AwardingDietRepository(award),
          ),
          myHealthRepositoryProvider.overrideWithValue(health),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              // MY 탭이 잔액을 보고 있는 상태.
              ref.watch(myHealthStateProvider);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showDietAddSheet(context),
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(health.calls, 1);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    // 시트가 길어 버튼이 접힌 화면에서는 스크롤해야 닿는다.
    await tester.ensureVisible(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pump();
    await tester.pump(OnCareMotion.toastEnter);
  }

  Future<void> dismissToast(WidgetTester tester) async {
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
  }

  testWidgets('적립을 받으면 저장 알림에 ★ +50P 가 붙고 MY 잔액을 다시 읽는다', (
    WidgetTester tester,
  ) async {
    await saveMeal(tester, const PointsAward(awarded: 50, balance: 1290));

    expect(find.text('식단이 저장되었어요'), findsOneWidget);
    expect(
      find.descendant(of: _badge, matching: find.text('+50P')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(health.calls, 2);

    await dismissToast(tester);
  });

  testWidgets('하루 한도를 넘어 0 이면 표시 없이 저장 알림만 뜬다', (WidgetTester tester) async {
    await saveMeal(tester, const PointsAward(awarded: 0, balance: 1390));

    expect(find.text('식단이 저장되었어요'), findsOneWidget);
    expect(_badge, findsNothing);

    await dismissToast(tester);
  });
}
