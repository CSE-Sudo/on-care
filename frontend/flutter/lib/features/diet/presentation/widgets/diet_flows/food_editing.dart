// 결과 시트·직접 추가·수정 화면이 함께 쓰는 음식 편집 동작과 편집 상태.

part of '../diet_flows.dart';

/// 끼니의 음식 목록을 고치는 편집기. 식단 상세의 수정 모드와 분석 완료
/// 시트의 수정 모드가 함께 쓴다(#2097).
///
/// 음식별 입력 칸, 섭취량 비례 환산(#1876), 공공 DB 제안(#1896), 당류 검사
/// (#1869), 영양 출처(#2105), 탄단지를 따라가는 열량(#2106), 이름을 바꾸면
/// 그 음식의 값(#2107)이 여기 모여 있다. 두 화면이 따로 들고 있으면 한쪽만
/// 고쳐져 같은 음식이 화면마다 다르게 고쳐진다.
///
/// 처음 값은 [_loadFoods] 로 깐다.
mixin _FoodEditing<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  List<DietFood> _foods = <DietFood>[];

  /// 음식 줄마다 하나씩. 컨트롤러를 줄 위젯이 아니라 시트가 들고 있어야
  /// 한 자 칠 때마다 새로 만들어지지 않는다 — 새로 만들면 커서가 맨 앞으로
  /// 튄다. 목록 순서와 1:1 로 붙어 다닌다(#1844).
  final List<_FoodEditors> _editors = <_FoodEditors>[];

  /// 음식마다 당류가 그 음식의 탄수화물을 넘지 않는지 본다(#1869). 당류는
  /// 탄수화물의 일부라 그보다 클 수 없고, 서버도 같은 값을 422 로 거절한다
  /// (#1863) — 앱이 먼저 막지 않으면 다 적고 저장을 누른 뒤에야 어느 칸이
  /// 문제인지 모르는 실패 토스트만 뜬다.
  ///
  /// 줄 번호가 아니라 [_FoodEditors] 를 키로 쓴다. 음식을 지우면 아래 줄의
  /// 번호가 당겨지므로, 번호로 기억해 두면 엉뚱한 줄에 빨간 글씨가 남는다.
  late AppFieldErrors<_FoodEditors> _sugarErrors = AppFieldErrors<_FoodEditors>(
    _checkSugar,
  );

  /// 이름 칸을 벗어나면 공공 DB 를 찾는다(#1896). 줄이 지워지거나 순서가 밀려도
  /// 어긋나지 않도록 **자리(index)가 아니라 그 줄 자체**를 붙잡는다.
  _FoodEditors _watchName(_FoodEditors e) {
    e.nameFocus.addListener(() {
      if (!e.nameFocus.hasFocus) unawaited(_lookupNutrition(e));
    });
    return e;
  }

  /// 이 끼니에 탄수화물이 적혀 있었나 — 저장된 값 기준이다(#1893).
  ///
  /// 탄수화물 0 은 두 가지다. 인식기가 그 값을 못 준 옛 기록의 0 과, 회원이
  /// 방금 지운 0. 앞은 봐주지 않으면 그 기록을 영영 고칠 수 없고, 뒤는
  /// 봐주면 탄수화물을 지워 검사를 피할 수 있다. 서버도 `entry.carbs_g` 로
  /// 같은 판단을 하므로, 저장에 성공할 때마다 함께 갱신한다.
  bool _carbsRecorded = false;

  double _carbsOf(List<DietFood> foods) =>
      foods.fold<double>(0, (double a, DietFood f) => a + f.carbsG);

  /// 편집기를 [foods] 로 새로 깐다. 처음 열 때와 `취소` 로 되돌릴 때 쓴다.
  ///
  /// setState 는 부르지 않는다 — 부르는 쪽이 제 상태와 함께 한 번에 바꾼다.
  /// 버리는 컨트롤러는 그 줄이 트리에서 물러난 다음 프레임에 버린다.
  void _loadFoods(List<DietFood> foods) {
    final List<_FoodEditors> stale = List<_FoodEditors>.of(_editors);
    _foods = List<DietFood>.of(foods);
    _editors
      ..clear()
      ..addAll(<_FoodEditors>[
        for (final DietFood f in _foods) _watchName(_FoodEditors.of(f)),
      ]);
    // 접었다 다시 펴면 오류도 처음부터다 — 저장을 누른 적 없는 화면에
    // 빨간 글씨가 먼저 서 있으면 안 된다(#1784).
    _sugarErrors = AppFieldErrors<_FoodEditors>(_checkSugar);
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final _FoodEditors e in stale) {
        e.dispose();
      }
    });
  }

  int get _total => _foods.fold(0, (int a, DietFood f) => a + f.kcal);

  // 영양 합계는 저장된 끼니가 아니라 지금 화면의 음식에서 낸다. 서버도 같은
  // 규칙으로 합치므로(`_sumMacro`), 음식을 고치면 저장 전에도 합계가 따라와야
  // 한 화면에 서로 다른 숫자가 남지 않는다(#1856).
  double _sumOf(double Function(DietFood) pick) =>
      _foods.fold<double>(0, (double a, DietFood f) => a + pick(f));

  double get _carbs => _sumOf((DietFood f) => f.carbsG);
  double get _protein => _sumOf((DietFood f) => f.proteinG);
  double get _fat => _sumOf((DietFood f) => f.fatG);
  double get _sugar => _sumOf((DietFood f) => f.sugarG);
  int get _sodium => _foods.fold(0, (int a, DietFood f) => a + f.sodiumMg);

  @override
  void dispose() {
    for (final _FoodEditors e in _editors) {
      e.dispose();
    }
    super.dispose();
  }

  /// 빈 칸과 알아볼 수 없는 글자는 0 으로 읽는다 — 칸을 비워 지우는 것이
  /// 0 을 적는 것과 같은 뜻이 되게.
  static int _asInt(TextEditingController c) =>
      int.tryParse(c.text.trim()) ?? 0;
  static double _asDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  /// 섭취량 칸의 값. 여기서만 빈 칸이 0 이 아니라 **null** 이다 — 0g 을 먹었다는
  /// 기록은 없고, 0 은 비례 환산의 분모가 될 수도 없다.
  static double? _asAmount(TextEditingController c) {
    final double? grams = double.tryParse(c.text.trim());
    return (grams != null && grams > 0) ? grams : null;
  }

  /// 지금 그 음식 칸에 적힌 값을 비례 환산의 기준으로 세운다.
  ///
  /// 회원이 영양 칸을 직접 고쳤다는 것은 "이 양에서는 이 값이 맞다" 고 말한
  /// 것이다. 그러니 다음 섭취량 변경은 분석이 준 값이 아니라 회원이 고친 값에서
  /// 비례해야 한다. 섭취량 칸이 비어 있으면 기준 없이 둔다.
  void _captureBasis(int index) {
    final _FoodEditors e = _editors[index];
    final double? amount = _asAmount(e.amount);
    e.basis = amount == null
        ? null
        : _FoodBasis(
            amountG: amount,
            kcal: _asInt(e.kcal),
            carbsG: _asDouble(e.carbs),
            sugarG: _asDouble(e.sugar),
            proteinG: _asDouble(e.protein),
            fatG: _asDouble(e.fat),
            sodiumMg: _asInt(e.sodium),
          );
  }

  /// 당류 칸에 보일 오류 문구. 맞으면 null 이다.
  ///
  /// 서버의 `_sugar_exceeds_carbs` 와 같은 규칙이다(#1893). 앱이 더 엄격하면
  /// 서버가 받아 주는 값을 저장할 수 없고, 더 느슨하면 다 적고 저장을 누른
  /// 뒤에야 어느 칸이 문제인지 모르는 실패 토스트만 뜬다.
  String? _checkSugar(_FoodEditors e) {
    final double carbs = _asDouble(e.carbs);
    // 같은 값은 통과한다 — 전부 당인 음식이 있다.
    if (_asDouble(e.sugar) <= carbs) return null;
    // 탄수화물 0 을 어떻게 볼지는 [_carbsRecorded] 가 정한다. 이 끼니에
    // 탄수화물이 처음부터 없었다면 인식기가 그 값을 못 준 기록이라 봐주고
    // (#1877), 회원이 방금 0 으로 바꾼 0 은 적은 값으로 본다.
    if (carbs <= 0 && !_carbsRecorded) return null;
    return AppLocalizations.of(context).dietSugarOverCarbs;
  }

  /// 그 음식의 입력 칸을 모두 읽어 `_foods` 에 반영한다. 한 칸만 바뀌어도
  /// 전부 다시 읽는 편이 칸마다 따로 갈래를 두는 것보다 흘릴 값이 없다.
  /// 매 글자마다 부르는 이유는 아래 총 칼로리와 영양 정보 합계가 입력을
  /// 곧바로 따라와야 하기 때문이다.
  ///
  /// [rebase] 는 지금 값을 비례 환산의 새 기준으로 삼을지다. 영양 칸을 직접
  /// 고쳤을 때는 그래야 하고, 섭취량이 움직여 값이 따라온 직후에는 안 된다 —
  /// 거기서 기준을 다시 세우면 원본 대신 방금 반올림된 값에서 다음 곱셈이
  /// 시작된다([_FoodBasis]).
  void _syncFood(int index, {bool rebase = true}) {
    final _FoodEditors e = _editors[index];
    if (rebase) _captureBasis(index);
    setState(() {
      _foods = <DietFood>[..._foods]
        ..[index] = DietFood(
          e.name.text,
          _asInt(e.kcal),
          amountG: _asAmount(e.amount),
          sodiumMg: _asInt(e.sodium),
          sugarG: _asDouble(e.sugar),
          carbsG: _asDouble(e.carbs),
          proteinG: _asDouble(e.protein),
          fatG: _asDouble(e.fat),
          source: e.source,
          // 이름을 그대로 두었는지는 저장할 때 [DietFood.wireName] 이 가린다.
          displayName: _foods[index].displayName,
          storedName: _foods[index].storedName,
        );
    });
  }

  /// 영양 칸 하나를 손으로 고쳤을 때. 그 음식의 값은 이제 **회원이 적은 값**이다
  /// (#2105) — 분석이나 공공 DB 가 준 숫자가 아니니 출처를 [FoodSource.member]
  /// 로 바꾼다. 탄단지를 고친 결과로 열량이 따라온 것도 마찬가지다.
  ///
  /// [kcal] 은 열량 칸을, [macro] 는 탄수화물·단백질·지방 칸을 고쳤다는 뜻이다.
  /// 당류·나트륨은 둘 다 아니다 — 열량에 들어가지 않는다(당류는 탄수화물의 일부).
  void _editNutrient(int index, {bool kcal = false, bool macro = false}) {
    final _FoodEditors e = _editors[index];
    // 열량을 직접 적었으면 그 음식은 이번 편집 동안 자동 반영을 멈춘다(#2106).
    // 라벨 값을 옮겨 적는 중이면, 칸을 어느 순서로 적든 라벨 열량이 남아야 한다.
    if (kcal) e.kcalPinned = true;
    if (macro) _followKcal(e);
    e
      ..source = FoodSource.member
      ..edits += 1
      // 값을 손으로 고쳤으니 "DB 값으로 바꿨어요 · 되돌리기" 는 낡았고, "값을
      // 확인해 주세요" 는 할 일을 했다.
      ..notice = null;
    _syncFood(index);
  }

  /// 탄단지가 바뀐 **만큼만** 열량을 움직인다. (#2106)
  ///
  /// `새 열량 = 기준 열량 + 4×Δ탄수화물 + 4×Δ단백질 + 9×Δ지방`. 4·4·9 로 새로
  /// 계산해 덮지 않는 이유는 공공 DB 열량이 식품마다 다른 에너지 환산계수를 써서다
  /// — 삼겹살 구운것은 100g 484kcal 인데 4·4·9 로는 462kcal 다. 새로 계산하면
  /// 지방만 줄였는데도 성분표가 알던 몫이 함께 사라진다.
  ///
  /// 기준은 한 글자마다 다시 세우지 않는다([_EnergyBasis]).
  void _followKcal(_FoodEditors e) {
    if (e.kcalPinned || e.fillOnly) return;
    e.kcal.text = _FoodEditors.intText(
      e.energy.kcalFor(
        carbsG: _asDouble(e.carbs),
        proteinG: _asDouble(e.protein),
        fatG: _asDouble(e.fat),
      ),
    );
  }

  /// 섭취량 칸이 바뀌었을 때 — 영양 여섯 값이 같은 비율로 따라온다. (#1876)
  ///
  /// 공공 영양 DB 는 100g 기준이고 서버 보정이 그 양으로 환산해 둔 값이 지금
  /// 칸에 적혀 있다. 그러니 양이 바뀌었을 때 필요한 것은 DB 재조회가 아니라
  /// 곱셈 한 번이다 — `새 값 = 기준 값 × (새 양 / 기준 양)`.
  void _syncAmount(int index) {
    final _FoodEditors e = _editors[index];
    final _FoodBasis? basis = e.basis;
    if (basis == null) {
      // 양을 모르던 음식이다. 지금 적어 넣은 값이 기준이 될 뿐, 영양은
      // 그대로 둔다 — 모르던 양을 적었다고 영양이 튀면 적기가 무서워진다.
      _syncFood(index);
      return;
    }
    final double? amount = _asAmount(e.amount);
    if (amount != null) {
      final double factor = amount / basis.amountG;
      e.kcal.text = _FoodEditors.intText((basis.kcal * factor).round());
      e.carbs.text = _FoodEditors.gramText(basis.carbsG * factor);
      e.sugar.text = _FoodEditors.gramText(basis.sugarG * factor);
      e.protein.text = _FoodEditors.gramText(basis.proteinG * factor);
      e.fat.text = _FoodEditors.gramText(basis.fatG * factor);
      e.sodium.text = _FoodEditors.intText((basis.sodiumMg * factor).round());
      // 방금 곱해 적은 한 벌은 서로 맞는 값이다 — 이어서 탄단지를 고치면 열량은
      // 이 값에서 바뀐 만큼 움직여야 한다(#2106).
      e.energy = e.readEnergy();
    }
    // 칸을 비웠을 때는 영양을 건드리지 않는다. 양을 적지 않겠다는 뜻이지 아무
    // 것도 안 먹었다는 뜻이 아니다. 기준도 그대로 두어, 다시 적으면 처음 그
    // 한 벌에서 비례한다 — 지우고 고쳐 쓰는 동안 값이 조금씩 어긋나지 않는다.
    //
    // 출처는 그대로다(#2105). 양만 바꾼 음식은 여전히 DB × 양이고, 추정은
    // 추정 × 양이다. 다만 "DB 값으로 바꿨어요 · 되돌리기" 는 거둔다 — 되돌리면
    // 방금 적은 양까지 되돌아가 버린다.
    if (e.notice is _FilledFromDb) e.notice = null;
    _syncFood(index, rebase: false);
  }

  /// 이름 칸을 벗어났을 때 공공 영양 DB 를 찾는다. (#1896, #2107)
  ///
  /// 이름을 **바꿨다면** 칸의 값은 이제 다른 음식의 것이다. 옛 음식의 값이 새
  /// 이름 아래 조용히 남는 것이 가장 부정확하므로, 찾은 결과에 따라 셋으로 나눈다.
  ///
  /// - **같은 음식**이 DB 에 있으면(이름·별칭·표기 변형이 같다) 곧바로 그 값으로
  ///   채우고 "무엇으로 바꿨는지 · 되돌리기" 를 띄운다. 되돌릴 수 있어야 손으로
  ///   바로잡아 둔 값이 소리 없이 사라지지 않는다 — #1896 이 제안만 하던 까닭이다.
  /// - **비슷한 음식**만 있으면(이름 끝말로 붙었다) 제안만 한다. 끝말로 붙은 값은
  ///   틀린 경우가 많아 회원이 보고 골라야 한다(서버 `matcher.find_in_rows`).
  /// - 없으면 값은 두고 확인해 달라고 말한다.
  ///
  /// 이름을 바꾸지 않고 칸만 드나들었으면 예전처럼 제안만 한다. 조회가 도는 사이
  /// 회원이 영양 칸을 고쳤으면 그 값이 이긴다 — 덮지 않고 제안으로 남긴다.
  ///
  /// 지금 적힌 양을 함께 보낸다 — 그 양의 값이어야 회원이 "내가 먹은 만큼" 을
  /// 보게 된다. 사진 속 그릇의 양은 이름이 바뀌어도 같다. 양이 없으면 서버가 그
  /// 음식의 1회 섭취량으로 답한다.
  Future<void> _lookupNutrition(_FoodEditors e) async {
    final String name = e.name.text.trim();
    if (name.isEmpty) {
      // 이름을 지웠는데 아까 제안이 남아 있으면 그게 무엇의 제안인지 알 수 없다.
      if (e.suggestion != null || e.lookedUpName != null || e.notice != null) {
        setState(() {
          e.suggestion = null;
          e.lookedUpName = null;
          e.notice = null;
        });
      }
      return;
    }
    if (name == e.lookedUpName) return;
    e.lookedUpName = name;
    final bool renamed = name != e.valuesName;
    final int editsBefore = e.edits;
    FoodNutritionSuggestion? found;
    bool failed = false;
    try {
      found = await ref
          .read(dietRepositoryProvider)
          .lookupFoodNutrition(name: name, amountG: _asAmount(e.amount));
    } on Object {
      // 조회가 실패해도 수정과 저장은 그대로 된다. 찾기는 거들 뿐이라
      // 여기서 막을 이유가 없다.
      failed = true;
    }
    // 그 사이 이름이 또 바뀌었거나 그 줄이 지워졌으면 이 응답은 낡은 값이다.
    final int index = _editors.indexOf(e);
    if (!mounted || e.lookedUpName != name || index < 0) return;
    if (!renamed) {
      setState(() => e.suggestion = found);
      return;
    }
    // 여기부터 칸의 값은 새 이름의 것으로 본다 — 같은 이름으로 다시 드나들어도
    // 이름 변경으로 세지 않는다.
    e.valuesName = name;
    if (found != null && found.exact && e.edits == editsBefore) {
      _fillFrom(index, found, announce: true);
      return;
    }
    setState(() {
      e
        ..suggestion = found
        // 옛 음식의 값이 새 이름 아래 남았다 — 공공 DB 나 분석이 이 이름에 대해
        // 말한 숫자가 아니다(#2105).
        ..source = FoodSource.member
        // 없다는 것을 알 때만 말한다. 조회가 실패했으면 없는 음식인지 모른다.
        ..notice = (found == null && !failed) ? const _NotInDb() : null;
    });
    _syncFood(index, rebase: false);
  }

  /// 제안을 적용하면 달라지는 값이 있나. 없으면 제안을 띄우지 않는다 —
  /// 이미 그 값인데 `값 채우기` 가 서 있으면 누를 이유를 찾게 된다.
  bool _suggestionWouldChange(_FoodEditors e) {
    final FoodNutritionSuggestion? s = e.suggestion;
    final _FoodBasis? filled = s == null ? null : _filledBy(e, s);
    return filled != null && _wouldChange(e, filled);
  }

  /// [filled] 로 채우면 지금 칸과 달라지는 값이 있나.
  bool _wouldChange(_FoodEditors e, _FoodBasis filled) {
    bool sameGram(double a, double b) => (a - b).abs() < 0.05;
    return !(filled.kcal == _asInt(e.kcal) &&
        filled.sodiumMg == _asInt(e.sodium) &&
        sameGram(filled.carbsG, _asDouble(e.carbs)) &&
        sameGram(filled.sugarG, _asDouble(e.sugar)) &&
        sameGram(filled.proteinG, _asDouble(e.protein)) &&
        sameGram(filled.fatG, _asDouble(e.fat)) &&
        sameGram(filled.amountG, _asAmount(e.amount) ?? 0));
  }

  /// 제안을 **지금 적힌 양에 맞춰** 환산한 한 벌.
  ///
  /// 회원이 이미 양을 적어 두었으면 그 양이 이긴다 — 제안을 받았다고 내가 적은
  /// 양이 뒤집히면 안 된다. 양이 없을 때만 제안이 들고 온 1회 섭취량을 쓴다.
  /// 곱셈은 #1876 의 비례 환산과 같은 계산이다.
  _FoodBasis? _filledBy(_FoodEditors e, FoodNutritionSuggestion s) {
    final double? base = s.food.amountG;
    if (base == null || base <= 0) return null;
    final double target = _asAmount(e.amount) ?? base;
    final double factor = target / base;
    return _FoodBasis(
      amountG: target,
      kcal: (s.food.calories * factor).round(),
      carbsG: s.food.carbsG * factor,
      sugarG: s.food.sugarG * factor,
      proteinG: s.food.proteinG * factor,
      fatG: s.food.fatG * factor,
      sodiumMg: (s.food.sodiumMg * factor).round(),
    );
  }

  /// `값 채우기` — 제안한 값으로 그 음식의 칸을 채운다.
  void _applySuggestion(int index) {
    final FoodNutritionSuggestion? s = _editors[index].suggestion;
    if (s != null) _fillFrom(index, s);
  }

  /// 공공 DB 에서 찾은 값으로 그 음식의 칸을 채운다. `값 채우기` 와, 같은
  /// 음식으로 이름을 바꿨을 때(#2107)가 같은 길을 쓴다.
  ///
  /// 채운 한 벌은 서로 맞는 값이라 모든 기준이 여기서 다시 선다 — 이어서 내용량을
  /// 고치면 #1876 의 비례 환산이, 탄단지를 고치면 #2106 의 열량 반영이 이 값에서
  /// 출발한다. 출처는 찾은 값의 것이다(#2105).
  ///
  /// [announce] 면 무엇으로 바꿨는지 말하고 되돌릴 수 있게 한다. 회원이 누르지
  /// 않았는데 값이 바뀌었기 때문이다.
  void _fillFrom(
    int index,
    FoodNutritionSuggestion found, {
    bool announce = false,
  }) {
    final _FoodEditors e = _editors[index];
    final _FoodBasis? filled = _filledBy(e, found);
    if (filled == null) return;
    final bool changes = _wouldChange(e, filled);
    final _FoodSnapshot before = _FoodSnapshot.of(e);
    e.amount.text = _FoodEditors.gramText(filled.amountG);
    e.kcal.text = _FoodEditors.intText(filled.kcal);
    e.carbs.text = _FoodEditors.gramText(filled.carbsG);
    e.sugar.text = _FoodEditors.gramText(filled.sugarG);
    e.protein.text = _FoodEditors.gramText(filled.proteinG);
    e.fat.text = _FoodEditors.gramText(filled.fatG);
    e.sodium.text = _FoodEditors.intText(filled.sodiumMg);
    e
      ..source = found.food.source
      ..valuesName = e.name.text.trim()
      ..energy = e.readEnergy()
      ..kcalPinned = false
      ..fillOnly = false;
    setState(() {
      // 제안을 거둔다 — 방금 그 값으로 채웠으니 더 제안할 것이 없다.
      e.suggestion = null;
      // 이미 그 값이었으면 바뀐 것이 없으니 말할 것도 없다.
      e.notice = announce && changes ? _FilledFromDb(found, before) : null;
    });
    _syncFood(index);
  }

  /// `되돌리기` — 이름을 바꿔 채운 값을 바꾸기 전으로 되돌린다(#2107).
  ///
  /// 이름은 새 이름 그대로다. 옛 값을 새 이름 아래 두기로 한 것이니 출처는
  /// 회원의 몫이다(#2105). 찾은 값은 제안으로 남겨 다시 고를 수 있게 한다.
  void _undoFill(int index) {
    final _FoodEditors e = _editors[index];
    final _NameNotice? notice = e.notice;
    if (notice is! _FilledFromDb) return;
    notice.before.restoreTo(e);
    e.source = FoodSource.member;
    setState(() {
      e.notice = null;
      e.suggestion = notice.found;
    });
    _syncFood(index, rebase: false);
  }

  void _addFood() {
    // Empty draft name; the localized label is shown only as a placeholder
    // and is validated out on save. 새 줄의 값은 회원이 적는다(#2105) — 공공 DB
    // 값으로 채우면 그때 출처가 바뀐다.
    const DietFood draft = DietFood('', 0, source: FoodSource.member);
    setState(() {
      _foods = <DietFood>[..._foods, draft];
      // 새 줄에서도 이름만 적으면 공공 DB 값을 제안받는다 — 오히려 이쪽이 더
      // 요긴하다. 일곱 칸을 손으로 채우지 않아도 된다(#1896).
      _editors.add(_watchName(_FoodEditors.of(draft)));
    });
  }

  void _removeFood(int index) {
    final _FoodEditors removed = _editors.removeAt(index);
    setState(() => _foods = <DietFood>[..._foods]..removeAt(index));
    // 이번 프레임에는 아직 지워진 줄이 트리에 남아 있다 — 그 줄이 물러난
    // 뒤에 버린다.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  /// 저장할 음식. 이름이 빈 줄은 버린다 — 새 줄의 자리표시 문구
  /// (`dietNewFood`)가 음식 이름으로 저장되지 않게.
  ///
  /// 영양은 이름·칼로리와 함께 되돌려 보낸다. 빠뜨리면 이 저장 한 번으로
  /// 그 끼니의 탄단지·나트륨·당류가 0 이 된다 — 합계가 음식별 값에서
  /// 계산되기 때문이다(#1853).
  List<FoodItem> _foodPayload() => <FoodItem>[
    for (final DietFood f in _foods)
      if (f.name.trim().isNotEmpty)
        FoodItem(
          name: f.wireName.name,
          displayName: f.wireName.displayName,
          calories: f.kcal,
          amountG: f.amountG,
          sodiumMg: f.sodiumMg,
          sugarG: f.sugarG,
          carbsG: f.carbsG,
          proteinG: f.proteinG,
          fatG: f.fatG,
          source: f.source,
        ),
  ];

  /// 보낼 줄만 검사한다 — 이름이 빈 줄은 [_foodPayload] 가 버리므로, 거기
  /// 남은 숫자 때문에 저장이 막히면 어디를 고쳐야 하는지 알 수 없다.
  /// 틀린 칸이 있으면 그 아래에 이유를 세우고 false 다(#1869).
  bool _validateFoods() {
    final List<_FoodEditors> filled = <_FoodEditors>[
      for (int i = 0; i < _foods.length; i++)
        if (_foods[i].name.trim().isNotEmpty) _editors[i],
    ];
    if (_sugarErrors.validate(filled)) return true;
    setState(() {});
    return false;
  }

  /// 끼니·음식을 기록에 반영한다. 날짜는 보내지 않는다 — `날짜 변경` 이 따로
  /// 옮긴다(#1947).
  Future<void> _saveFoods({
    required String id,
    required MealType mealType,
    required List<FoodItem> foods,
  }) {
    return ref
        .read(dietRepositoryProvider)
        .updateEntry(
          id: id,
          mealType: mealType.name,
          foods: foods,
          totalCalories: foods.fold<int>(
            0,
            (int a, FoodItem f) => a + f.calories,
          ),
          // 나트륨·당류는 끼니 행에도 따로 저장된다 — 음식에서 다시 합쳐
          // 보내지 않으면 음식별 값만 바뀌고 끼니 합계는 옛 숫자에 머문다.
          sodiumMg: foods.fold<int>(0, (int a, FoodItem f) => a + f.sodiumMg),
          sugarG: foods.fold<double>(0, (double a, FoodItem f) => a + f.sugarG),
        );
  }

  /// `총 칼로리` 줄. 식단 상세와 직접 추가가 함께 쓴다.
  Widget _totalRow(BuildContext context, AppLocalizations l) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            l.dietTotalCalories,
            style: _text(
              context,
              OnCareTypography.strong(OnCareTypography.bodySmall),
              OnCareColors.textPrimary,
            ),
          ),
        ),
        Text(
          l.unitKcalValue(_total),
          key: const Key('meal-total'),
          style: OnCareTypography.numeric(
            _text(context, OnCareTypography.titleSmall, tokens.brand.primary),
          ),
        ),
      ],
    );
  }

  /// 지금 화면의 음식에서 낸 영양 합계 카드. 식단 상세와 직접 추가가 함께
  /// 쓴다 — 두 화면이 같은 순서·같은 서식으로 읽혀야 한다.
  Widget _nutritionCard(BuildContext context, AppLocalizations l) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _FieldLabel(l.dietNutritionInfo),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.dietEditNutritionHint,
            style: _text(
              context,
              OnCareTypography.caption,
              OnCareColors.textSecondary,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 탄단지가 기준이다. 당류는 탄수화물의 일부라 바로 아래에 들여 붙이고,
          // 나트륨은 탄단지가 아니라 맨 끝에 둔다. 지방은 포화·트랜스까지 나누지
          // 않는다 — 분석이 그만큼 재지 못한다.
          _NutrientRow(
            label: l.homeMacroCarbs,
            value: _gramsText(_carbs),
            unit: l.dietUnitG,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.dietSugar,
            value: _gramsText(_sugar),
            unit: l.dietUnitG,
            sub: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.homeMacroProtein,
            value: _gramsText(_protein),
            unit: l.dietUnitG,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.homeMacroFat,
            value: _gramsText(_fat),
            unit: l.dietUnitG,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.dietSodium,
            value: '$_sodium',
            unit: l.dietUnitMg,
          ),
        ],
      ),
    );
  }

  /// 음식 한 줄의 수정 칸.
  Widget _foodEditor(int i) => _FoodEditBlock(
    index: i + 1,
    editors: _editors[i],
    sugarError: _sugarErrors.of(_editors[i]),
    // 이름만 바뀐 동안에는 기준을 다시 세우지 않는다 — 값은 그대로다. 이름이
    // 값에 닿는 것은 칸을 벗어난 뒤다([_lookupNutrition]).
    onNameChanged: () => _syncFood(i, rebase: false),
    onAmountChanged: () => _syncAmount(i),
    onKcalChanged: () => _editNutrient(i, kcal: true),
    onMacroChanged: () => _editNutrient(i, macro: true),
    onChanged: () => _editNutrient(i),
    onDelete: () => _removeFood(i),
    suggestion: _suggestionWouldChange(_editors[i])
        ? _editors[i].suggestion
        : null,
    onApplySuggestion: () => _applySuggestion(i),
    onUndoFill: () => _undoFill(i),
  );
}

