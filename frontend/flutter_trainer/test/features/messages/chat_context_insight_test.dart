import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/messages/domain/chat_context_insight.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

void main() {
  const detector = ChatContextInsightDetector();
  final now = DateTime(2026, 8, 14);

  ClientChatMessage message(
    String body, {
    ChatSender sender = ChatSender.client,
  }) {
    return ClientChatMessage(
      id: 'message-1',
      sender: sender,
      body: body,
      timeLabel: '18:16',
      createdAt: now,
    );
  }

  test('detects a downplayed discomfort report and its body part', () {
    final insight = detector.detect(message('무릎이 가볍게 당기긴 했는데 괜찮아요'));

    expect(insight?.kind, ChatInsightKind.discomfort);
    expect(insight?.bodyPart, ChatBodyPart.knee);
  });

  test('detects negative workout feedback', () {
    final insight = detector.detect(message('이번 주 일이 너무 많아서 운동을 못 갔어요'));

    expect(insight?.kind, ChatInsightKind.negativeFeedback);
  });

  test('does not flag a trainer message', () {
    final insight = detector.detect(
      message('무릎이 불편한지 확인해 보세요', sender: ChatSender.trainer),
    );

    expect(insight, isNull);
  });

  group('body part matching stops at word boundaries', () {
    test('a weekday is not the neck', () {
      final insight = detector.detect(message('목요일에 무리했더니 아직 아프네요'));

      expect(insight?.kind, ChatInsightKind.discomfort);
      expect(insight?.bodyPart, isNull);
    });

    test('a goal is not the neck', () {
      final insight = detector.detect(message('이번 주 목표를 못 했어요'));

      expect(insight?.kind, ChatInsightKind.negativeFeedback);
      expect(insight?.bodyPart, isNull);
    });

    test('a scarf is not the neck', () {
      final insight = detector.detect(message('목도리를 두르니 좀 불편해요'));

      expect(insight?.bodyPart, isNull);
    });

    test('the neck itself is still matched', () {
      final insight = detector.detect(message('목이 뻐근해요'));

      expect(insight?.kind, ChatInsightKind.discomfort);
      expect(insight?.bodyPart, ChatBodyPart.neck);
    });

    test('the neck is matched with a particle attached', () {
      expect(
        detector.detect(message('목도 좀 아프네요'))?.bodyPart,
        ChatBodyPart.neck,
      );
    });

    test('ankle and wrist win over the neck regardless of rule order', () {
      expect(
        detector.detect(message('발목이 아프네요'))?.bodyPart,
        ChatBodyPart.ankle,
      );
      expect(
        detector.detect(message('손목이 불편해요'))?.bodyPart,
        ChatBodyPart.wrist,
      );
    });

    test('a wristwatch is not the wrist', () {
      expect(detector.detect(message('손목시계가 불편해요'))?.bodyPart, isNull);
    });
  });

  group('통증어·부정어도 낱말 경계에서 끊는다 (#975)', () {
    test('마무리 운동 보고는 아무 신호도 만들지 않는다', () {
      // 프로그램이 준비운동·본운동·마무리로 나뉘어 있어(#934) `마무리` 는 이
      // 대화에서 흔한 말이다. 잘 마쳤다는 보고가 경고 배너로 뜨면 안 된다.
      expect(detector.detect(message('마무리 운동까지 다 했어요')), isNull);
    });

    test('아무리 해도 라는 말이 무리로 읽히지 않는다', () {
      expect(detector.detect(message('아무리 해도 재밌네요')), isNull);
    });

    test('무리했다는 보고는 그대로 잡는다', () {
      expect(
        detector.detect(message('어제 좀 무리했어요'))?.kind,
        ChatInsightKind.negativeFeedback,
      );
    });

    test('아프리카는 통증이 아니다', () {
      expect(detector.detect(message('아프리카 다큐 보면서 걸었어요')), isNull);
    });

    test('아파트는 통증이 아니다', () {
      expect(detector.detect(message('아파트 계단으로 올라갔어요')), isNull);
    });

    test('연못은 못 갔다는 말이 아니다', () {
      expect(detector.detect(message('연못 근처를 한 바퀴 걸었어요')), isNull);
    });

    test('가장 흔한 통증 활용형을 모두 잡는다', () {
      // 어간 하나만 두면 `아프네요` 는 잡으면서 `아파요` 를 지나친다.
      for (final (String body, ChatBodyPart? part) in <(String, ChatBodyPart?)>[
        ('무릎이 아파요', ChatBodyPart.knee),
        ('어제부터 아팠어요', null),
        ('어깨가 저려요', ChatBodyPart.shoulder),
        ('허리가 당겨요', ChatBodyPart.back),
        ('발목이 부었어요', ChatBodyPart.ankle),
        ('종아리가 쑤셔요', null),
        ('오늘은 좀 아픔이 있어요', null),
      ]) {
        final insight = detector.detect(message(body));
        expect(
          insight?.kind,
          ChatInsightKind.discomfort,
          reason: '`$body` 를 통증으로 읽지 못했습니다.',
        );
        expect(insight?.bodyPart, part, reason: body);
      }
    });

    test('예전부터 잡히던 표현은 그대로 잡힌다', () {
      for (final (String body, ChatInsightKind kind)
          in <(String, ChatInsightKind)>[
            ('무릎이 아프네요', ChatInsightKind.discomfort),
            ('어깨가 불편해요', ChatInsightKind.discomfort),
            ('통증이 좀 있어요', ChatInsightKind.discomfort),
            ('목이 뻐근해요', ChatInsightKind.discomfort),
            ('운동을 못 갔어요', ChatInsightKind.negativeFeedback),
            ('오늘은 못했어요', ChatInsightKind.negativeFeedback),
            ('너무 힘들어서 포기했어요', ChatInsightKind.negativeFeedback),
            ('별로였어요', ChatInsightKind.negativeFeedback),
            ('오늘은 지쳤어요', ChatInsightKind.negativeFeedback),
            ('계단이 좀 부담돼요', ChatInsightKind.negativeFeedback),
          ]) {
        expect(detector.detect(message(body))?.kind, kind, reason: body);
      }
    });

    test('영어 통증어도 낱말 경계에서 끊는다', () {
      // `painting`·`sorely` 처럼 통증과 무관한 낱말에 어간이 들어 있다.
      expect(detector.detect(message('did some painting today')), isNull);
      expect(
        detector.detect(message('my knee hurts'))?.kind,
        ChatInsightKind.discomfort,
      );
      expect(
        detector.detect(message('my back aches since monday'))?.bodyPart,
        ChatBodyPart.back,
      );
    });
  });

  group('english body parts need real word context', () {
    test('coming back to the gym is not the back', () {
      final insight = detector.detect(
        message('back at the gym today, legs are sore'),
      );

      expect(insight?.kind, ChatInsightKind.discomfort);
      expect(insight?.bodyPart, isNull);
    });

    test('a possessive marks the back as a body part', () {
      expect(
        detector.detect(message('my back is sore'))?.bodyPart,
        ChatBodyPart.back,
      );
    });

    test('a pain word after it marks the back as a body part', () {
      expect(
        detector.detect(message('lower back pain since monday'))?.bodyPart,
        ChatBodyPart.back,
      );
    });

    test('unambiguous parts match on their own, singular or plural', () {
      expect(
        detector.detect(message('my neck hurts'))?.bodyPart,
        ChatBodyPart.neck,
      );
      expect(
        detector.detect(message('both knees are sore'))?.bodyPart,
        ChatBodyPart.knee,
      );
    });
  });

  // (#2303) 영어 메시지도 한국어와 같은 무게로 읽는다. 한 표에 문장·기대 종류·
  // 기대 부위를 두어, 규칙 하나를 고칠 때 어떤 자연스러운 말이 빠지는지 곧바로
  // 드러나게 한다.
  group('영어 통증 표현 (#2303)', () {
    for (final (String body, ChatBodyPart? part) in <(String, ChatBodyPart?)>[
      ('my knee hurts', ChatBodyPart.knee),
      ('My knees hurt after the squats', ChatBodyPart.knee),
      ('I have some pain in my left knee', ChatBodyPart.knee),
      ('knee is a bit sore today', ChatBodyPart.knee),
      ('Knee pain came back during lunges', ChatBodyPart.knee),
      ('my lower back hurts', ChatBodyPart.back),
      ('I think I hurt my back deadlifting', ChatBodyPart.back),
      ('Back pain again this morning', ChatBodyPart.back),
      ('back hurts when I bend over', ChatBodyPart.back),
      ('I woke up with a backache', ChatBodyPart.back),
      ('my upper back feels tight', ChatBodyPart.back),
      ('Ankle is swollen since yesterday', ChatBodyPart.ankle),
      ('I twisted my ankle on the stairs', ChatBodyPart.ankle),
      ('rolled my ankle during the run', ChatBodyPart.ankle),
      ('my shoulder aches when I press overhead', ChatBodyPart.shoulder),
      ('Shoulders are really stiff', ChatBodyPart.shoulder),
      ('left shoulder is aching', ChatBodyPart.shoulder),
      ('wrist feels uncomfortable on push-ups', ChatBodyPart.wrist),
      ('I tweaked my wrist', ChatBodyPart.wrist),
      ('my wrist is numb after cycling', ChatBodyPart.wrist),
      ('neck is stiff after sleeping wrong', ChatBodyPart.neck),
      ('Neck pain from the desk job', ChatBodyPart.neck),
      ('slight neckache today', ChatBodyPart.neck),
      ("I'm so sore from yesterday", null),
      ('legs are sore', null),
      ('My hamstrings are tight', null),
      ('I think I pulled a muscle', null),
      ('I have a cramp in my calf', null),
      ('had a headache all day', null),
      ('there is a throbbing feeling in my hip', null),
      ('some tingling in my fingers', null),
      ('I think I sprained something', null),
      ('I got injured at football', null),
      ('I took painkillers this morning', null),
      ('feeling some discomfort', null),
      ('it is painful to walk', null),
      ('HURTS A LOT', null),
    ]) {
      test('`$body` → discomfort / ${part?.name}', () {
        final insight = detector.detect(message(body));
        expect(insight?.kind, ChatInsightKind.discomfort, reason: body);
        expect(insight?.bodyPart, part, reason: body);
        expect(insight?.evidence, body);
        expect(insight?.id, 'message-1:discomfort');
      });
    }
  });

  group('영어 부담·수행 어려움 표현 (#2303)', () {
    for (final String body in <String>[
      'The workout was too hard',
      'that session was way too intense for me',
      'the weights were too heavy',
      "I couldn't finish the last set",
      'I couldnt do the plank',
      "I can't keep up with the program",
      'I can’t do the lunges anymore',
      'I cannot do burpees',
      'I was unable to finish',
      "I wasn't able to go today",
      "I didn't go to the gym this week",
      "didn't work out yesterday",
      "I didn't make it today",
      'I gave up halfway',
      'I want to give up',
      'I skipped my workout',
      'skipped leg day again',
      'I missed the session',
      "missed today's workout because of work",
      'I feel exhausted',
      'totally drained after work',
      "I'm burned out",
      'feeling burnt out lately',
      'I feel worn out',
      'honestly overwhelmed by the routine',
      "I'm too tired",
      'so tired today',
      'I struggled with the cardio',
      'I overdid it yesterday',
      'the plan feels like a burden',
      'it is hard to keep up with the plan',
    ]) {
      test('`$body` → negativeFeedback', () {
        final insight = detector.detect(message(body));
        expect(insight?.kind, ChatInsightKind.negativeFeedback, reason: body);
        expect(insight?.bodyPart, isNull, reason: body);
        expect(insight?.id, 'message-1:negative');
      });
    }
  });

  group('영어 일상 말은 신호가 아니다 (#2303)', () {
    for (final String body in <String>[
      'did some painting today',
      "I'm back at the gym!",
      'coming back tomorrow',
      "can't wait for the next session",
      'I ate too much at dinner',
      'I skipped dessert',
      'my schedule is tight this week',
      'pulled up the app to log lunch',
      'I rolled my eyes at the scale',
      'great session, thanks coach',
      'done with all three sets',
      'I missed you at the gym',
      'I finished the cooldown',
      'no problem, see you Friday',
      'I tried a new recipe',
    ]) {
      test('`$body` → null', () {
        expect(detector.detect(message(body)), isNull, reason: body);
      });
    }
  });

  group('한국어 표현 표 (#2303 회귀)', () {
    for (final (String body, ChatInsightKind kind, ChatBodyPart? part)
        in <(String, ChatInsightKind, ChatBodyPart?)>[
          ('무릎이 시큰하고 아파요', ChatInsightKind.discomfort, ChatBodyPart.knee),
          ('허리가 뻐근해요', ChatInsightKind.discomfort, ChatBodyPart.back),
          ('발목이 좀 부었어요', ChatInsightKind.discomfort, ChatBodyPart.ankle),
          ('어깨가 쑤셔요', ChatInsightKind.discomfort, ChatBodyPart.shoulder),
          ('손목이 저려요', ChatInsightKind.discomfort, ChatBodyPart.wrist),
          ('목이 당겨요', ChatInsightKind.discomfort, ChatBodyPart.neck),
          ('관절통증이 있어요', ChatInsightKind.discomfort, null),
          ('허리띠가 불편해요', ChatInsightKind.discomfort, null),
          ('운동이 너무 힘들어요', ChatInsightKind.negativeFeedback, null),
          ('오늘은 못 했어요', ChatInsightKind.negativeFeedback, null),
          ('중간에 포기했어요', ChatInsightKind.negativeFeedback, null),
          ('계획이 부담스러워요', ChatInsightKind.negativeFeedback, null),
          ('너무 지쳐요', ChatInsightKind.negativeFeedback, null),
        ]) {
      test('`$body` → ${kind.name} / ${part?.name}', () {
        final insight = detector.detect(message(body));
        expect(insight?.kind, kind, reason: body);
        expect(insight?.bodyPart, part, reason: body);
      });
    }

    test('한국어와 영어가 같은 부위 코드를 낸다', () {
      for (final (String ko, String en) in <(String, String)>[
        ('무릎이 아파요', 'my knee hurts'),
        ('허리가 아파요', 'my back hurts'),
        ('발목이 아파요', 'my ankle hurts'),
        ('어깨가 아파요', 'my shoulder hurts'),
        ('손목이 아파요', 'my wrist hurts'),
        ('목이 아파요', 'my neck hurts'),
      ]) {
        final ChatBodyPart? a = detector.detect(message(ko))?.bodyPart;
        expect(a, isNotNull, reason: ko);
        expect(detector.detect(message(en))?.bodyPart, a, reason: en);
      }
    });

    test('통증이 부담보다 먼저다 — 둘 다 있으면 통증으로 읽는다', () {
      expect(
        detector.detect(message('too hard, and my knee hurts'))?.kind,
        ChatInsightKind.discomfort,
      );
      expect(
        detector.detect(message('너무 힘들고 무릎도 아파요'))?.kind,
        ChatInsightKind.discomfort,
      );
    });
  });

  group('부위 이름은 로케일을 따른다 (#2303)', () {
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    test('모든 부위 코드에 한·영 이름이 있다', () {
      const Map<ChatBodyPart, (String, String)> expected =
          <ChatBodyPart, (String, String)>{
            ChatBodyPart.knee: ('무릎', 'Knee'),
            ChatBodyPart.back: ('허리', 'Back'),
            ChatBodyPart.ankle: ('발목', 'Ankle'),
            ChatBodyPart.shoulder: ('어깨', 'Shoulder'),
            ChatBodyPart.wrist: ('손목', 'Wrist'),
            ChatBodyPart.neck: ('목', 'Neck'),
          };
      expect(expected.keys.toSet(), ChatBodyPart.values.toSet());
      for (final MapEntry<ChatBodyPart, (String, String)> e
          in expected.entries) {
        expect(chatBodyPartLabel(ko, e.key), e.value.$1);
        expect(chatBodyPartLabel(en, e.key), e.value.$2);
      }
    });

    test('영어 메시지에서 잡은 부위도 한국어 화면에는 한국어로 뜬다', () {
      final ChatContextInsight insight = detector.detect(
        message('my knee hurts'),
      )!;
      expect(chatInsightBodyPartLabel(ko, insight), '무릎');
      expect(chatInsightBodyPartLabel(en, insight), 'Knee');
      expect(
        ko.chatInsightDiscomfortTitle(chatInsightBodyPartLabel(ko, insight)),
        '무릎 불편 표현 감지',
      );
      expect(
        en.chatInsightDiscomfortTitle(chatInsightBodyPartLabel(en, insight)),
        'Knee discomfort detected',
      );
    });

    test('한국어 메시지에서 잡은 부위도 영어 화면에는 영어로 뜬다', () {
      final ChatContextInsight insight = detector.detect(message('허리가 뻐근해요'))!;
      expect(chatInsightBodyPartLabel(ko, insight), '허리');
      expect(chatInsightBodyPartLabel(en, insight), 'Back');
    });

    test('부위가 없으면 일반 이름이다', () {
      final ChatContextInsight insight = detector.detect(
        message('legs are sore'),
      )!;
      expect(
        chatInsightBodyPartLabel(ko, insight),
        ko.chatInsightBodyPartGeneral,
      );
      expect(
        chatInsightBodyPartLabel(en, insight),
        en.chatInsightBodyPartGeneral,
      );
    });

    test('메모 요약도 로케일 이름을 쓴다', () {
      final ChatContextInsight knee = detector.detect(
        message('my knee hurts'),
      )!;
      expect(chatInsightMemoSummary(ko, knee), '무릎 불편 감지');
      expect(chatInsightMemoSummary(en, knee), 'Knee discomfort detected');

      final ChatContextInsight general = detector.detect(
        message('so sore today'),
      )!;
      expect(
        chatInsightMemoSummary(en, general),
        en.chatInsightMemoSummaryDiscomfort(en.chatInsightBodyPartGeneral),
      );

      final ChatContextInsight negative = detector.detect(
        message('I gave up halfway'),
      )!;
      expect(chatInsightMemoSummary(ko, negative), '운동 부담 감지');
      expect(chatInsightMemoSummary(en, negative), 'Workout strain detected');
    });
  });
}
