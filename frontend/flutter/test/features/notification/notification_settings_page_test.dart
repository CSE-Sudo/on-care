import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 데모/목 설정 — 화면이 기기 저장을 쓰는 쪽.
const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 저장 요청을 기록하고, 실패시킬 수도 있는 페이크.
class _FakeRepository implements NotificationSettingsRepository {
  _FakeRepository({
    Map<String, bool>? initial,
    this.failOnWrite = false,
    this.failFrom,
    this.failedFetches = 0,
  }) : _values =
           initial ??
           <String, bool>{
             for (final NotificationSettingItem item
                 in kNotificationSettingItems)
               item.key: item.fallback,
           };

  final Map<String, bool> _values;
  final bool failOnWrite;

  /// N번째 쓰기부터 실패시킨다(1부터). 성공 뒤 실패를 재현할 때 쓴다.
  final int? failFrom;
  final List<(String, bool)> writes = <(String, bool)>[];

  /// 앞에서부터 이 횟수만큼 조회를 실패시킨다 — 다시 시도를 재현한다.
  int failedFetches;
  int fetchCalls = 0;

  @override
  Future<Map<String, bool>> fetch() async {
    fetchCalls++;
    if (failedFetches > 0) {
      failedFetches--;
      throw StateError('fetch failed');
    }
    return Map<String, bool>.from(_values);
  }

  @override
  Future<void> setValue(String key, bool value) async {
    final int attempt = writes.length + 1;
    if (failOnWrite || (failFrom != null && attempt >= failFrom!)) {
      throw StateError('write failed');
    }
    writes.add((key, value));
    _values[key] = value;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  NotificationSettingsRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_demo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (repository != null)
          notificationSettingsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _indexOf(String key) => kNotificationSettingItems.indexWhere(
  (NotificationSettingItem item) => item.key == key,
);

bool _switchValue(WidgetTester tester, String key) => tester
    .widgetList<Switch>(find.byType(Switch))
    .toList()[_indexOf(key)]
    .value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('토글이 설정 항목 수만큼 그려진다', (WidgetTester tester) async {
    await _pump(tester);

    expect(
      find.byType(Switch),
      findsNWidgets(kNotificationSettingItems.length),
    );
  });

  testWidgets('저장된 값이 화면에 반영된다', (WidgetTester tester) async {
    final repo = _FakeRepository(
      initial: <String, bool>{
        for (final NotificationSettingItem item in kNotificationSettingItems)
          item.key: item.key == 'notif_trainer_message' ? false : item.fallback,
      },
    );

    await _pump(tester, repository: repo);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_trainer_message',
    );
    expect(switches[index].value, isFalse);
  });

