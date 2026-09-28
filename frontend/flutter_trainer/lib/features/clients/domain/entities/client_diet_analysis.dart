/// 트레이너 웹 `식단 분석` 한 문장 — 로케일과 무관한 키와 값. (#2379)
///
/// 서버(`GET /trainer/clients/{id}/diet-advice` 의 `sentences`)와 데모 규칙
/// (`diet_analysis_rules.dart`)이 같은 모양으로 낸다. 화면이 ARB 로 그린다.
class ClientDietSentence {
  const ClientDietSentence(this.key, [this.params = const <String, Object>{}]);

  factory ClientDietSentence.fromJson(Map<String, Object?> json) =>
      ClientDietSentence((json['key'] as String?) ?? '', <String, Object>{
        for (final MapEntry<String, Object?> e
            in ((json['params'] as Map<String, Object?>?) ??
                    const <String, Object?>{})
                .entries)
          if (e.value != null) e.key: e.value!,
      });

  final String key;
  final Map<String, Object> params;

  Map<String, Object> toJson() => <String, Object>{
    'key': key,
    'params': params,
  };

  @override
  bool operator ==(Object other) =>
      other is ClientDietSentence &&
      other.key == key &&
      other.params.length == params.length &&
      params.entries.every(
        (MapEntry<String, Object> e) => other.params[e.key] == e.value,
      );

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(params.keys));

  @override
  String toString() => 'ClientDietSentence($key, $params)';
}

/// 한 기간의 `식단 분석` — 문장들. 비어 있으면 카드를 세우지 않는다.
class ClientDietAnalysis {
  const ClientDietAnalysis(this.sentences);

  static const ClientDietAnalysis empty = ClientDietAnalysis(
    <ClientDietSentence>[],
  );

  final List<ClientDietSentence> sentences;

  bool get isEmpty => sentences.isEmpty;
}

/// 회원에게 추천할 AI 후보 한 개 — 회원의 4주 추천 메뉴 리스트의 한 줄. (#2378)
class ClientDietCandidate {
  const ClientDietCandidate({
    required this.slot,
    required this.name,
    required this.tag,
    this.keyword = '',
    this.kcal = 0,
    this.proteinG = 0,
    this.sodiumMg = 0,
    this.urgent = false,
  });

  factory ClientDietCandidate.fromJson(Map<String, Object?> json) =>
      ClientDietCandidate(
        slot: (json['slot'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        tag: (json['tag'] as String?) ?? '',
        keyword: (json['keyword'] as String?) ?? '',
        kcal: (json['kcal'] as num?)?.toInt() ?? 0,
        proteinG: (json['protein_g'] as num?)?.toInt() ?? 0,
        sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
        urgent: (json['urgent'] as bool?) ?? false,
      );

  /// `breakfast`·`lunch`·`dinner`·`snack`.
  final String slot;
  final String name;

  /// 추천 이유 태그 — `sodium_low`·`protein_high`·`calorie_low`·`calorie_high`·
  /// `sugar_low`·`fiber_high`.
  final String tag;

  /// 리스트 언어의 짧은 이유(`고단백` …).
  final String keyword;

  /// 1인분 추정치. 모르면 0(데모 리스트)이고, 화면은 0 인 값을 적지 않는다.
  final int kcal;
  final int proteinG;
  final int sodiumMg;

  /// 회원의 급한 태그를 채우는 메뉴인가.
  final bool urgent;
}

/// 트레이너가 확정한 추천의 지금 상태.
class ClientDietPick {
  const ClientDietPick({
    required this.slot,
    required this.name,
    required this.tag,
    this.keyword = '',
    required this.resolved,
    required this.confirmedAt,
    this.resolvedAt,
  });

  factory ClientDietPick.fromJson(Map<String, Object?> json) => ClientDietPick(
    slot: (json['slot'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    tag: (json['tag'] as String?) ?? '',
    keyword: (json['keyword'] as String?) ?? '',
    resolved: json['status'] == 'resolved',
    confirmedAt:
        DateTime.tryParse((json['confirmed_at'] as String?) ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    resolvedAt: DateTime.tryParse(
      (json['resolved_at'] as String?) ?? '',
    )?.toLocal(),
  );

  final String slot;
  final String name;
  final String tag;
  final String keyword;

  /// 회원이 그 메뉴를 기록해 홈에서 내려갔다.
  final bool resolved;
  final DateTime confirmedAt;
  final DateTime? resolvedAt;
}

/// `GET /trainer/clients/{id}/diet-recommendations` 응답. (#2378)
class ClientDietRecommendations {
  const ClientDietRecommendations({
    this.needs = const <String>[],
    this.basisDays = 0,
    this.pick,
    this.candidates = const <ClientDietCandidate>[],
  });

  factory ClientDietRecommendations.fromJson(Map<String, Object?> json) =>
      ClientDietRecommendations(
        needs: <String>[
          for (final Object? n in (json['needs'] as List<Object?>?) ?? const [])
            if (n is String) n,
        ],
        basisDays: (json['basis_days'] as num?)?.toInt() ?? 0,
        pick: switch (json['pick']) {
          final Map<String, Object?> p => ClientDietPick.fromJson(p),
          _ => null,
        },
        candidates: <ClientDietCandidate>[
          for (final Object? c
              in (json['candidates'] as List<Object?>?) ?? const [])
            if (c is Map<String, Object?>) ClientDietCandidate.fromJson(c),
        ],
      );

  /// 최근 4주 평균이 목표에서 벗어난 태그 — 비면 채울 점이 없다.
  final List<String> needs;
  final int basisDays;
  final ClientDietPick? pick;
  final List<ClientDietCandidate> candidates;
}
