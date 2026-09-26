/// 주간 피드백의 규칙 — 화면 없이 셀 수 있는 것들. (#2232)
///
/// 여기서 지키는 것은 두 가지다. 하나는 **저장값과 앱이 같은 말을 쓰는가** —
/// 서버가 쓰는 `too_easy` 를 앱이 `tooEasy` 로 보내면 답이 조용히 사라진다.
/// 다른 하나는 **언제 묻는가** — 일요일·월요일 규칙은 화면 어디에도 쓰여 있지
/// 않아, 틀려도 아무도 모른 채 한 주가 빈다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';

import '../../helpers/fixed_clock.dart';

/// 2026-09-14 은 월요일이다 — 이 파일의 모든 주는 여기서 센다.
final DateTime _monday = DateTime(2026, 9, 14);

MemberWeeklyFeedback _submitted({
  WeekCondition condition = WeekCondition.good,
  WeekIntensity intensity = WeekIntensity.right,
  String painArea = '',
  DateTime? painOn,
  String note = '',
}) => MemberWeeklyFeedback(
  weekStart: _monday,
  submitted: true,
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

    test('저장값에서 되읽는다', () {
      for (final WeekCondition value in WeekCondition.values) {
        expect(WeekCondition.parse(value.wire), value);
      }
    });

    test('모르는 값은 null 이다 — 보통으로 접지 않는다', () {
      // 조용히 `보통` 으로 접으면 트레이너가 회원이 하지 않은 말을 읽는다.
      expect(WeekCondition.parse('sleepy'), isNull);
      expect(WeekCondition.parse(''), isNull);
      expect(WeekCondition.parse(null), isNull);
    });

    test('눈여겨봐야 하는 답은 지침·나쁨 둘뿐이다', () {
      expect(WeekCondition.tired.needsAttention, isTrue);
      expect(WeekCondition.bad.needsAttention, isTrue);
      expect(WeekCondition.ok.needsAttention, isFalse);
      expect(WeekCondition.good.needsAttention, isFalse);
      expect(WeekCondition.great.needsAttention, isFalse);
    });

    test('차례는 좋은 쪽에서 나쁜 쪽이다 — 화면이 이 순서로 줄을 세운다', () {
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
      expect(WeekIntensity.hard.wire, 'hard');
    });

    test('저장값에서 되읽는다', () {
      for (final WeekIntensity value in WeekIntensity.values) {
        expect(WeekIntensity.parse(value.wire), value);
      }
    });

    test('dart 이름으로는 읽히지 않는다 — 앱과 서버가 다른 말을 쓰면 답이 사라진다', () {
      expect(WeekIntensity.parse('tooEasy'), isNull);
      expect(WeekIntensity.parse('tooHard'), isNull);
    });

    test('눈여겨봐야 하는 답은 양쪽 끝이다', () {
      // `힘들었나` 만 물으면 너무 쉬웠던 주가 괜찮음으로 접혀, 다음 주에도
      // 같은 무게가 나간다.
      expect(WeekIntensity.tooEasy.needsAttention, isTrue);
      expect(WeekIntensity.tooHard.needsAttention, isTrue);
      expect(WeekIntensity.right.needsAttention, isFalse);
      expect(WeekIntensity.hard.needsAttention, isFalse);
    });
  });

  group('한 주치 답', () {
    test('안 낸 주는 두 문항이 비어 있다', () {
      final MemberWeeklyFeedback empty = MemberWeeklyFeedback.empty(_monday);

      expect(empty.submitted, isFalse);
      expect(empty.condition, isNull);
      expect(empty.intensity, isNull);
      expect(empty.weekStart, _monday);
    });

    test('두 문항을 다 골라야 보낼 수 있다', () {
      expect(
        MemberWeeklyFeedback(
          weekStart: _monday,
          condition: WeekCondition.ok,
        ).isComplete,
        isFalse,
      );
      expect(
        MemberWeeklyFeedback(
          weekStart: _monday,
          intensity: WeekIntensity.hard,
        ).isComplete,
        isFalse,
      );
      expect(_submitted().isComplete, isTrue);
    });

    test('아픈 곳을 적었으면 통증이 있는 주다', () {
      expect(_submitted(painArea: '오른 무릎').hasPain, isTrue);
      expect(_submitted().hasPain, isFalse);
    });

    test('셋 중 하나만 걸려도 눈여겨볼 주다', () {
      expect(_submitted(condition: WeekCondition.tired).needsAttention, isTrue);
      expect(
        _submitted(intensity: WeekIntensity.tooHard).needsAttention,
        isTrue,
      );
      expect(_submitted(painArea: '허리').needsAttention, isTrue);
    });

    test('셋 다 편안한 주는 눈여겨볼 것이 없다', () {
      expect(_submitted().needsAttention, isFalse);
    });

    test('안 낸 주는 결코 눈여겨볼 주가 아니다', () {
      // 답하지 않은 것은 `괜찮다` 도 `나쁘다` 도 아니다.
      expect(MemberWeeklyFeedback.empty(_monday).needsAttention, isFalse);
    });

    test('고른 값 하나만 바꿔 다시 들 수 있다', () {
      final MemberWeeklyFeedback before = _submitted();
      final MemberWeeklyFeedback after = before.copyWith(
        condition: WeekCondition.bad,
      );

      expect(after.condition, WeekCondition.bad);
      expect(after.intensity, before.intensity);
      expect(after.weekStart, before.weekStart);
    });

    test('아픈 날은 따로 지운다 — null 은 안 바꿈이라서', () {
      final MemberWeeklyFeedback before = _submitted(
        painArea: '오른 무릎',
        painOn: DateTime(2026, 9, 17),
      );

      expect(before.copyWith(painArea: '').painOn, isNotNull);
      expect(before.copyWith(painArea: '', clearPainOn: true).painOn, isNull);
    });
  });

  group('언제 묻는가', () {
    test('일요일에는 오늘로 끝나는 주를 묻는다', () {
      // 2026-09-20 은 일요일이고, 그 주는 9/14 에 시작한다.
      expect(askableWeek(DateTime(2026, 9, 20, 21)), _monday);
    });

    test('월요일에는 어제 끝난 지난 주를 묻는다', () {
      // 일요일에 앱을 안 켠 회원의 한 주가 영영 비지 않게 한 번 더 묻되,
      // 오늘이 속한 주는 아직 하루도 지나지 않았다.
      expect(askableWeek(DateTime(2026, 9, 21, 7)), _monday);
    });

    test('그 밖의 요일에는 묻지 않는다', () {
      for (int day = 15; day <= 19; day++) {
        expect(
          askableWeek(DateTime(2026, 9, day, 12)),
          isNull,
          reason: '9월 $day일',
        );
      }
    });

    test('묻는 주는 언제나 월요일이다', () {
      expect(askableWeek(DateTime(2026, 9, 20))!.weekday, DateTime.monday);
      expect(askableWeek(DateTime(2026, 9, 21))!.weekday, DateTime.monday);
    });

    test('오늘을 주지 않으면 KST 로 읽는다', () {
      useFixedKstDate(DateTime(2026, 9, 20, 23, 30));

      expect(askableWeek(), _monday);
    });

    test('시각은 답을 바꾸지 않는다 — 날짜만 본다', () {
      expect(
        askableWeek(DateTime(2026, 9, 20, 0, 1)),
        askableWeek(DateTime(2026, 9, 20, 23, 59)),
      );
    });
  });

  group('직접 열었을 때 묻는 주', () {
    test('주중에는 방금 끝난 지난 주다', () {
      // 수요일에 `한 주 컨디션` 을 물으면, 아직 오지 않은 나흘에 대한 답을
      // 받아 트레이너에게 넘기게 된다.
      expect(manualFeedbackWeek(DateTime(2026, 9, 23)), DateTime(2026, 9, 14));
    });

    test('월요일에도 지난 주다 — 오늘 주는 하루도 지나지 않았다', () {
      expect(manualFeedbackWeek(DateTime(2026, 9, 21)), _monday);
    });

    test('일요일만은 오늘로 끝나는 주다', () {
      expect(manualFeedbackWeek(DateTime(2026, 9, 20)), _monday);
    });

    test('언제 열어도 월요일을 돌려준다', () {
      for (int day = 14; day <= 20; day++) {
        expect(
          manualFeedbackWeek(DateTime(2026, 9, day)).weekday,
          DateTime.monday,
          reason: '9월 $day일',
        );
      }
    });

    test('물을 날에는 자동 물음과 같은 주를 가리킨다', () {
      // 일요일·월요일에 두 길(자동 물음, 직접 열기)이 다른 주를 가리키면
      // 회원이 같은 주에 두 번 답하거나 한 주가 빈다.
      for (final DateTime day in <DateTime>[
        DateTime(2026, 9, 20),
        DateTime(2026, 9, 21),
      ]) {
        expect(manualFeedbackWeek(day), askableWeek(day), reason: '$day');
      }
    });

    test('오늘을 주지 않으면 KST 로 읽는다', () {
      useFixedKstDate(DateTime(2026, 9, 23, 9));

      expect(manualFeedbackWeek(), DateTime(2026, 9, 14));
    });
  });
}
