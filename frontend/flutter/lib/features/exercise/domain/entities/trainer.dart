/// A trainer working at a gym. Trainers have their own identity so a gym can
/// employ several of them — [Gym] deliberately carries no trainer fields.
///
/// The profile fields (career/intro/certifications) mirror the trainer app's
/// `TrainerProfile`, so the same person reads the same in both apps.
class Trainer {
  const Trainer({
    required this.id,
    required this.gymId,
    required this.name,
    this.role,
    this.reasons = const <String>[],
    this.career,
    this.intro,
    this.certifications = const <String>[],
  });

  final String id;

  /// Gym this trainer belongs to. Several trainers may share one gym id.
  final String gymId;
  final String name;

  /// Job title (e.g. "퍼스널 트레이너"). Null falls back to a localized default.
  final String? role;

  /// 이 트레이너를 추천하는 근거 키워드. 한 사람을 고를 이유가 하나뿐인 경우는
  /// 드물어 목록으로 든다 — 헬스장 찾기 줄은 이걸 배지로 하나씩 그린다(#1881).
  /// 비어 있으면 근거가 없는 것이라, 화면은 아무것도 적지 않거나 기본 문구로
  /// 갈음한다.
  final List<String> reasons;

  /// Years of experience as free text (e.g. "7년"). Null hides the row.
  final String? career;

  /// Self-introduction shown on the detail page. Null hides the section.
  final String? intro;

  /// Licences and certifications. Empty hides the section.
  final List<String> certifications;

  /// 배지를 여러 개 놓을 자리가 없는 화면(트레이너 목록 카드·상세 박스)이 한 줄로
  /// 적을 때 쓴다. 근거가 없으면 null — 부르는 쪽이 기본 문구로 갈음한다.
  String? get reasonLine => reasons.isEmpty ? null : reasons.join(', ');

  /// True when there is anything to render in the 트레이너 소개 section.
  bool get hasProfile =>
      (intro?.isNotEmpty ?? false) ||
      (career?.isNotEmpty ?? false) ||
      certifications.isNotEmpty;
}
