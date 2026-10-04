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

    // 주간 리포트는 기본 켜짐이라(#3025) 끄는 방향으로 눌린다.
    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_weekly_report',
    );
    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();

    expect(repo.writes, <(String, bool)>[('notif_weekly_report', false)]);
  });

  testWidgets('저장에 실패하면 원래 값으로 되돌리고 알린다', (WidgetTester tester) async {
    // 끈 줄 알았는데 알림이 계속 오는 상태도, 그 반대도 나쁘다.
    final repo = _FakeRepository(failOnWrite: true);
    await _pump(tester, repository: repo);
    final index = kNotificationSettingItems.indexWhere(
      (NotificationSettingItem item) => item.key == 'notif_weekly_report',
    );

    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[index].value, isTrue);
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

    // 1) 켬 → 끔 (성공). 서버 값은 이제 false.
    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();
    // 2) 끔 → 켬 (실패). 되돌아갈 곳은 false 다.
    await tester.tap(find.byType(Switch).at(index));
    await tester.pumpAndSettle();

    expect(repo.writes, <(String, bool)>[('notif_weekly_report', false)]);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[index].value, isFalse);
  });

  testWidgets('데모는 기기 저장을 그대로 쓴다', (WidgetTester tester) async {
    // repository override 없이 — 데모 설정이 로컬 저장소를 고르는지 확인한다.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notif_trainer_message': false,
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
      (NotificationSettingItem item) => item.key == 'notif_trainer_message',
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

      expect(_switchValue(tester, 'notif_weekly_report'), isTrue);
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
      expect(repo.writes, <(String, bool)>[('notif_weekly_report', false)]);
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

  group('제어할 알림이 없는 스위치 (#2854)', () {
    testWidgets('식단 기록·AI 코칭 스위치가 없다', (WidgetTester tester) async {
      // 실서버에 이 두 알림을 만드는 곳이 없다 — 켜 두어도 아무것도 오지 않았다.
      await _pump(tester);

      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.text('식단 기록 알림'), findsNothing);
      expect(find.text('AI 코칭 조언'), findsNothing);
      expect(find.text('운동 루틴'), findsOneWidget);
      expect(find.text('트레이너 메시지'), findsOneWidget);
      expect(find.text('트레이너 주간 리포트'), findsOneWidget);
    });

    test('설정 항목은 서버가 실제로 만드는 알림의 키뿐이다', () {
      expect(
        kNotificationSettingItems.map((NotificationSettingItem i) => i.key),
        <String>[
          'notif_exercise_reminder',
          'notif_trainer_message',
          'notif_weekly_report',
        ],
      );
    });
  });

  group('스위치가 끄는 범위 (#3024·#3025)', () {
    Future<void> pumpIn(WidgetTester tester, Locale locale) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_demo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            notificationSettingsRepositoryProvider.overrideWithValue(
              _FakeRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NotificationSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('예전 라벨이 남아 있지 않다', (WidgetTester tester) async {
      // '운동 리마인더'는 PT 일정까지 끄는 것처럼 읽혔고, '주간 리포트'는
      // 포인트로 만드는 리포트와 이름이 같았다.
      await pumpIn(tester, const Locale('ko'));

      expect(find.text('운동 리마인더'), findsNothing);
      expect(find.text('주간 리포트'), findsNothing);
    });

    testWidgets('스위치마다 실제로 끄는 알림을 한 줄로 말한다', (WidgetTester tester) async {
      await pumpIn(tester, const Locale('ko'));

      expect(find.text('트레이너가 운동 루틴·프로그램을 보내면 알려요'), findsOneWidget);
      expect(find.text('트레이너가 대화로 보낸 메시지를 알려요'), findsOneWidget);
      expect(find.text('담당 트레이너가 주간 리포트를 보내면 알려요'), findsOneWidget);
    });

    testWidgets('끌 수 없는 알림을 목록 아래에 밝힌다', (WidgetTester tester) async {
      await pumpIn(tester, const Locale('ko'));

      final Finder note = find.byKey(
        const Key('notificationSettingsAlwaysSent'),
      );
      expect(note, findsOneWidget);
      expect(
        find.text('PT 일정 등록·변경·취소와 담당 트레이너 연결·해제 알림은 항상 보내요'),
        findsOneWidget,
      );
      // 안내는 스위치 목록 아래에 선다.
      final double lastSwitchY = tester.getCenter(find.byType(Switch).last).dy;
      expect(tester.getTopLeft(note).dy, greaterThan(lastSwitchY));
    });

    testWidgets('안내에는 스위치가 없다 — 끌 수 있는 항목은 세 개뿐', (WidgetTester tester) async {
      await pumpIn(tester, const Locale('ko'));

      expect(
        find.byType(Switch),
        findsNWidgets(kNotificationSettingItems.length),
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('notificationSettingsAlwaysSent')),
          matching: find.byType(Switch),
        ),
        findsNothing,
      );
    });

    testWidgets('영어 라벨·설명·안내', (WidgetTester tester) async {
      await pumpIn(tester, const Locale('en'));

      expect(find.text('Workout routines'), findsOneWidget);
      expect(find.text('Trainer message'), findsOneWidget);
      expect(find.text('Trainer weekly report'), findsOneWidget);
      expect(
        find.text('When your trainer sends a workout routine or program'),
        findsOneWidget,
      );
      expect(
        find.text('When your trainer sends you a chat message'),
        findsOneWidget,
      );
      expect(
        find.text('When your trainer sends your weekly report'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notificationSettingsAlwaysSent')),
        findsOneWidget,
      );
    });

    testWidgets('처음 들어오면 트레이너 주간 리포트가 켜져 있다', (WidgetTester tester) async {
      await pumpIn(tester, const Locale('ko'));

      for (final NotificationSettingItem item in kNotificationSettingItems) {
        expect(_switchValue(tester, item.key), isTrue, reason: item.key);
      }
    });
  });
}
