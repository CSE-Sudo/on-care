/// 고객이 그날 한 운동 **한 종목**. (#1902)
///
/// 예전에는 이름 문자열 하나였고, 세트·횟수·중량은 그 이름 안에 적혀 있었다
/// (`레그프레스 70kg · 4세트`). 서버는 같은 값을 `sets`·`reps`·`weight` 칸으로
/// 내려보내는데 앱이 이름만 읽어서, 이름을 쓰는 화면과 필드를 읽는 화면이 같은
/// 기록을 다르게 말했다.
///
/// 한 줄로 읽히는 표기는 화면이 만든다 — `세트`·`회`·`kg` 은 로케일을 타는
/// 문구라, 여기서 이어 붙이면 영어 화면에 한글이 새어 나온다(#1933).
class ClientExerciseItem {
  const ClientExerciseItem({
    required this.name,
    this.type = '',
    this.minutes = 0,
    this.sets,
    this.reps,
    this.holdSeconds,
    this.weight,
    this.done = true,
  });

  /// 이름만 아는 옛 기록. 값이 이름 문자열에 섞여 있던 시절의 자료와, 이름만
  /// 싣던 응답이 여기로 떨어진다 — 그때는 적힌 그대로 보여 준다.
  /// `벤치프레스 ✓` 처럼 수행 표시가 붙어 있던 줄도 받는다.
  factory ClientExerciseItem.nameOnly(String raw) => ClientExerciseItem(
    name: raw.replaceAll(RegExp(r'\s*[✓✗]\s*'), ' ').trim(),
    done: !raw.contains('✗'),
  );

  factory ClientExerciseItem.fromJson(Map<String, Object?> json) =>
      ClientExerciseItem(
        name: (json['name'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        sets: (json['sets'] as num?)?.toInt(),
        reps: (json['reps'] as num?)?.toInt(),
        holdSeconds: (json['hold_seconds'] as num?)?.toInt(),
        weight: (json['weight'] as num?)?.toDouble(),
        done: json['done'] as bool? ?? true,
      );

  final String name;

  /// `cardio` | `strength` | `stretching` | `other`. 비어 있으면 모른다.
  final String type;

  final int minutes;

  /// 근력의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 null 이다.
  final int? sets;
  final int? reps;

  /// 버티는 운동이면 한 세트를 버틴 시간(초). [reps] 와 한 자리를 나눠 쓴다 —
  /// 플랭크를 `3회` 로 적으면 45초를 "3회" 라고 말하게 된다(#1969).
  final int? holdSeconds;

  final double? weight;

  /// 실제로 했는가. 운동 기록 탭이 ✓/✗ 로 그린다 — 배정만 되고 하지 않은 항목도
  /// 이력에는 남는다.
  final bool done;

  /// 이름 말고 적힌 값이 하나라도 있는가.
  bool get hasAmount =>
      sets != null || reps != null || holdSeconds != null || minutes > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (type.isNotEmpty) 'type': type,
    if (minutes > 0) 'minutes': minutes,
    if (sets != null) 'sets': sets,
    if (reps != null) 'reps': reps,
    if (holdSeconds != null) 'hold_seconds': holdSeconds,
    if (weight != null) 'weight': weight,
    if (!done) 'done': done,
  };
}