/// 섭취량을 고칠 때 비례 환산이 출발하는 자리 — **그 양일 때의 영양 한 벌**.
///
/// 화면에 적힌 값에서 곱해 나가지 않는 이유가 여기 있다. `300` 은 한 번에
/// 들어오지 않고 `3` → `30` → `300` 으로 들어오는데, 그때마다 칸의 값을
/// 곱하면 칼로리·나트륨의 정수 반올림이 단계마다 쌓여 같은 300g 인데
/// 555kcal 이 아니라 600kcal 이 남는다. 곱셈은 늘 이 원본 한 벌에서 한 번만
/// 한다. (#1876)
class _FoodBasis {
  const _FoodBasis({
    required this.amountG,
    required this.kcal,
    required this.carbsG,
    required this.sugarG,
    required this.proteinG,
    required this.fatG,
    required this.sodiumMg,
  });

  /// 이 한 벌이 잰 양. 늘 0 보다 크다 — 0 은 나눌 수도, 기준이 될 수도 없다.
  final double amountG;
  final int kcal;
  final double carbsG;
  final double sugarG;
  final double proteinG;
  final double fatG;
  final int sodiumMg;
}

/// 탄단지를 고칠 때 열량이 출발하는 자리 — **서로 맞는 열량·탄·단·지 한 벌.**
/// (#2106)
///
/// 섭취량의 기준([_FoodBasis])과 따로 둔다. 그쪽은 영양 칸을 고칠 때마다 지금
/// 값으로 다시 서는데, 열량의 기준까지 그렇게 하면 `128` 을 치는 동안 `1` 다음
/// 부터는 기준에 탄수화물이 생겨 탄단지 없던 기록의 "채우기" 가 "늘리기" 로
/// 읽히고, 정수 반올림도 글자마다 쌓인다. 그래서 이 한 벌은 앱이 서로 맞는 값을
/// 한꺼번에 적은 때에만 다시 선다 — 편집을 열 때, 섭취량 비례 환산 직후, 공공 DB
/// 값으로 채운 직후.
class _EnergyBasis {
  const _EnergyBasis({
    required this.kcal,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });

