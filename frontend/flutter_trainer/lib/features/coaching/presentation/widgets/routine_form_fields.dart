import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_effects.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_limits.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Category order mirrors the member app's exercise-add sheet.
///
/// 여기 담긴 것은 **계약값**이다(서버 `RoutineType` Literal). 화면 문구는
/// `routineTypeLabel(l, value)` 로 따로 가져온다 — 번역하면 서버가 422 를
/// 돌려준다. (#501)
const List<String> kRoutineCategoryLabels = kRoutineTypes;

/// Button-style category picker matching the member exercise-add sheet.
class RoutineCategoryChips extends StatelessWidget {
  const RoutineCategoryChips({
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'routine-category',
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final selected = kRoutineCategoryLabels.contains(value) ? value : '기타';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.routineFieldType,
          style: context.oncare
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final category in kRoutineCategoryLabels)
              AppChoiceChip(
                // key 는 계약값으로 — 로케일이 바뀌어도 위젯 identity 는 같아야
                // 하고, 기존 테스트도 이 키를 쓴다.
                key: ValueKey<String>('$keyPrefix-$category'),
                label: routineTypeLabel(l, category),
                selected: selected == category,
                onSelected: (_) => onChanged(category),
              ),
          ],
        ),
      ],
    );
  }
}

/// 운동 시간 한 칸 — 직접 입력하고 −/+ 로 한 칸씩 고친다. (#1276)
///
/// 예전에는 슬라이더였다. "대충 이쯤" 을 고르기엔 좋지만 트레이너가 아는
/// 값(45분)을 그대로 넣기에는 나쁘다 — 회원 앱의 운동 추가 시트와 같은 모양으로
/// 맞췄다.
class RoutineMinutesField extends StatelessWidget {
  const RoutineMinutesField({
    required this.minutes,
    required this.onChanged,
    this.label,
    this.keyPrefix,
    this.compact = false,
    this.min = 1,
    this.max = 600,
    this.helper,
    super.key,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  /// 받는 값의 범위(분). 개별 운동 시간은 기본값(1~600분)이고, AI 생성
  /// 조건의 총 시간은 서버 범위(10~180분)를 넘긴다(#2871). 범위 밖으로 친
  /// 값은 경계값으로 당기고, 경계에 닿으면 −/+ 가 잠긴다.
  final int min;
  final int max;

  /// 칸 아래 도움말. 범위가 좁은 칸에서 받는 범위를 알린다(#2871).
  final String? helper;

  /// Optional context-specific label. Individual exercises use the default
  /// `routineFieldMinutes`; generation constraints pass the total-time label.
  final String? label;

  final String? keyPrefix;

  /// 스테퍼 버튼 없이 키보드 입력 칸만 그린다. 근력의 세트·횟수·중량과 한
  /// 줄에 나란히 둘 때 쓴다 — 세 칸 모두 −/+ 를 달면 가로 폭이 모자란다.
  /// (#1489)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _NumberInput(
      label: label ?? l.routineFieldMinutes,
      value: minutes.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      suffix: l.routineUnitMinutes,
      keyPrefix: keyPrefix ?? 'routine-minutes',
      steppers: !compact,
      helper: helper,
      onChanged: (double v) => onChanged(v.round()),
    );
  }
}

/// 운동 시간 — 시·분·초 세 칸. 치거나, 칸을 누르면 그 칸 아래 목록에서
/// 고른다. (#2221)
///
/// [RoutineMinutesField] 는 분 한 칸이라 45초짜리 운동을 적을 수 없었고, 한
/// 시간이 넘으면 90분처럼 환산해야 했다. 회원 앱은 같은 값을 휠로 적지만
/// (`AppDurationWheel`), 웹에서 마우스로 휠을 굴리면 한 칸에 1씩 움직여 45초를
/// 맞추려면 45번을 굴려야 한다.
///
/// 값은 초 하나다. 상한은 서버·회원 앱과 같은 열 시간이다.
class RoutineDurationField extends StatelessWidget {
  const RoutineDurationField({
    required this.seconds,
    required this.onChanged,
    this.label,
    this.keyPrefix,
    super.key,
  });

  final int seconds;
  final ValueChanged<int> onChanged;

  /// 세 칸 위 이름. 비우면 `운동 시간` 이다.
  final String? label;

