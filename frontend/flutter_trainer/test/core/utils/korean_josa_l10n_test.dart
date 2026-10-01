import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/korean_josa_l10n.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 화면 언어별 조사 부착 (#2895).
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('한국어 화면', () {
    test('받침이 있으면 을·은', () {
      expect(withObjectJosaFor(ko, '스쿼트 러닝'), '스쿼트 러닝을');
      expect(withTopicJosaFor(ko, '인터벌 러닝'), '인터벌 러닝은');
    });

    test('받침이 없으면 를·는', () {
      expect(withObjectJosaFor(ko, '스쿼트'), '스쿼트를');
      expect(withTopicJosaFor(ko, '요가'), '요가는');
    });

    test('withParticle 은 넘긴 두 조사 중 하나를 고른다', () {
      expect(withParticle(ko, '런지', '이', '가'), '런지가');
      expect(withParticle(ko, '플랭크', '이', '가'), '플랭크가');
      expect(withParticle(ko, '데드리프트 운동', '이', '가'), '데드리프트 운동이');
    });
  });

  group('영어 화면', () {
    test('한국어 이름에도 조사를 붙이지 않는다', () {
      expect(withObjectJosaFor(en, '스쿼트'), '스쿼트');
      expect(withTopicJosaFor(en, '가벼운 인터벌 러닝'), '가벼운 인터벌 러닝');
      expect(withParticle(en, '런지', '이', '가'), '런지');
    });

    test('영어 이름도 그대로 둔다', () {
      expect(withObjectJosaFor(en, 'Squat'), 'Squat');
      expect(withTopicJosaFor(en, 'Interval run'), 'Interval run');
    });

    test('문장에 끼우면 조사 없는 문장이 된다', () {
      expect(
        en.aiProgramExerciseRemoveBody(withObjectJosaFor(en, '스쿼트')),
        'Removes 스쿼트 from this program.',
      );
      expect(
        en.aiPersonalDismissed(withTopicJosaFor(en, '가벼운 인터벌 러닝')),
        '가벼운 인터벌 러닝 will not be recommended',
      );
    });
  });
}
