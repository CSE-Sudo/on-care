import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
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
    super.key,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

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
      min: 1,
      max: 600,
      suffix: l.routineUnitMinutes,
      keyPrefix: keyPrefix ?? 'routine-minutes',
      steppers: !compact,
      onChanged: (double v) => onChanged(v.round()),
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
      onSubmitted: onSubmitted,
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
        // 입력창과 같은 모양(채움·테두리·반경 12)의 누르는 칸.
        Material(
          color: OnCareColors.surfaceCard,
          shape: const RoundedRectangleBorder(
            borderRadius: OnCareRadius.mdAll,
            side: BorderSide(color: OnCareColors.lineStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey<String>(keyPrefix),
            onTap: () async {
              final DateTime now = nowKst();
              final DateTime? picked = await showAppDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(now.year - 2),
                // 프로그램은 앞으로 할 운동도 잡는다 — 회원 기록과 달리 미래를
                // 막지 않는다.
                lastDate: DateTime(now.year + 2),
              );
              if (picked != null) {
                onChanged(DateTime(picked.year, picked.month, picked.day));
              }
            },
            child: Container(
              constraints: BoxConstraints(
                minHeight: tokens.density.inputMedium,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s12,
                vertical: OnCareSpacing.s8,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.calendar_today_rounded,
                    size: OnCareSize.iconSmall,
                    color: tokens.brand.primary,
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    child: Text(
                      // 로케일이 정하는 날짜 문구 — 하드코딩하면 영어 화면에도
                      // 한국식 표기가 남는다.
                      MaterialLocalizations.of(context).formatFullDate(date),
                      style: tokens
                          .text(OnCareTypography.body)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: OnCareSize.iconMedium,
                    color: OnCareColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
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
              const Icon(
                Icons.local_fire_department_rounded,
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
  });

  /// 필드 위 라벨("세트 수"·"횟수"·"중량"·"운동 시간").
  final String label;
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
              icon: Icons.remove_rounded,
              tooltip: l.routineFormDecrease,
              variant: AppIconButtonVariant.tonal,
              onPressed: widget.value > widget.min ? () => _bump(-1) : null,
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(child: field),
            const SizedBox(width: OnCareSpacing.s8),
            AppIconButton(
              key: _key('plus'),
              icon: Icons.add_rounded,
              tooltip: l.routineFormIncrease,
              variant: AppIconButtonVariant.tonal,
              onPressed: widget.value < widget.max ? () => _bump(1) : null,
            ),
          ],
        ),
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
