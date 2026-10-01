import 'package:flutter/widgets.dart';

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

// 동명이인 구분 문구·로스터 조회는 위젯이 아니라서 `shared/widgets` 밖에 둔다.
// 규격 전환을 마친 화면(#1703)이 옛 위젯 파일을 가져가지 않고 쓸 수 있게 한다.

/// Returns the localized demographic label used to distinguish clients who
/// share a name.
String clientDemographicsLabel(BuildContext context, TrainerClient client) =>
    demographicsLabel(
      context,
      gender: client.rosterGender,
      age: client.rosterAge,
    );

/// 로스터 행이 아닌 값으로도 같은 문구를 만든다 — `여성 · 29세`.
///
/// 신규 고객 등록의 확인 카드가 쓴다 (#1634). 목록과 다른 모양으로 적으면,
/// 트레이너가 지금 잇는 사람이 목록의 그 사람인지 견줄 때 한 번 더 생각해야
/// 한다.
///
/// 아는 값만 적는다 — 지어내지 않는다.
/// - [age] 가 `null` 이면(회원이 생년월일을 넣지 않았다) 성별만(#2744).
/// - 성별이 `male`/`female`/`other` 가 아니면(미입력) 나이만(#2870).
/// - 둘 다 모르면 빈 문자열 — 부르는 쪽은 구분 문구 자리를 그리지 않는다.
///
/// `other` 는 회원이 직접 고른 `기타` 다. 미입력을 `기타` 로 바꿔 적으면 회원이
/// 고르지 않은 값을 고른 것처럼 보이므로 둘을 가른다.
String demographicsLabel(
  BuildContext context, {
  required String gender,
  required int? age,
}) {
  // 성별·나이 문구는 ARB 가 정한다 (#2304) — 예전의 `korean ?` 분기는 두 언어만
  // 코드에 박아 두어, 로케일이 늘면 그 언어도 영어로 떨어졌다.
  final AppLocalizations l = AppLocalizations.of(context);
  final String? genderLabel = switch (gender) {
    'female' => l.memberHealthGenderFemale,
    'male' => l.memberHealthGenderMale,
    'other' => l.memberHealthGenderOther,
    _ => null,
  };
  if (genderLabel == null) {
    return age == null ? '' : l.coachClientAgeOnly(age);
  }
  if (age == null) return genderLabel;
  return l.coachClientDemographics(genderLabel, age);
}

/// Resolves display-only records that carry a client id and a legacy name.
/// A name fallback is safe only when it identifies exactly one roster entry.
TrainerClient? findClientIdentity(
  List<TrainerClient> clients, {
  required String? clientId,
  required String clientName,
}) {
  for (final client in clients) {
    if (clientId != null && client.id == clientId) return client;
  }
  final sameName = clients.where((client) => client.name == clientName);
  return sameName.length == 1 ? sameName.single : null;
}

/// [clientId]·[clientName] 이 로스터의 누구도 가리키지 않는가. (#988)
///
/// 상담으로 잡힌 가망 고객이 그렇다 — 트레이너가 수락하기 전까지 회원과의
/// 연결이 없어 로스터에 자리가 없다. 이름이 겹치는 회원이 둘 이상이면 누구인지
/// 못 고르는 것이지 없는 것이 아니므로 신규로 보지 않는다.
bool isProspectClient(
  List<TrainerClient> clients, {
  required String? clientId,
  required String clientName,
}) {
  // 이름은 다듬어 견준다 — 표시용 이름에 앞뒤 공백이 섞여 들어오면, 로스터에
  // 있는 회원까지 신규로 읽힌다.
  final name = clientName.trim();
  if (name.isEmpty) return false;
  for (final client in clients) {
    if (clientId != null && client.id == clientId) return false;
    if (client.name.trim() == name) return false;
  }
  return true;
}
