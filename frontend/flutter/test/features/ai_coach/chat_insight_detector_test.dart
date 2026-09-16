import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/ai_coach/domain/chat_insight_detector.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';

/// AI 챗봇 통증·부정적 반응 감지(#1824). 서버 `test_ai_coach_insights.py`, 트레이너
/// 웹 채팅 감지와 같은 사례를 못 박는다 — 한쪽만 고치면 여기서 깨진다.
void main() {
  group('감지한다', () {
    for (final (String text, ChatInsightKind kind, String? part)
        in <(String, ChatInsightKind, String?)>[
          ('무릎이 아파요', ChatInsightKind.discomfort, '무릎'),
          ('어제부터 허리가 뻐근해요', ChatInsightKind.discomfort, '허리'),
          ('발목이 좀 부었어요', ChatInsightKind.discomfort, '발목'),
          ('목이 당겨요', ChatInsightKind.discomfort, '목'),
          ('손목 통증이 있어요', ChatInsightKind.discomfort, '손목'),
          ('어깨가 불편해요', ChatInsightKind.discomfort, '어깨'),
          ('그냥 좀 아팠어요', ChatInsightKind.discomfort, null),
          ('My lower back aches', ChatInsightKind.discomfort, 'Back'),
          ('my knee hurts', ChatInsightKind.discomfort, 'Knee'),
          ('오늘은 너무 힘들어서 못 했어요', ChatInsightKind.negativeFeedback, null),
          ('운동 포기하고 싶어요', ChatInsightKind.negativeFeedback, null),
          ('I gave up today', ChatInsightKind.negativeFeedback, null),
        ]) {
      test(text, () {
        expect(
          detectChatInsight(text),
          ChatInsight(kind: kind, bodyPart: part),
        );
      });
    }
  });

  group('비슷한 낱말은 감지하지 않는다', () {
    for (final String text in <String>[
      '목요일에 운동할게요',
      '이번 달 목표를 세웠어요',
      '골목에서 걸었어요',
      '아파트 계단을 올랐어요',
      '아프리카 여행 가요',
      '마무리 스트레칭까지 했어요',
      '허리띠를 샀어요',
      "I'm back at the gym",
      '오늘 샐러드 먹었어요',
      '',
    ]) {
      test(text.isEmpty ? '(빈 문장)' : text, () {
        expect(detectChatInsight(text), isNull);
      });
    }
  });

  test('한 문장에 둘 다 있으면 통증이 먼저다', () {
    expect(
      detectChatInsight('무릎이 아파서 못 했어요'),
      const ChatInsight(kind: ChatInsightKind.discomfort, bodyPart: '무릎'),
    );
  });

  test('기록 기간은 작성일 기준 30일이다', () {
    final DateTime now = DateTime(2026, 9, 16, 12);
    expect(
      isWithinInsightWindow(now.subtract(const Duration(days: 29)), now),
      isTrue,
    );
    expect(
      isWithinInsightWindow(now.subtract(const Duration(days: 30)), now),
      isTrue,
    );
    expect(
      isWithinInsightWindow(now.subtract(const Duration(days: 31)), now),
      isFalse,
    );
  });
}