  final int kcal;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 탄단지 없이 열량만 있는 한 벌 — 인식기가 탄단지를 주지 않은 옛 기록이다
  /// (#1877). 여기에 탄단지를 적는 것은 이미 열량에 든 성분을 **채워 넣는** 것이지
  /// 늘리는 것이 아니다. 반영하면 두 번 센다(700kcal 짜장면에 탄수화물 128g 을
  /// 채우면 1,212kcal).
  bool get onlyKcal => kcal > 0 && carbsG == 0 && proteinG == 0 && fatG == 0;

  /// 탄단지가 이 값들로 바뀌었을 때의 열량 — 바뀐 만큼만 더하고 뺀다. 0 아래로
  /// 내려가지 않는다.
  int kcalFor({
    required double carbsG,
    required double proteinG,
    required double fatG,
  }) {
    final double next =
        kcal +
        4 * (carbsG - this.carbsG) +
        4 * (proteinG - this.proteinG) +
        9 * (fatG - this.fatG);
    return next <= 0 ? 0 : next.round();
  }
}

/// 이름 칸 아래에 서는 한 줄 안내(#2107). 제안(`값 채우기`)과는 다르다 — 이미
/// 일어난 일을 말한다.
sealed class _NameNotice {
  const _NameNotice();
}

/// 같은 음식의 공공 DB 값으로 바꿨다. 무엇으로 바꿨는지 말하고 되돌릴 수 있게
/// 한다 — 회원이 누르지 않았는데 값이 바뀌었다.
final class _FilledFromDb extends _NameNotice {
  const _FilledFromDb(this.found, this.before);

