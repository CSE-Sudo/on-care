import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 식단 탭 오류 상태의 설명이 원인을 말한다. (#3140)
///
/// 하루 식단을 못 읽으면 제목(`식단을 불러오지 못했어요`)만 있었다. 연결이
/// 끊긴 것인지 서버가 잠시 내려간 것인지 알 수 없어, 회원은 다시 시도가 의미
/// 있는지 판단하지 못했다.
class _FailingDietRepository extends FakeDietRepository {
  _FailingDietRepository(this.error);

  final Object error;
  int calls = 0;

  @override
  Future<DietDay> fetchToday() async {
    calls++;
    throw error;
  }

  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    calls++;
    throw error;
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _FailingDietRepository repo, {
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DietRecordPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(DietRecordPage)));
}

void main() {
  testWidgets('연결이 끊기면 연결 확인 안내가 선다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      _FailingDietRepository(const NetworkError()),
    );

    expect(find.text(l.dietLoadError), findsWidgets);
    expect(find.text(l.errorNetwork), findsWidgets);
    expect(find.text(l.errorServer), findsNothing);
  });

  testWidgets('서버 5xx 면 일시 문제 안내가 선다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      _FailingDietRepository(const ServerError(statusCode: 502)),
    );

    expect(find.text(l.dietLoadError), findsWidgets);
    expect(find.text(l.errorServer), findsWidgets);
    expect(find.text(l.errorNetwork), findsNothing);
  });

  testWidgets('403 이면 권한·동의 안내가 선다 — 다시 로그인으로 보내지 않는다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await _pump(
      tester,
      _FailingDietRepository(const ForbiddenError()),
    );

    expect(find.text(l.errorForbidden), findsWidgets);
    expect(find.text(l.authSessionExpired), findsNothing);
  });

  testWidgets('영어 화면은 영어 원인 문구다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      _FailingDietRepository(const NetworkError()),
      locale: const Locale('en'),
    );

    expect(find.text(l.errorNetwork), findsWidgets);
  });

  testWidgets('다시 시도는 지금처럼 다시 받는다', (WidgetTester tester) async {
    final _FailingDietRepository repo = _FailingDietRepository(
      const NetworkError(),
    );
    final AppLocalizations l = await _pump(tester, repo);
    final int before = repo.calls;

    await tester.tap(find.text(l.actionRetry).first);
    await tester.pumpAndSettle();

    expect(repo.calls, greaterThan(before));
  });
}
