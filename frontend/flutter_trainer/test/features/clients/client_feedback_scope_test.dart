/// 기록 종류 이름. (#1453)
///
/// 옛 시드의 `AI 루틴 · 자율 운동` 이 그대로 보였다. 회원 피드백 상자의 제목을
/// 보던 테스트는 상자를 걷어내면서 함께 지웠다(#2329).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

void main() {
  group('routineKindLabel', () {
    test('옛 라벨은 그릴 때 새 용어로 바꿔 읽는다', () {
      expect(routineKindLabel(_ko, 'AI 루틴 · 자율 운동'), '개인운동');
    });

    test('그 밖의 라벨은 서버가 준 그대로 둔다', () {
      expect(routineKindLabel(_ko, 'PT 세션 · 트레이너 지도'), 'PT · 트레이너 지도');
      expect(routineKindLabel(_ko, 'AI 개인운동'), '개인운동');
    });
  });
}