  /// 칸 키의 앞머리 — `<keyPrefix>-hours` · `-minutes` · `-seconds`.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDurationField(
      duration: Duration(seconds: seconds),
      onChanged: (Duration value) => onChanged(value.inSeconds),
      label: label ?? l.routineFieldMinutes,
      labels: AppDurationWheelLabels(
        hours: l.routineUnitHours,
        minutes: l.routineUnitMinutes,
        seconds: l.routineUnitSeconds,
      ),
      maxSeconds: kMaxExerciseSeconds,
      keyPrefix: keyPrefix ?? 'routine-duration',
    );
  }
}

/// 근력의 세트 수 한 칸.
class RoutineSetsField extends StatelessWidget {
  const RoutineSetsField({
    required this.sets,
    required this.onChanged,
    this.keyPrefix,
    this.compact = false,
    super.key,
  });

  final int sets;
  final ValueChanged<int> onChanged;
  final String? keyPrefix;

  /// [RoutineMinutesField.compact] 참고.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _NumberInput(
      label: l.routineFieldSets,
      value: sets.toDouble(),
      min: 1,
      max: kMaxExerciseSets.toDouble(),
      suffix: l.routineUnitSets,
      keyPrefix: keyPrefix ?? 'routine-sets',
      steppers: !compact,
      onChanged: (double v) => onChanged(v.round()),
    );
  }
}

/// 근력의 한 세트당 횟수 한 칸. (#1310)
///
/// 세트·중량만으로는 근력 한 줄이 재현되지 않는다 — "12세트 60kg" 은 한 번에
/// 몇 개를 들었는지가 빠져 있어, 다음 주에 같은 운동을 다시 짤 근거가 없다.
class RoutineRepsField extends StatelessWidget {
  const RoutineRepsField({
    required this.reps,
    required this.onChanged,
    this.keyPrefix,
    this.compact = false,
    super.key,
  });

  final int reps;
  final ValueChanged<int> onChanged;
  final String? keyPrefix;

  /// [RoutineMinutesField.compact] 참고.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _NumberInput(
      label: l.routineFieldReps,
      value: reps.toDouble(),
      min: 1,
      max: kMaxExerciseReps.toDouble(),
      suffix: l.routineUnitReps,
      keyPrefix: keyPrefix ?? 'routine-reps',
      steppers: !compact,
      onChanged: (double v) => onChanged(v.round()),
    );
  }
}

/// 버티는 운동의 **한 세트를 버티는 시간** 한 칸. (#1969)
///
/// [RoutineRepsField] 와 한 자리를 나눠 쓴다 — 플랭크·행잉처럼 버티는 운동은
/// 한 세트를 몇 회가 아니라 몇 초로 재므로, 칸을 하나 더 두지 않고 횟수 칸을
/// 이것으로 바꿔 보인다. 칸이 없던 동안 트레이너는 `플랭크 3세트 · 60초` 를
/// **이름에** 적을 수밖에 없었고, 이름에 적힌 글자는 어떤 집계에도 잡히지
/// 않았다.
class RoutineHoldSecondsField extends StatelessWidget {
  const RoutineHoldSecondsField({
    required this.holdSeconds,
    required this.onChanged,
    this.keyPrefix,
    this.compact = false,
    super.key,
  });

  final int holdSeconds;
  final ValueChanged<int> onChanged;
  final String? keyPrefix;

  /// [RoutineMinutesField.compact] 참고.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _NumberInput(
      label: l.routineFieldHold,
      value: holdSeconds.toDouble(),
      min: 1,
      max: kMaxExerciseHoldSeconds.toDouble(),
      suffix: l.routineUnitSeconds,
      keyPrefix: keyPrefix ?? 'routine-hold',
      steppers: !compact,
      onChanged: (double v) => onChanged(v.round()),
    );
  }
}

/// 한 세트를 **회로 잴지 초로 잴지** 고르는 칩 두 개. (#1969)
///
/// 이름 해석이 기본값을 정하지만([isIsometricExerciseName]), 고르는 것은
/// 트레이너다 — 종목표에 없는 이름도 있고 같은 운동을 다르게 시키기도 한다.
class RoutineMeasureToggle extends StatelessWidget {
  const RoutineMeasureToggle({
    required this.isHold,
    required this.onChanged,
    this.keyPrefix,
    super.key,
  });

