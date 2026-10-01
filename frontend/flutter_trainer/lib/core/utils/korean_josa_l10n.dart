/// 화면 언어를 보고 조사를 붙인다. (#2895)
///
/// [withObjectJosa]·[withTopicJosa] 는 언어를 보지 않고 늘 한국어 조사를
/// 붙인다 — 영어 화면에서 그대로 쓰면 `Removes 스쿼트를 from this program.`
/// 처럼 깨진 문장이 된다. 화면 문구에 이름을 끼울 때는 이 파일의 함수를 쓰고,
/// 언어와 무관한 함수는 백엔드 문장과 맞추는 한국어 전용 경로에만 남긴다.
///
/// 받침 판정 규칙은 [hasFinalConsonant] 하나를 그대로 따른다.
library;

import 'package:oncare_trainer/core/utils/korean_josa.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 한국어 화면일 때만 받침에 맞는 조사를 붙인다. 다른 언어에는 조사가 없다 —
/// 영어 문장에 `Squat은` 이 남으면 안 된다.
///
/// 리포트 도메인에 있던 것을 코칭 화면도 함께 쓰도록 옮겼다(#2895).
String withParticle(
  AppLocalizations l,
  String word,
  String afterConsonant,
  String afterVowel,
) {
  if (l.localeName != 'ko') return word;
  return '$word${hasFinalConsonant(word) ? afterConsonant : afterVowel}';
}

/// [word] 에 목적격 조사(`을`/`를`)를 붙인다 — 한국어 화면일 때만.
String withObjectJosaFor(AppLocalizations l, String word) =>
    withParticle(l, word, '을', '를');

/// [word] 에 주제격 조사(`은`/`는`)를 붙인다 — 한국어 화면일 때만.
String withTopicJosaFor(AppLocalizations l, String word) =>
    withParticle(l, word, '은', '는');
