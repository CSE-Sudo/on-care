/// 회원이 낸 세 문항을 저장값에서 되읽는 규칙. (#2232)
///
/// 여기서 지키는 것은 하나다 — **회원이 하지 않은 말을 만들어 내지 않는다.**
/// 모르는 값을 `보통` 으로 접거나 반쯤 읽힌 답을 반쯤 그리면, 트레이너는
/// 그것을 회원의 말로 읽고 다음 주 처방을 거기에 맞춘다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';

final DateTime _week = DateTime(2026, 9, 14);

MemberWeeklyFeedback? _wire({
  String? condition = 'good',
  String? intensity = 'right',
  String painArea = '',
  String painOn = '',
  String note = '',
}) => MemberWeeklyFeedback.fromWire(
  weekStart: _week,
  condition: condition,
  intensity: intensity,
  painArea: painArea,
  painOn: painOn,
  note: note,
);

void main() {
  group('컨디션', () {
    test('저장값은 이름 그대로다', () {
      expect(WeekCondition.great.wire, 'great');
      expect(WeekCondition.bad.wire, 'bad');
    });

    test('모든 값이 스스로 되읽힌다 — 저장과 읽기가 갈라지지 않는다', () {
      for (final WeekCondition c in WeekCondition.values) {
        expect(WeekCondition.parse(c.wire), c);
      }
    });

    test('모르는 값은 null 이다 — 조용히 보통으로 접지 않는다', () {
      expect(WeekCondition.parse('meh'), isNull);
      expect(WeekCondition.parse(''), isNull);
      expect(WeekCondition.parse(null), isNull);
    });

    test('지쳤다·나빴다만 강도를 내리는 근거다', () {
      expect(WeekCondition.tired.needsAttention, isTrue);
      expect(WeekCondition.bad.needsAttention, isTrue);
      expect(WeekCondition.ok.needsAttention, isFalse);
      expect(WeekCondition.good.needsAttention, isFalse);
      expect(WeekCondition.great.needsAttention, isFalse);
    });

    test('나열 순서가 좋은 쪽에서 나쁜 쪽이다 — 화면이 이 순서로 줄을 세운다', () {
      expect(WeekCondition.values, <WeekCondition>[
        WeekCondition.great,
        WeekCondition.good,
        WeekCondition.ok,
        WeekCondition.tired,
        WeekCondition.bad,
      ]);
    });
  });

  group('강도', () {
    test('저장값은 snake_case 다', () {
      expect(WeekIntensity.tooEasy.wire, 'too_easy');
      expect(WeekIntensity.tooHard.wire, 'too_hard');
      expect(WeekIntensity.right.wire, 'right');
    });

    test('모든 값이 스스로 되읽힌다', () {
      for (final WeekIntensity i in WeekIntensity.values) {
        expect(WeekIntensity.parse(i.wire), i);
      }
    });

    test('dart 이름으로는 읽히지 않는다 — 서버가 쓰는 말만 받는다', () {
      expect(WeekIntensity.parse('tooEasy'), isNull);
    });

    test('양쪽 끝이 다음 주를 바꾼다 — 너무 쉬운 주도 고칠 주다', () {
      expect(WeekIntensity.tooEasy.needsAttention, isTrue);
      expect(WeekIntensity.tooHard.needsAttention, isTrue);
      expect(WeekIntensity.right.needsAttention, isFalse);
      expect(WeekIntensity.hard.needsAttention, isFalse);
    });
  });

  group('저장값 되읽기', () {
    test('둘 다 읽히면 답이 된다', () {
      final MemberWeeklyFeedback? f = _wire(
        condition: 'tired',
        intensity: 'too_hard',
      );

      expect(f, isNotNull);
      expect(f!.condition, WeekCondition.tired);
      expect(f.intensity, WeekIntensity.tooHard);
      expect(f.weekStart, _week);
    });

    test('컨디션이 안 읽히면 답이 아니다 — 반쪽을 그리면 나머지를 짐작하게 된다', () {
      expect(_wire(condition: null), isNull);
      expect(_wire(condition: 'meh'), isNull);
    });

    test('강도가 안 읽히면 답이 아니다', () {
      expect(_wire(intensity: null), isNull);
      expect(_wire(intensity: 'medium'), isNull);
    });

    test('아픈 곳의 앞뒤 공백은 떼고 읽는다', () {
      expect(_wire(painArea: '  오른 무릎 ')!.painArea, '오른 무릎');
    });

    test('공백만 적은 통증은 통증이 아니다', () {
      final MemberWeeklyFeedback f = _wire(painArea: '   ')!;

      expect(f.painArea, isEmpty);
      expect(f.hasPain, isFalse);
    });

    test('아픈 곳이 없으면 날짜도 버린다 — "(빈칸)이 아팠다" 를 그리지 않게', () {
      expect(_wire(painOn: '2026-09-17')!.painOn, isNull);
    });

    test('아픈 곳이 있으면 날짜를 함께 읽는다', () {
      final MemberWeeklyFeedback f = _wire(
        painArea: '허리',
        painOn: '2026-09-17',
      )!;

      expect(f.painOn, DateTime(2026, 9, 17));
    });

    test('날짜가 깨져 있어도 통증 자체는 남는다', () {
      final MemberWeeklyFeedback f = _wire(painArea: '허리', painOn: '언젠가')!;

      expect(f.hasPain, isTrue);
      expect(f.painOn, isNull);
    });

    test('한 줄 서술의 앞뒤 공백도 뗀다', () {
      expect(_wire(note: '  야근이 많았어요\n')!.note, '야근이 많았어요');
    });
  });

  group('확인 필요 판정', () {
    test('셋 다 무난하면 확인할 것이 없다', () {
      // 기본값이 `좋았어요 · 적당했어요 · 통증 없음` 이다.
      expect(_wire()!.needsAttention, isFalse);
    });

    test('컨디션 하나만 나빠도 확인이 필요하다', () {
      expect(_wire(condition: 'bad')!.needsAttention, isTrue);
    });

    test('강도 하나만 어긋나도 확인이 필요하다', () {
      expect(_wire(intensity: 'too_easy')!.needsAttention, isTrue);
    });

    test('통증만 있어도 확인이 필요하다 — 수치로는 보이지 않는 답이다', () {
      expect(_wire(painArea: '오른 무릎')!.needsAttention, isTrue);
    });
  });
}