  final FoodNutritionSuggestion found;

  /// 바꾸기 전의 칸. `되돌리기` 가 여기로 돌아간다.
  final _FoodSnapshot before;
}

/// 공공 DB 에 없는 이름이다. 값은 옛 음식의 것 그대로라 확인해 달라고 말한다.
final class _NotInDb extends _NameNotice {
  const _NotInDb();
}

/// 한 음식 줄의 칸과 기준을 통째로 적어 둔 것 — `되돌리기` 가 돌아갈 자리(#2107).
class _FoodSnapshot {
  _FoodSnapshot.of(_FoodEditors e)
    : amount = e.amount.text,
      kcal = e.kcal.text,
      carbs = e.carbs.text,
      sugar = e.sugar.text,
      protein = e.protein.text,
      fat = e.fat.text,
      sodium = e.sodium.text,
      basis = e.basis,
      energy = e.energy,
      kcalPinned = e.kcalPinned,
      fillOnly = e.fillOnly;

  final String amount;
  final String kcal;
  final String carbs;
  final String sugar;
  final String protein;
  final String fat;
  final String sodium;
  final _FoodBasis? basis;
  final _EnergyBasis energy;
  final bool kcalPinned;
  final bool fillOnly;

  void restoreTo(_FoodEditors e) {
    e.amount.text = amount;
    e.kcal.text = kcal;
    e.carbs.text = carbs;
    e.sugar.text = sugar;
    e.protein.text = protein;
    e.fat.text = fat;
    e.sodium.text = sodium;
    e
      ..basis = basis
      ..energy = energy
      ..kcalPinned = kcalPinned
      ..fillOnly = fillOnly;
  }
}