  final bool isHold;
  final ValueChanged<bool> onChanged;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String prefix = keyPrefix ?? 'routine-measure';
    return Semantics(
      label: l.routineFieldMeasure,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppChoiceChip(
            key: Key('$prefix-reps'),
            label: l.routineUnitReps,
            selected: !isHold,
            onSelected: (bool _) => onChanged(false),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          AppChoiceChip(
            key: Key('$prefix-seconds'),
            label: l.routineUnitSeconds,
            selected: isHold,
            onSelected: (bool _) => onChanged(true),
          ),
        ],
      ),
    );
  }
}

/// 근력의 중량 한 칸. 소수점 한 자리까지 받는다 — 원판은 0.5kg 단위다.
class RoutineWeightField extends StatelessWidget {
  const RoutineWeightField({
    required this.weight,
    required this.onChanged,
    this.keyPrefix,
    this.compact = false,
    super.key,
  });

  final double weight;
  final ValueChanged<double> onChanged;
  final String? keyPrefix;

  /// [RoutineMinutesField.compact] 참고.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _NumberInput(
      label: l.routineFieldWeight,
      value: weight,
      min: 0,
      max: kMaxExerciseWeightKg,
      decimals: 1,
      suffix: l.routineUnitKg,
      keyPrefix: keyPrefix ?? 'routine-weight',
      steppers: !compact,
      onChanged: onChanged,
    );
  }
}

/// 운동 이름 한 칸 — 자유 입력. 유형은 집계 축이라 넷뿐이라, 무슨 운동인지는
/// 이 칸에만 남는다. (#1276)
class RoutineNameField extends StatelessWidget {
  const RoutineNameField({
    required this.controller,
    this.label,
    this.keyPrefix = 'routine-exercise-name',
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String keyPrefix;

  /// 유형별 예시 문구(#1483) — 없으면 일반 예시로 떨어진다.
  /// [routineTypeNameHint] 로 만든다.
  final String? hint;

  /// 글자가 바뀔 때마다. 이름이 버티는 운동인지에 따라 `횟수`/`버티는 시간`
  /// 칸이 갈리므로, 적는 동안 따라와야 한다(#1969).
  final ValueChanged<String>? onChanged;

  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTextField(
      key: ValueKey<String>(keyPrefix),
      controller: controller,
      label: label ?? l.routineFieldExerciseName,
      hint: hint ?? l.routineFieldExerciseNameHint,
      maxLength: 100,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// 회원에게 보일 효과 한 줄 — 자동 문구를 placeholder 로 미리 보인다. (#2570)
///
/// 트레이너가 운동마다 효과를 적게 하면 부담이 되므로, 비워 두면 [autoEffect]
/// (유형 × 회원 목표 문구표)가 그대로 간다. 칸에 회색으로 미리 보이니 무엇이
/// 갈지 알 수 있고, 바꾸고 싶으면 그 자리에서 바로 친다 — 연필을 한 번 더
/// 누르지 않는다. 유형을 바꾸면 placeholder 도 따라 바뀐다.
///
/// 값은 트레이너가 친 글자뿐이다([value]). 목록에서 줄이 빠지면 같은 자리의
/// 칸이 다른 운동의 값을 받으므로, 바깥 값이 바뀌면 칸 글자를 맞춘다.
class RoutineEffectField extends StatefulWidget {
  const RoutineEffectField({
    required this.value,
    required this.autoEffect,
    required this.onChanged,
    this.keyPrefix = 'routine-effect',
    super.key,
  });

  /// 트레이너가 적은 효과. 비어 있으면 [autoEffect] 가 간다.
  final String value;

  /// 비워 두면 갈 자동 문구 — placeholder 로 보인다. 기타 유형처럼 비어
  /// 있으면 예시 문구를 대신 보인다.
  final String autoEffect;

  final ValueChanged<String> onChanged;
  final String keyPrefix;

  @override
  State<RoutineEffectField> createState() => _RoutineEffectFieldState();
}

class _RoutineEffectFieldState extends State<RoutineEffectField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(RoutineEffectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTextField(
      key: ValueKey<String>(widget.keyPrefix),
      controller: _controller,
      label: l.routineFieldEffect,
      // 자동 문구는 보이는 글만 화면 언어로 옮긴다 — 저장 값은 그대로다(#2737).
      // 번역 표는 두 앱이 함께 쓰는 `oncare_ui` 한 벌이다(#2906).
      hint: widget.autoEffect.isNotEmpty
          ? routineEffectText(widget.autoEffect, languageCode: l.localeName)
          : l.routineFieldEffectHint,
      // 글자 수 표시 없이 막는다 — 회원 카드에서 한 줄로 읽히는 길이다.
      inputFormatters: <TextInputFormatter>[
        LengthLimitingTextInputFormatter(kRoutineEffectMaxLength),
      ],
      onChanged: widget.onChanged,
    );
  }
}

/// 날짜 한 칸 — 눌러서 달력을 연다. 기본값은 오늘이다. (#1276)
class RoutineDateField extends StatelessWidget {
  const RoutineDateField({
    required this.date,
    required this.onChanged,
    this.keyPrefix = 'routine-date',
    super.key,
  });

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.routineFieldDate,
          style: tokens
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppPickerField(
          key: ValueKey<String>(keyPrefix),
          icon: AppIcons.calendar,
          // 로케일이 정하는 날짜 문구 — 하드코딩하면 영어 화면에도 한국식
          // 표기가 남는다.
          value: MaterialLocalizations.of(context).formatFullDate(date),
          onTap: () async {
            final DateTime now = nowKst();
            final DateTime? picked = await showAppDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(now.year - 2),
              // 프로그램은 앞으로 할 운동도 잡는다 — 회원 기록과 달리 미래를
              // 막지 않는다.
              lastDate: DateTime(now.year + 2),
              // 오늘 테두리는 기기 시각이 아니라 서울의 오늘이다(#3250).
              currentDate: now,
            );
            if (picked != null) {
              onChanged(DateTime(picked.year, picked.month, picked.day));
            }
          },
        ),
      ],
    );
  }
}

