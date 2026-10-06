/// 알림 설정 — 서버 값을 받기 전·받지 못했을 때. (#2883)
///
/// 예전에는 기본값(모두 켬)에서 출발해, 받기 전·실패 뒤에도 스위치가 켬으로
/// 보이고 눌렸다. 그 사이 누른 스위치는 기본값이 섞인 전체 상태를 저장해, 꺼
/// 둔 새 메시지 알림을 켬으로 덮어썼다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings_repository.dart';

import '../../helpers/pump_app.dart';

/// 불러오기를 붙잡아 두거나 실패시킬 수 있는 저장소.
class _GatedRepository implements TrainerSettingsRepository {
  final List<Completer<TrainerSettings>> loads = <Completer<TrainerSettings>>[];
  final List<TrainerSettings> saved = <TrainerSettings>[];

  @override
  Future<TrainerSettings> load() {
    final Completer<TrainerSettings> c = Completer<TrainerSettings>();
    loads.add(c);
    return c.future;
  }

  @override
  Future<TrainerSettings> save(TrainerSettings settings) async {
    saved.add(settings);
    return settings;
  }
}

const List<String> _switchKeys = <String>[
  'new-message',
  'consultation',
  'reservation',
  'member-updates',
];

Switch _switch(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(ValueKey<String>('my-notif-$key')));

/// 화면의 숫자만 있는 글자 — 사이드바 배지.
List<String> _badgeNumbers(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data)
    .whereType<String>()
    .where((String d) => RegExp(r'^\d+$').hasMatch(d))
    .toList();

void main() {
  Future<_GatedRepository> openNotifications(WidgetTester tester) async {
    final _GatedRepository repo = _GatedRepository();
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.mySection('notifications'),
      extraOverrides: <Override>[
        trainerSettingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await settle(tester);
    return repo;
  }

  group('알림 설정 화면', () {
    testWidgets('받기 전에는 모든 스위치가 꺼진 채 막히고 불러오는 중이라고 적는다', (tester) async {
      final _GatedRepository repo = await openNotifications(tester);

      for (final String key in _switchKeys) {
        expect(_switch(tester, key).value, isFalse, reason: key);
        expect(_switch(tester, key).onChanged, isNull, reason: key);
      }
      expect(
        find.byKey(const ValueKey<String>('my-notif-loading')),
        findsOneWidget,
      );
      expect(find.text('알림 설정을 불러오는 중이에요'), findsOneWidget);

      // 눌러도 아무것도 저장하지 않는다.
      await tester.tap(
        find.byKey(const ValueKey<String>('my-notif-reservation')),
      );
      await settle(tester);
      expect(repo.saved, isEmpty);
    });

    testWidgets('받으면 서버 값대로 그리고 켜고 끌 수 있다', (tester) async {
      final _GatedRepository repo = await openNotifications(tester);
      repo.loads.single.complete(
        const TrainerSettings(newMessageAlerts: false),
      );
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('my-notif-loading')),
        findsNothing,
      );
      expect(_switch(tester, 'new-message').value, isFalse);
      expect(_switch(tester, 'new-message').onChanged, isNotNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('my-notif-reservation')),
      );
      await settle(tester);
      // 꺼 둔 새 메시지 알림은 그대로 꺼진 채 저장된다.
      expect(repo.saved.single.newMessageAlerts, isFalse);
      expect(repo.saved.single.reservationAlerts, isFalse);
    });

    testWidgets('불러오기에 실패하면 실패 안내와 다시 시도를 두고 스위치를 막는다', (tester) async {
      final _GatedRepository repo = await openNotifications(tester);
      repo.loads.single.completeError(const NetworkError(message: 'offline'));
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('my-notif-load-failed')),
        findsOneWidget,
      );
      expect(find.text('알림 설정을 불러오지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      for (final String key in _switchKeys) {
        expect(_switch(tester, key).value, isFalse, reason: key);
        expect(_switch(tester, key).onChanged, isNull, reason: key);
      }

      await tester.tap(find.byKey(const ValueKey<String>('my-notif-retry')));
      await settle(tester);
      expect(repo.loads, hasLength(2));
      expect(
        find.byKey(const ValueKey<String>('my-notif-loading')),
        findsOneWidget,
      );

      repo.loads.last.complete(const TrainerSettings());
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('my-notif-load-failed')),
        findsNothing,
      );
      expect(_switch(tester, 'new-message').value, isTrue);
      expect(_switch(tester, 'new-message').onChanged, isNotNull);
      expect(repo.saved, isEmpty);
    });

    testWidgets('서버가 모르는 항목은 받은 뒤에도 막혀 있다', (tester) async {
      final _GatedRepository repo = await openNotifications(tester);
      repo.loads.single.complete(
        trainerSettingsFromJson(<String, dynamic>{'notify_new_message': true}),
      );
      await settle(tester);

      expect(_switch(tester, 'new-message').onChanged, isNotNull);
      for (final String key in <String>[
        'consultation',
        'reservation',
        'member-updates',
      ]) {
        expect(_switch(tester, key).onChanged, isNull, reason: key);
      }
    });
  });

  group('사이드바 미읽음 배지', () {
    testWidgets('받기 전에도, 받은 값이 꺼짐이어도 그대로 보인다(#2420)', (tester) async {
      await withWideSurface(tester, () async {
        final _GatedRepository repo = _GatedRepository();
        final ProviderContainer container = await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.dashboard,
          extraOverrides: <Override>[
            trainerSettingsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        // 사이드바는 설정을 읽지 않는다 — 설정 화면처럼 다른 곳이 불러오는
        // 중이어도, 받은 값이 꺼짐이어도 배지가 그대로인지 본다.
        container.listen(trainerSettingsProvider, (_, _) {});
        await settle(tester);
        final List<String> before = _badgeNumbers(tester);
        expect(before, isNotEmpty, reason: '시드의 읽지 않은 대화 배지');

        repo.loads.single.complete(
          const TrainerSettings(newMessageAlerts: false),
        );
        await settle(tester);

        expect(_badgeNumbers(tester), before);
      });
    });
  });
}