  testWidgets('토글하면 저장소에 값을 넘긴다', (WidgetTester tester) async {
    final repo = _FakeRepository();
    await _pump(tester, repository: repo);

    // 주간 리포트는 기본 꺼짐이라 켜는 방향으로 눌린다.
    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_weekly_report',
    );
    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();

    expect(repo.writes, <(String, bool)>[('notif_weekly_report', true)]);
  });

  testWidgets('저장에 실패하면 원래 값으로 되돌리고 알린다', (WidgetTester tester) async {
    // 켜진 줄 알았는데 알림이 안 오는 상태가 가장 나쁘다.
    final repo = _FakeRepository(failOnWrite: true);
    await _pump(tester, repository: repo);
    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_weekly_report',
    );

    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[index].value, isFalse);
    expect(find.text('알림 설정을 저장하지 못했어요'), findsOneWidget);
  });

  testWidgets('성공한 뒤 실패하면 최초값이 아니라 직전 값으로 돌아간다', (WidgetTester tester) async {
    // 첫 저장이 성공하면 서버에는 그 값이 남는다. 다음 저장이 실패했다고 최초
    // 조회값으로 되돌리면 화면과 서버가 어긋난다(CodeRabbit 리뷰).
    final repo = _FakeRepository(failFrom: 2);
    await _pump(tester, repository: repo);
    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_weekly_report',
    );

    // 1) 끔 → 켬 (성공). 서버 값은 이제 true.
    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();
    // 2) 켬 → 끔 (실패). 되돌아갈 곳은 true 다.
    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();

    expect(repo.writes, <(String, bool)>[('notif_weekly_report', true)]);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[index].value, isTrue);
  });

  testWidgets('데모는 기기 저장을 그대로 쓴다', (WidgetTester tester) async {
    // repository override 없이 — 데모 설정이 로컬 저장소를 고르는지 확인한다.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notif_diet_log': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NotificationSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_diet_log',
    );
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).toList()[index].value,
      isFalse,
    );
  });

  group('다시 들어올 때 (#2851)', () {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

    Future<void> pumpHost(WidgetTester tester, _FakeRepository repo) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_demo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            notificationSettingsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester) async {
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
    }

    testWidgets('바꾼 값이 나갔다 들어와도 그대로 보인다', (WidgetTester tester) async {
      // 예전에는 화면 State 에만 남아, 다시 들어오면 최초 조회값(켜짐)이 보였다.
      // 회원이 다시 누르면 서버 값이 뒤집혔다.
      final repo = _FakeRepository();
      await pumpHost(tester, repo);
      await open(tester);
      expect(_switchValue(tester, 'notif_trainer_message'), isTrue);

      await tester.tap(
        find.byType(Switch).at(_indexOf('notif_trainer_message')),
      );
      await tester.pumpAndSettle();
      await close(tester);
      await open(tester);

      expect(_switchValue(tester, 'notif_trainer_message'), isFalse);
      expect(repo.writes, <(String, bool)>[('notif_trainer_message', false)]);
    });

    testWidgets('저장이 실패했으면 다시 들어와도 직전 값이다', (WidgetTester tester) async {
      final repo = _FakeRepository(failOnWrite: true);
      await pumpHost(tester, repo);
      await open(tester);

      await tester.tap(find.byType(Switch).at(_indexOf('notif_weekly_report')));
      await tester.pumpAndSettle();
      await close(tester);
      await open(tester);

      expect(_switchValue(tester, 'notif_weekly_report'), isFalse);
    });
  });

  group('조회 실패 (#2851)', () {
    testWidgets('실패 안내와 다시 시도가 보이고 토글은 쓸 수 있다', (WidgetTester tester) async {
      final repo = _FakeRepository(failedFetches: 1);
      await _pump(tester, repository: repo);

      expect(
        find.byKey(const Key('notificationSettingsLoadFailed')),
        findsOneWidget,
      );
      expect(find.text('알림 설정을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      // 끌 방법이 사라지면 안 된다.
      expect(
        find.byType(Switch),
        findsNWidgets(kNotificationSettingItems.length),
      );
      await tester.tap(find.byType(Switch).at(_indexOf('notif_weekly_report')));
      await tester.pumpAndSettle();
      expect(repo.writes, <(String, bool)>[('notif_weekly_report', true)]);
    });

    testWidgets('다시 시도하면 서버 값을 읽고 안내가 사라진다', (WidgetTester tester) async {
      final repo = _FakeRepository(
        initial: <String, bool>{
          for (final NotificationSettingItem item in kNotificationSettingItems)
            item.key: item.key == 'notif_trainer_message'
                ? false
                : item.fallback,
        },
        failedFetches: 1,
      );
      await _pump(tester, repository: repo);
      // 실패한 동안은 기본값(켜짐)이다.
      expect(_switchValue(tester, 'notif_trainer_message'), isTrue);

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notificationSettingsLoadFailed')),
        findsNothing,
      );
      expect(_switchValue(tester, 'notif_trainer_message'), isFalse);
      expect(repo.fetchCalls, 2);
    });

    testWidgets('조회에 성공하면 안내가 없다', (WidgetTester tester) async {
      await _pump(tester, repository: _FakeRepository());

      expect(
        find.byKey(const Key('notificationSettingsLoadFailed')),
        findsNothing,
      );
    });
  });
}
