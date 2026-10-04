import 'package:demo_fixture/demo_fixture.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';

/// The trainer's gym / workplace details.
class TrainerGym {
  /// Creates gym details.
  const TrainerGym({
    this.id,
    required this.name,
    required this.address,
    required this.hours,
    required this.phone,
  });

  /// Backend `places.id` used by `PUT /trainer/me/gym`.
  ///
  /// Legacy/demo profiles may not be affiliated with a persisted place.
  final String? id;

  /// Gym name (e.g. "온케어짐 신촌점").
  final String name;

  /// Street address.
  final String address;

  /// Operating hours label (e.g. "06:00 – 23:00").
  final String hours;

  /// Contact phone number.
  final String phone;
}

/// 운영자 승인 상태 — `GET /trainer/me` 의 `verification.status` (#2825).
enum TrainerVerificationStatus {
  /// 가입 직후. 회원 앱에 나오지 않고 상담·회원 연결을 받을 수 없다.
  pending,

  /// 승인됨 — 모든 기능이 열린다.
  approved,

  /// 반려됨. 승인 대기와 같이 막히고, 사유가 있으면 함께 보인다.
  rejected;

  /// 서버 문자열을 읽는다. 모르는 값은 [pending] — 닫힌 쪽으로 읽는다.
  static TrainerVerificationStatus fromWire(Object? value) => switch (value) {
    'approved' => approved,
    'rejected' => rejected,
    _ => pending,
  };
}

/// 트레이너 계정의 운영자 승인 상태 (#2825).
class TrainerVerification {
  /// Creates a verification snapshot.
  const TrainerVerification({required this.status, this.note = ''});

  /// 승인된 상태 — 데모 트레이너와 승인 절차 이전 서버의 응답이 이 값이다.
  static const TrainerVerification approved = TrainerVerification(
    status: TrainerVerificationStatus.approved,
  );

  /// 승인 대기·승인·반려.
  final TrainerVerificationStatus status;

  /// 반려 사유. 승인·대기면 빈 문자열이다.
  final String note;

  /// 승인을 받아 회원 앱 노출·상담·회원 연결이 열려 있는가.
  bool get isApproved => status == TrainerVerificationStatus.approved;
}

/// A trainer account's profile.
///
/// Until the real backend exists, login attaches a single fixed
/// [seedTrainerProfile] to the session (see the trainer-auth design in
/// CLAUDE.local.md). Fields mirror the Figma trainer "MY" screen so the
/// MY tab (a later issue) can render/edit them without reshaping data.
class TrainerProfile {
  /// Creates a trainer profile.
  const TrainerProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.specialty,
    required this.careerYears,
    required this.intro,
    required this.certifications,
    required this.gym,
    this.verification = TrainerVerification.approved,
    this.hasPassword = true,
  });

  /// Display name (e.g. "김태오").
  final String name;

  /// Login / contact email.
  final String email;

  /// Contact phone number.
  final String phone;

  /// Specialty label (e.g. "퍼스널 트레이너").
  final String specialty;

  /// 경력 연수(예: 7). 모르면 `null` 이다.
  ///
  /// 숫자로 들고 화면이 ARB(`myCareerYears`)로 적는다 (#2304). 예전에는
  /// `'7년'` 문구를 그대로 들고 있어 영어 화면에도 `7년 experience` 가 떴다.
  final int? careerYears;

  /// Short self-introduction shown on the MY screen.
  final String intro;

  /// Certifications / licenses.
  final List<String> certifications;

  /// Gym the trainer belongs to.
  final TrainerGym gym;

  /// 운영자 승인 상태 (#2825). 데모 프로필은 승인 상태다.
  final TrainerVerification verification;

  /// 비밀번호로 로그인할 수 있는 계정인가 — `GET /trainer/me` 의 `has_password`
  /// (#3039). 소셜로만 가입한 계정은 false 라, 탈퇴 같은 본인 확인을 비밀번호
  /// 대신 소셜 계정 재로그인으로 받는다. 칸이 없는 서버·데모 프로필은 true 다.
  final bool hasPassword;

  /// Returns a copy with the given fields replaced. Used by 회원가입 to
  /// reflect the submitted name/email on the (otherwise seed) demo profile.
  TrainerProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? specialty,
    int? careerYears,
    String? intro,
    List<String>? certifications,
    TrainerGym? gym,
    TrainerVerification? verification,
    bool? hasPassword,
  }) {
    return TrainerProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      specialty: specialty ?? this.specialty,
      careerYears: careerYears ?? this.careerYears,
      intro: intro ?? this.intro,
      certifications: certifications ?? this.certifications,
      gym: gym ?? this.gym,
      verification: verification ?? this.verification,
      hasPassword: hasPassword ?? this.hasPassword,
    );
  }
}

/// 데모 트레이너의 소속 헬스장 id — 백엔드 시드의 온케어짐 신촌점과 같은 값이다.
/// 데모 프로필이 소속을 가져야 '회원에게 보이지 않는다' 안내가 뜨지 않는다(#2543).
const String kDemoTrainerGymId = 'gym-oncare-sinchon';

/// The single fixed trainer profile attached on a successful (mock)
/// login. Sourced from the On-Care Figma trainer mock (TrainerMyTab).
const TrainerProfile seedTrainerProfile = TrainerProfile(
  name: kDemoTrainerName,
  email: 'trainer@oncare.com',
  phone: '010-1234-5678',
  specialty: '퍼스널 트레이너',
  careerYears: 7,
  // 회원앱 `MockGymRepository._kim.intro` 와 같은 문구여야 한다 — 한 사람이 두 앱에서
  // 같게 읽혀야 하고, 회원앱 테스트가 이 값을 그대로 비교한다.
  intro:
      '혈압 관리와 체중 감량을 함께 다루는 퍼스널 트레이너입니다. 회원 상태에 맞춘 '
      'AI 추천 프로그램을 활용해 안전한 강도부터 시작합니다.',
  certifications: <String>['생활스포츠지도사 2급', '퍼스널트레이닝 CPT', '스포츠 영양사'],
  gym: TrainerGym(
    id: kDemoTrainerGymId,
    name: '온케어짐 신촌점',
    address: '서울 서대문구 신촌로 120',
    hours: '06:00 – 23:00',
    phone: '02-1234-5678',
  ),
);

/// 영어 데모의 같은 트레이너 (#2304). 이름·연락처는 그대로 두고 소개·자격·
/// 헬스장 문구만 영어로 적는다.
const TrainerProfile seedTrainerProfileEn = TrainerProfile(
  name: kDemoTrainerName,
  email: 'trainer@oncare.com',
  phone: '010-1234-5678',
  specialty: 'Personal trainer',
  careerYears: 7,
  intro:
      'A personal trainer who works on blood pressure and weight loss '
      'together. I use AI-recommended programs tailored to each member and '
      'start from a safe intensity.',
  certifications: <String>[
    'Sports Instructor Level 2',
    'Certified Personal Trainer (CPT)',
    'Sports Nutritionist',
  ],
  gym: TrainerGym(
    id: kDemoTrainerGymId,
    name: 'OnCare Gym Sinchon',
    address: '120 Sinchon-ro, Seodaemun-gu, Seoul',
    hours: '06:00 – 23:00',
    phone: '02-1234-5678',
  ),
);

/// [language] 데모의 트레이너 프로필.
TrainerProfile seedTrainerProfileFor(DemoLanguage language) =>
    language.isEnglish ? seedTrainerProfileEn : seedTrainerProfile;
