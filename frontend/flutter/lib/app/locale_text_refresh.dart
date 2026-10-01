import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/shared/services/locale_provider.dart';

/// 화면 언어가 바뀌면 서버가 그 언어로 만든 문장을 다시 읽는다(#2719).
///
/// 앱은 모든 요청에 화면 언어를 `Accept-Language` 로 싣고, 서버는 그 언어로
/// 문장(코치 한마디·코칭 카드·알림·운동 조언)을 만든다. 언어가 바뀌어도 이미
/// 받아 둔 응답은 옛 언어 그대로라 같은 화면에 두 언어가 섞였다. 언어를 조회
/// 키에 넣은 식단 조언(`dietAdviceProvider`)처럼 다시 읽게 한다.
///
/// **서버가 언어를 가리는 응답만** 여기 등록한다. 한국어로만 오는 응답은 다시
/// 읽어도 같으니 넣지 않는다. 앱 루트(`OncareApp`)가 이 프로바이더를 켜 둔다.
final localeTextRefreshProvider = Provider<void>((ref) {
  ref.listen(resolvedLocaleProvider, (previous, next) {
    if (previous == null || previous == next) return;
    ref
      ..invalidate(dietTodayProvider)
      ..invalidate(dietByDateFamily)
      ..invalidate(aiCoachStateProvider)
      ..invalidate(notificationControllerProvider)
      ..invalidate(exerciseAdviceProvider);
  });
}, name: 'localeTextRefresh');
