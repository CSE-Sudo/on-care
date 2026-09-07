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
    required this.career,
    required this.intro,
    required this.certifications,
    required this.gym,
  });

  /// Display name (e.g. "김트레이너").
  final String name;

  /// Login / contact email.
  final String email;

  /// Contact phone number.
  final String phone;

  /// Specialty label (e.g. "퍼스널 트레이너").
  final String specialty;

  /// Career length label (e.g. "7년").
  final String career;

  /// Short self-introduction shown on the MY screen.
  final String intro;

  /// Certifications / licenses.
  final List<String> certifications;

  /// Gym the trainer belongs to.
  final TrainerGym gym;

  /// Returns a copy with the given fields replaced. Used by 회원가입 to
  /// reflect the submitted name/email on the (otherwise seed) demo profile.
  TrainerProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? specialty,
    String? career,
    String? intro,
    List<String>? certifications,
    TrainerGym? gym,
  }) {
    return TrainerProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      specialty: specialty ?? this.specialty,
      career: career ?? this.career,
      intro: intro ?? this.intro,
      certifications: certifications ?? this.certifications,
      gym: gym ?? this.gym,
    );
  }
}

/// The single fixed trainer profile attached on a successful (mock)
/// login. Sourced from the On-Care Figma trainer mock (TrainerMyTab).
const TrainerProfile seedTrainerProfile = TrainerProfile(
  name: '김트레이너',
  email: 'trainer@oncare.com',
  phone: '010-1234-5678',
  specialty: '퍼스널 트레이너',
  career: '7년',
  // 회원앱 `MockGymRepository._kim.intro` 와 같은 문구여야 한다 — 한 사람이 두 앱에서
  // 같게 읽혀야 하고, 회원앱 테스트가 이 값을 그대로 비교한다.
  intro:
      '혈압 관리와 체중 감량을 함께 다루는 퍼스널 트레이너입니다. 회원 상태에 맞춘 '
      'AI 추천 프로그램을 활용해 안전한 강도부터 시작합니다.',
  certifications: <String>['생활스포츠지도사 2급', '퍼스널트레이닝 CPT', '스포츠 영양사'],
  gym: TrainerGym(
    name: '온케어짐 신촌점',
    address: '서울 서대문구 신촌로 120',
    hours: '06:00 – 23:00',
    phone: '02-1234-5678',
  ),
);
