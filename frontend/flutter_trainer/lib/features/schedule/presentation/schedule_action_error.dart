import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 스케줄 화면 동작(삭제·완료·취소·노쇼·개인운동·프로그램 전송)이 실패했을 때
/// 토스트에 띄울 문구. (#2888)
///
/// 서버가 사유를 주면(이미 다른 기기에서 취소됨, 시작 전이라 노쇼 불가 등) 그
/// 문장이 고정 문구보다 정확하다 — 트레이너는 "왜 안 되는지" 알면 바로
/// 해결한다. 사유가 없는 실패(네트워크·데모 저장소)는 동작별 [fallback] 이다.
/// 영어 화면에서는 한국어 사유 대신 [fallback] 이다([serverDetailOr]).
String scheduleActionErrorMessage(
  AppLocalizations l,
  Object error,
  String fallback,
) => error is AppError ? serverDetailOr(l, error.message, fallback) : fallback;

/// 일정 상태가 그새 바뀌어 서버가 거절했는가(409). (#2888)
///
/// 다른 탭·기기에서 이미 노쇼·취소로 마무리한 PT 를 이 화면이 아직 예정으로
/// 들고 있으면 같은 동작을 되풀이하게 된다 — 안내 뒤 그 주를 다시 읽어 화면을
/// 서버 상태에 맞춘다.
bool isScheduleStateConflict(Object error) =>
    error is ServerError && error.statusCode == 409;
