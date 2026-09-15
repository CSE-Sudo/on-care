import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/health_focus.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';

/// 트레이너 웹의 회원 목표 = 회원 건강 목표. (#1818)
void main() {
  group('어휘', () {
    // 두 앱과 서버는 패키지가 달라 상수를 나눠 가질 수 없다. 한쪽만 고치면 회원이
    // 고른 목표를 트레이너 화면이 모르는 글로 보여 주므로, 세 파일을 직접 대조한다.
    test('회원앱·서버와 같은 목록·순서·최대 개수다', () {
      final String member = File(
        '../flutter/lib/features/account/domain/entities/health_focus.dart',
      ).readAsStringSync();
      final String server = File(
        '../../backend/app/services/health_focus.py',
      ).readAsStringSync();

      final List<String> memberValues = RegExp(
        r"const String kHealthFocus\w+ = '([^']+)';",
      ).allMatches(member).map((RegExpMatch m) => m.group(1)!).toList();
      final List<String> serverValues = RegExp(
        r'^FOCUS_(?!LABEL)\w+ = "([^"]+)"$',
        multiLine: true,
      ).allMatches(server).map((RegExpMatch m) => m.group(1)!).toList();

      expect(memberValues, kHealthFocusOptions);
      expect(serverValues, kHealthFocusOptions);
      expect(
        member,
        contains(
          'const int kHealthFocusMaxSelected = $kHealthFocusMaxSelected;',
        ),
      );
      expect(server, contains('MAX_FOCUS = $kHealthFocusMaxSelected'));
    });

    test('옛 질환 이름을 정리하고 두 개까지만 읽는다', () {
      expect(parseHealthFocus('고혈압, 당뇨 전단계'), <String>{
        kHealthFocusBloodPressure,
      });
      expect(parseHealthFocus('재활 · 체중 감량 · 근력 향상'), <String>{
        kHealthFocusWeightLoss,
        kHealthFocusStrength,
      });
      expect(healthFocusNotes('혈압 관리, 무릎 통증'), '무릎 통증');
      expect(
        mergeHealthFocus('고혈압, 무릎 통증', <String>{kHealthFocusRehab}),
        '재활, 무릎 통증',
      );
      expect(healthFocusGoal('혈압 관리, 체중 감량, 무릎 통증'), '체중 감량 · 혈압 관리');
      expect(
        canPickHealthFocus(<String>{
          kHealthFocusRehab,
          kHealthFocusPosture,
        }, kHealthFocusFitness),
        isFalse,
      );
    });
  });

  group('화면 문구', () {
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    test('로스터 목표를 로케일 문구로 옮기고 모르는 글은 그대로 둔다', () {
      expect(healthFocusGoalLabel(ko, '체중 감량 · 혈압 관리'), '체중 감량 · 혈압 관리');
      expect(
        healthFocusGoalLabel(en, '체중 감량 · 혈압 관리'),
        'Weight loss · Blood pressure care',
      );
      expect(healthFocusGoalLabel(en, '마라톤 완주 준비'), '마라톤 완주 준비');
      expect(healthFocusGoalLabel(en, ''), '');
    });

    test('모든 목표에 영어 문구가 있고 한글이 없다', () {
      for (final String option in kHealthFocusOptions) {
        expect(healthFocusLabel(ko, option), option);
        expect(
          healthFocusLabel(en, option),
          isNot(matches(RegExp('[가-힣]'))),
          reason: option,
        );
      }
      expect(en.memberHealthFocus, isNot(matches(RegExp('[가-힣]'))));
    });
  });

  group('데모 로스터', () {
    late AppDatabase db;
    late DriftClientRepository repository;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
      repository = DriftClientRepository(db);
    });
    tearDown(() => db.close());

    test('데모 회원 목표는 모두 건강 목표 두 개 이하이고 여덟 목표가 다 나온다', () async {
      final clients = await repository.watchClients().first;
      final Set<String> seen = <String>{};
      for (final client in clients) {
        final List<String> parts = client.goal.isEmpty
            ? const <String>[]
            : client.goal.split(kHealthFocusLabelSeparator);
        expect(
          parts.length,
          lessThanOrEqualTo(kHealthFocusMaxSelected),
          reason: client.name,
        );
        expect(
          parts.every(kHealthFocusOptions.contains),
          isTrue,
          reason: client.goal,
        );
        seen.addAll(parts);
      }
      expect(seen, kHealthFocusOptions.toSet());
    });

    test('트레이너가 목표를 고치면 로스터 목표와 건강 프로필이 함께 바뀐다', () async {
      final first = (await repository.watchClients().first).first;
      final before = await repository.fetchHealthProfile(first.id);
      expect(parseHealthFocus(before.conditions), parseHealthFocus(first.goal));

      await repository.updateHealthProfile(first.id, <String, Object?>{
        'conditions': '당뇨, 재활, 무릎 통증',
      });

      final after = (await repository.watchClients().first).firstWhere(
        (c) => c.id == first.id,
      );
      expect(after.goal, '재활');
      expect(
        (await repository.fetchHealthProfile(first.id)).conditions,
        '재활, 무릎 통증',
      );
    });
  });
}