/// 음식 한 줄이 쓰는 입력 컨트롤러 한 벌. [_MealEditSheetState] 가 목록으로
/// 들고 다닌다.
class _FoodEditors {
  _FoodEditors({
    required this.name,
    required this.amount,
    required this.kcal,
    required this.carbs,
    required this.sugar,
    required this.protein,
    required this.fat,
    required this.sodium,
    required this.source,
    required this.valuesName,
  });

  /// 0 은 빈 칸으로 연다 — 새로 추가한 줄에 `0` 이 적혀 있으면 지우고 쓰는
  /// 일이 한 번 더 늘어난다. 섭취량은 **모르는 것**이라 더욱 그렇다(null).
  factory _FoodEditors.of(DietFood food) {
    final _FoodEditors editors = _FoodEditors(
      name: TextEditingController(text: food.name),
      amount: _gramField(food.amountG ?? 0),
      kcal: _intField(food.kcal),
      carbs: _gramField(food.carbsG),
      sugar: _gramField(food.sugarG),
      protein: _gramField(food.proteinG),
      fat: _gramField(food.fatG),
      sodium: _intField(food.sodiumMg),
      source: food.source,
      valuesName: food.name.trim(),
    );
    // 열량 반영의 기준은 **칸에 보이는 값**으로 세운다(#2106). 소수 한 자리로
    // 반올림해 적은 칸과 원본이 다르면, 손대지 않은 칸이 Δ 를 만들어 열량이
    // 저절로 1kcal 씩 흔들린다.
    editors
      ..energy = editors.readEnergy()
      ..fillOnly = editors.energy.onlyKcal;
    // 양을 아는 음식은 열자마자 기준이 선다. 모르는 음식은 회원이 처음 적어
    // 넣는 양이 기준이 된다 — 그때까지는 비례 환산할 근거가 없다.
    final double? amountG = food.amountG;
    if (amountG != null && amountG > 0) {
      editors.basis = _FoodBasis(
        amountG: amountG,
        kcal: food.kcal,
        carbsG: food.carbsG,
        sugarG: food.sugarG,
        proteinG: food.proteinG,
        fatG: food.fatG,
        sodiumMg: food.sodiumMg,
      );
    }
    return editors;
  }