/// 예상 소모 칼로리 — 읽기 전용. 운동 이름·유형·시간(또는 세트)·강도에서 나온다.
///
/// [estimate] 가 null 이면 **숫자를 띄우지 않는다.** 이름을 적기 전에는 확정된
/// 값이 없다는 것이 회원 앱과 같은 규약이다(#1312) — 폼을 여는 순간 기본값만으로
/// 값이 떠 있으면, 그 숫자가 무엇의 값인지도 이름 칸이 왜 필요한지도 읽히지
/// 않는다.
class RoutineCaloriesLine extends StatelessWidget {
  const RoutineCaloriesLine({required this.estimate, super.key});

  final RoutineCalorieEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final RoutineCalorieEstimate? value = estimate;
    return AppTile(
      key: const ValueKey<String>('routine-calories'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIcon(
                AppIcons.calories,
                size: OnCareSize.iconSmall,
                color: OnCareColors.cautionFill,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  l.routineFieldCalories,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              if (value == null)
                Text(
                  l.routineCaloriesNeedName,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(color: OnCareColors.textTertiary),
                )
              else
                Text(
                  l.routineKcalValue(value.calories),
                  style: OnCareTypography.numeric(
                    tokens.text(OnCareTypography.label),
                  ).copyWith(color: tokens.brand.primary),
                ),
            ],
          ),
          if (value != null && value.isRough) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              l.routineCaloriesRoughEstimate,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 숫자 한 칸 — 직접 입력하는 입력창과 (compact 가 아니면) 양옆의 −/+ 버튼.
///
/// 공용 `AppNumberStepper` 는 정수 값만 받고 직접 입력을 하지 못해, 중량의
/// 소수(62.5kg)와 "아는 값을 그대로 적기"(#1276)를 담지 못한다. 그래서 같은
/// 부품(tonal 아이콘 버튼 + 입력창)으로 이 파일 안에서 조립한다. 테스트가 짚는
/// 키 규칙(`<keyPrefix>-minus` / `-field` / `-plus`)은 옛 스테퍼와 같다.
class _NumberInput extends StatefulWidget {
  const _NumberInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.keyPrefix,
    required this.steppers,
    required this.onChanged,
    this.decimals = 0,
    this.helper,
  });

  /// 필드 위 라벨("세트 수"·"횟수"·"중량"·"운동 시간").
  final String label;

  /// 칸 아래 도움말(받는 범위 등). 없으면 그리지 않는다.
  final String? helper;
  final double value;
  final double min;
  final double max;

  /// 값 오른쪽에 붙는 단위("세트"·"회"·"kg"·"분").
  final String suffix;
  final String keyPrefix;

