import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 이메일 완전 일치로 찾은 회원 한 명.
///
/// 요청을 보낼지 판단할 만큼만 담는다 — 이름, 이미 담당이 있는지, 내가 보낸
/// 요청이 기다리고 있는지. 담당이 **누구인지**는 서버도 알려 주지 않는다.
/// 담당이 아닌 트레이너가 알 이유가 없는 값이다. (#919)
///
/// [gender]·[age]·[goal] 은 실 API 에는 없다(`MemberLookupOut` 이 문서로 남긴
/// 대로 — 담당이 성립하기 전에는 신체 정보를 보여줄 이유가 없다). 데모만
/// 채운다 — 답할 회원 백엔드가 없어 연결이 그 자리에서 끝나는 대신, 트레이너가
/// 등록 전에 "이 사람이 맞는지" 확인할 수 있어야 한다.
class MemberLookup {
  const MemberLookup({
    required this.memberId,
    required this.name,
    required this.hasTrainer,
    required this.coachedByMe,
    required this.invitePending,
    this.gender,
    this.age,
    this.goal,
  });

  final String memberId;
  final String name;

  /// 이미 활성 담당 트레이너가 있는가.
  final bool hasTrainer;

  /// 그 담당이 나인가 — 이미 명단에 있는 회원을 다시 찾은 경우.
  final bool coachedByMe;

  /// 내가 보낸 요청이 대기 중인가.
  final bool invitePending;

  /// `male`/`female`/`other` — 데모에서만 채워지는, 회원이 이미 등록해 둔 값.
  final String? gender;

  /// 데모에서만 채워지는 만 나이.
  final int? age;

  /// 데모에서만 채워지는 운동 목표.
  final String? goal;

  /// 지금 이 회원에게 요청을 보낼 수 있는가.
  bool get canInvite => !hasTrainer && !invitePending;

  factory MemberLookup.fromJson(Map<String, Object?> json) => MemberLookup(
    memberId: json['member_id']! as String,
    name: json['name'] as String? ?? '',
    hasTrainer: json['has_trainer'] as bool? ?? false,
    coachedByMe: json['coached_by_me'] as bool? ?? false,
    invitePending: json['invite_pending'] as bool? ?? false,
    gender: json['gender'] as String?,
    age: (json['age'] as num?)?.toInt(),
    goal: json['goal'] as String?,
  );
}

/// 6자리 동기화 코드로 방금 연결된 회원. (#1634)
///
/// 코드를 발급해 불러 준 것이 회원 본인이라 신원 확인은 이미 끝났다. 그래도
/// 이름만 돌려받지 않는 것은, 트레이너가 여섯 자리를 잘못 눌렀을 때 **연결된
/// 뒤에라도** 그 사실을 알아볼 수 있어야 하기 때문이다.
///
/// 키·몸무게·질환 같은 값은 여기 없다. 그것들은 고객 상세의 건강 프로필에서
/// 조회한다.
class PairedMember {
  const PairedMember({
    required this.memberId,
    required this.name,
    this.gender = '',
    this.age,
    this.goal = '',
  });

  /// 내부 식별자(`User.id`) — 고객 상세로 넘어갈 때 쓴다.
  final String memberId;
  final String name;

  /// `male`/`female`/`other`. 회원이 자기 앱에 등록해 둔 값이고, 비어 있을 수 있다.
  final String gender;

  /// 생년월일로 계산한 만 나이. 회원이 넣지 않았으면 `null`.
  final int? age;

  /// 회원이 적어 둔 운동 목표. 비어 있을 수 있다.
  final String goal;

  /// 화면에 쓸 성별·나이 — 고객 목록과 **같은 규칙**이다 (#1634).
  ///
  /// 회원이 프로필에 성별·생년월일을 넣지 않았으면 목록과 마찬가지로 id 에서
  /// 만든 고정 값이 선다. 목록은 `남성 · 23세` 라고 하는데 확인 카드만 아무
  /// 말이 없으면, 트레이너가 지금 잇는 사람이 목록의 그 사람인지 견줄 수 없다.
  String get rosterGender => rosterGenderFor(id: memberId, gender: gender);

  /// 나이는 생년월일이 없으면 `null` 이다 — 지어내지 않는다(#2744).
  int? get rosterAge => rosterAgeFor(age: age);

  factory PairedMember.fromJson(Map<String, Object?> json) => PairedMember(
    memberId: (json['member_id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    gender: (json['gender'] as String?) ?? '',
    age: (json['age'] as num?)?.toInt(),
    goal: (json['goal'] as String?) ?? '',
  );
}

/// 담당 요청의 처리 상태.
enum ClientInviteStatus {
  pending,
  accepted,
  rejected,
  cancelled;

  static ClientInviteStatus parse(Object? value) => switch (value) {
    'accepted' => ClientInviteStatus.accepted,
    'rejected' => ClientInviteStatus.rejected,
    'cancelled' => ClientInviteStatus.cancelled,
    _ => ClientInviteStatus.pending,
  };
}

/// 트레이너가 회원에게 보낸 담당 요청.
///
/// 이것이 있다고 해서 명단에 회원이 생기지는 않는다 — 담당은 회원이 수락해야
/// 생긴다. 그래서 이 목록은 고객 목록과 나란히 있지 않고, 등록 시트 안에서만
/// 보인다. 두 목록을 섞으면 "요청 = 고객" 으로 읽힌다.
class ClientInvite {
  const ClientInvite({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.memberEmail,
    required this.status,
    required this.createdAt,
    this.message,
  });

  final String id;
  final String memberId;
  final String memberName;
  final String memberEmail;
  final ClientInviteStatus status;
  final DateTime createdAt;
  final String? message;

  bool get isPending => status == ClientInviteStatus.pending;

  factory ClientInvite.fromJson(Map<String, Object?> json) => ClientInvite(
    id: json['id']! as String,
    memberId: json['member_id'] as String? ?? '',
    memberName: json['member_name'] as String? ?? '',
    memberEmail: json['member_email'] as String? ?? '',
    status: ClientInviteStatus.parse(json['status']),
    // 보낸 시각이 없거나 깨졌으면 조용히 '지금' 으로 메우지 않는다 — 언제
    // 보냈는지가 트레이너가 기다릴지 다시 보낼지를 정하는 값이라, 틀린 값보다
    // 실패가 낫다(다른 응답 파서와 같은 규약).
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
        (throw const FormatException('Invalid client invite created_at.')),
    message: json['message'] as String?,
  );
}