  static String intText(int v) => v == 0 ? '' : '$v';

  static String gramText(double v) => v == 0 ? '' : _gramsFieldText(v);

  static TextEditingController _intField(int v) =>
      TextEditingController(text: intText(v));

  static TextEditingController _gramField(double v) =>
      TextEditingController(text: gramText(v));

  final TextEditingController name;

  /// 이름 칸을 **벗어났을 때** 공공 DB 를 찾기 위한 것(#1896). 타이핑 중간값
  /// (`짜`, `짜장`)으로 부르면 요청만 늘고 쓸모없는 제안이 깜빡인다 — 운동의
  /// 칼로리 미리보기가 같은 방식이다(#1312).
  final FocusNode nameFocus = FocusNode();

  /// 지금 이름으로 찾은 공공 DB 값. 없으면 제안할 것이 없다는 뜻이다.
  FoodNutritionSuggestion? suggestion;

  /// 마지막으로 조회를 건 이름. 같은 이름을 두 번 묻지 않고, 늦게 도착한
  /// 응답이 그 사이 바뀐 이름을 덮지 않게 막는 표식이기도 하다.
  String? lookedUpName;

  /// 먹은 양(g). 이 칸 하나가 아래 여섯 값을 함께 움직인다.
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController carbs;
  final TextEditingController sugar;
  final TextEditingController protein;
  final TextEditingController fat;
  final TextEditingController sodium;