  /// −/+ 버튼을 둘지. compact 칸은 키보드 입력만 받는다.
  final bool steppers;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(_controller.text);
    });
  }

  @override
  void didUpdateWidget(_NumberInput old) {
    super.didUpdateWidget(old);
    // 밖에서 값이 바뀐 경우(유형 전환 등)만 필드를 다시 그린다 — 편집 중인
    // 문자열을 덮어쓰면 커서가 튄다.
    if (widget.value != old.value && !_focus.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  double _round(double v) => widget.decimals == 0
      ? v.roundToDouble()
      : double.parse(v.toStringAsFixed(widget.decimals));

  double _clamp(double v) => v.clamp(widget.min, widget.max);

  /// 적히는 대로 값을 올린다. **필드의 글자는 건드리지 않는다** — 타이핑 중에
  /// 고쳐 쓰면 "4" 를 지나 "47" 로 가는 길이 막히고 커서가 튄다.
  void _typed(String raw) {
    final double? parsed = double.tryParse(raw.trim());
    if (parsed != null) widget.onChanged(_round(_clamp(parsed)));
  }

  /// 비워 둔 칸이나 범위 밖 값을 되돌리고 글자를 다시 그린다.
  void _commit(String raw) {
    final double next = _round(
      _clamp(double.tryParse(raw.trim()) ?? widget.value),
    );
    _controller.text = _format(next);
    widget.onChanged(next);
  }

  void _bump(double delta) {
    _focus.unfocus();
    _commit(
      ((double.tryParse(_controller.text.trim()) ?? widget.value) + delta)
          .toString(),
    );
  }

  Key _key(String suffix) => ValueKey<String>('${widget.keyPrefix}-$suffix');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final Widget field = AppTextField(
      key: _key('field'),
      controller: _controller,
      focusNode: _focus,
      // compact 칸은 라벨을 필드에 붙여 둔다 — 세 칸이 나란히 서도 무엇의
      // 값인지 읽힌다. 스테퍼 칸은 버튼까지 덮도록 위에 따로 얹는다.
      label: widget.steppers ? null : widget.label,
      // −/+ 사이의 값은 칸 가운데에 선다(규격 전환 전 스테퍼와 같다).
      textAlign: widget.steppers ? TextAlign.center : TextAlign.start,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.decimals > 0,
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          widget.decimals > 0 ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      onChanged: _typed,
      onSubmitted: _commit,
      // compact 칸은 도움말을 칸에 붙인다 — 스테퍼 칸은 줄 아래에 따로 둔다.
      helper: widget.steppers ? null : widget.helper,
      suffix: Padding(
        padding: const EdgeInsetsDirectional.only(end: OnCareSpacing.s12),
        child: Center(
          widthFactor: 1,
          child: Text(
            widget.suffix,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
      ),
    );
    if (!widget.steppers) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.label,
          style: tokens
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Row(
          children: <Widget>[
            AppIconButton(
              key: _key('minus'),
              icon: AppIcons.remove,
              tooltip: l.routineFormDecrease,
              variant: AppIconButtonVariant.tonal,
              onPressed: widget.value > widget.min ? () => _bump(-1) : null,
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(child: field),
            const SizedBox(width: OnCareSpacing.s8),
            AppIconButton(
              key: _key('plus'),
              icon: AppIcons.add,
              tooltip: l.routineFormIncrease,
              variant: AppIconButtonVariant.tonal,
              onPressed: widget.value < widget.max ? () => _bump(1) : null,
            ),
          ],
        ),
        if (widget.helper case final String helper) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            helper,
            key: _key('helper'),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// Three-button intensity picker matching the member add sheet.
class RoutineIntensityChips extends StatelessWidget {
  const RoutineIntensityChips({
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'routine-intensity',
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String keyPrefix;

  /// (라벨 키, 계약값). 저장되는 것은 뒤쪽 값이다 — 라벨만 로케일을 따른다.
  static List<(String, String)> _choices(AppLocalizations l) =>
      <(String, String)>[
        (l.intensityLight, 'low'),
        (l.intensityModerate, 'moderate'),
        (l.intensityHigh, 'high'),
      ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<(String, String)> choices = _choices(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.routineFieldIntensity,
          style: context.oncare
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Row(
          children: <Widget>[
            for (var index = 0; index < choices.length; index++) ...<Widget>[
              Expanded(
                child: AppChoiceChip(
                  // key 는 계약값으로 — 로케일이 바뀌어도 identity 는 같다.
                  key: ValueKey<String>('$keyPrefix-${choices[index].$2}'),
                  label: choices[index].$1,
                  selected: value == choices[index].$2,
                  onSelected: (_) => onChanged(choices[index].$2),
                ),
              ),
              if (index < choices.length - 1)
                const SizedBox(width: OnCareSpacing.s8),
            ],
          ],
        ),
      ],
    );
  }
}
