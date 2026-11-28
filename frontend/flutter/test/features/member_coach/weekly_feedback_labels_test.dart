/// 주간 피드백 답을 되읽어 주는 말. (#2232)
///
/// 회원이 고른 답은 **고른 그 문장으로** 돌아와야 한다. 다섯 단계 컨디션과
/// 네 단계 강도가 서로 다른 문장인지를 잰다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/weekly_feedback_labels.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';

final AppLocalizations _ko = AppLocalizationsKo();
final RegExp _hangul = RegExp(r'[가-힣]');

void main() {
  group('컨디션', () {
    test('다섯 단계가 모두 있다', () {
      expect(WeekCondition.values, hasLength(5));
    });

    test('단계마다 서로 다른 비어 있지 않은 문장', () {
      final List<String> labels = <String>[
        for (final WeekCondition c in WeekCondition.values)
          weekConditionLabel(_ko, c),
      ];
      expect(labels.every((String s) => s.trim().isNotEmpty), isTrue);
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('문장은 한글이다', () {
      for (final WeekCondition c in WeekCondition.values) {
        expect(
          _hangul.hasMatch(weekConditionLabel(_ko, c)),
          isTrue,
          reason: c.name,
        );
      }
    });

    test('단계마다 이모지가 서로 다르다', () {
      final Set<String> emojis = <String>{
        for (final WeekCondition c in WeekCondition.values) c.emoji,
      };
      expect(emojis, hasLength(WeekCondition.values.length));
      expect(emojis.every((String e) => e.isNotEmpty), isTrue);
    });

    test('서버 값에서 되읽으면 같은 단계다', () {
      for (final WeekCondition c in WeekCondition.values) {
        expect(WeekCondition.parse(c.name), c);
      }
      expect(WeekCondition.parse(null), isNull);
      expect(WeekCondition.parse('unknown'), isNull);
    });
  });

  group('강도 체감', () {
    test('단계마다 서로 다른 비어 있지 않은 문장', () {
      final List<String> labels = <String>[
        for (final WeekIntensity i in WeekIntensity.values)
          weekIntensityLabel(_ko, i),
      ];
      expect(labels.every((String s) => s.trim().isNotEmpty), isTrue);
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('서버 값에서 되읽으면 같은 단계다', () {
      for (final WeekIntensity i in WeekIntensity.values) {
        expect(WeekIntensity.parse(i.wire), i);
      }
      expect(WeekIntensity.parse(null), isNull);
      expect(WeekIntensity.parse(''), isNull);
    });
  });

  group('주 범위', () {
    test('시작과 끝 날짜를 모두 말한다', () {
      final String label = weekRangeLabel(_ko, DateTime(2026, 9, 14));
      expect(label, contains('9'));
      expect(label, contains('14'));
      expect(label, contains('20'));
    });

    test('달이 바뀌는 주는 끝 날짜의 달을 따른다', () {
      final String ko = weekRangeLabel(_ko, DateTime(2026, 9, 28));
      // 9/28 ~ 10/4
      expect(ko, contains('10'));
      expect(ko, contains('4'));
    });

    test('해가 바뀌는 주도 선다', () {
      final String label = weekRangeLabel(_ko, DateTime(2026, 12, 28));
      expect(label, contains('12'));
      expect(label, contains('1'));
      expect(label, contains('3'));
    });
  });
}