  /// 지금 적힌 영양이 **어느 양에서 나온 값인가.** 섭취량을 모르는 음식은
  /// null 이고, 회원이 양을 적어 넣거나 영양 칸을 직접 고칠 때 다시 선다.
  _FoodBasis? basis;

  /// 지금 칸의 영양이 어디서 왔나(#2105). 저장할 때 그대로 싣는다.
  FoodSource source;

  /// 지금 칸의 영양이 **어느 이름의 값인가**(#2107). 이름을 이것과 다르게 고치고
  /// 칸을 벗어나야 "다른 음식이 됐다" 로 본다 — 칸만 드나든 것은 이름 변경이
  /// 아니다.
  String valuesName;

  /// 탄단지를 고칠 때 열량이 출발하는 자리(#2106).
  late _EnergyBasis energy;

  /// 회원이 이 음식의 열량을 직접 적었다 — 이번 편집 동안 열량을 탄단지에
  /// 따라 움직이지 않는다(#2106). 라벨 값을 옮겨 적는 중이면 칸을 어느 순서로
  /// 적든 라벨 열량이 남아야 한다. 저장한 기록은 이것을 기억하지 않는다.
  bool kcalPinned = false;

  /// 편집을 열 때 탄단지 없이 열량만 있던 음식이다([_EnergyBasis.onlyKcal]) —
  /// 이번 편집 동안 탄단지를 적어도 열량을 움직이지 않는다. 공공 DB 값으로
  /// 채우면 풀린다.
  late bool fillOnly;

  /// 영양 칸을 손으로 고친 횟수. 이름 조회가 도는 사이 회원이 값을 고쳤는지
  /// 가린다(#2107) — 그랬으면 응답이 그 값을 덮지 않는다.
  int edits = 0;

  /// 이름 칸 아래의 안내(#2107). 없으면 null.
  _NameNotice? notice;

  /// 지금 칸에 적힌 열량·탄·단·지 한 벌(#2106).
  _EnergyBasis readEnergy() => _EnergyBasis(
    kcal: int.tryParse(kcal.text.trim()) ?? 0,
    carbsG: double.tryParse(carbs.text.trim()) ?? 0,
    proteinG: double.tryParse(protein.text.trim()) ?? 0,
    fatG: double.tryParse(fat.text.trim()) ?? 0,
  );

  void dispose() {
    nameFocus.dispose();
    for (final TextEditingController c in <TextEditingController>[
      name,
      amount,
      kcal,
      carbs,
      sugar,
      protein,
      fat,
      sodium,
    ]) {
      c.dispose();
    }
  }
}
