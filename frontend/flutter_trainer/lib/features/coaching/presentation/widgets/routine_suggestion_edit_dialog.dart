import 'package:flutter/material.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 수정 후 추천으로 나가는 값. 취소는 null 이다.
///
/// 근력이면 [sets]·[reps]·[weight] 가 실리고 [minutes] 는 쓰이지 않는다. 그
/// 밖의 유형은 반대다 — 서버도 같은 규칙으로 받는다(#1321).
typedef RoutineSuggestionEdit = ({
  String name,
  int minutes,
  String type,
  int? sets,
  int? reps,
  int? holdSeconds,
  double? weight,
  String reason,
});

/// Opens the minimal editor for one AI personal-exercise suggestion (#790).
///
/// 개인운동 하나를 고치려고 정규 프로그램 편집기로 보내지 않는다 — 그쪽은 여러
/// 세션과 운동 구성을 다루는 화면이라, `8분 스트레칭을 10분으로` 같은 판단에
/// 필요한 것보다 훨씬 크다. 그래서 이 dialog 는 승인 판단에 필요한 필드만 둔다.
///
/// **강도 필드는 없다.** 배정 루틴에는 강도가 없고(회원 화면도 보여 주지 않는다),
/// 넣더라도 어디에도 닿지 않는 값이 된다. 강도 조절은 시간·운동 유형과 회원에게
/// 전달할 메모로 표현한다.
///
/// 다만 **근력은 시간으로 재지 않는다.** 유형이 근력이면 세트·횟수·중량을 묻고,
/// 그 밖이면 시간을 묻는다 — 앱의 다른 운동 입력 화면과 같은 스펙이고 같은
/// 위젯을 쓴다(#1276, #1310). 예전에는 여기만 시간을 물어, 근력 제안을 승인하면
/// 세트가 빈 배정이 회원에게 갔다(#1321).
Future<RoutineSuggestionEdit?> showRoutineSuggestionEditDialog(
  BuildContext context,
  RoutineSuggestion suggestion,
) {
  return showAppDialog<RoutineSuggestionEdit>(
    context: context,
    builder: (_) => RoutineSuggestionEditDialog(suggestion: suggestion),
  );
}

/// 개인운동 제안 하나의 **최종 검토** — 승인 직전 확인 (#1028).
///
/// `true` 로 닫히면 트레이너가 나갈 내용을 그대로 보고 확인한 것이다. 취소·
/// 바깥 탭은 null 이고, 그때는 아무 mutation 도 일어나지 않는다. 여기 그리는
/// 값(이름·양·유형·메모)이 곧 `approve` 가 보낼 값이라, 확인한 내용과
/// payload 가 어긋날 자리가 없다. 근력은 시간이 아니라 세트·횟수·중량으로
/// 적는다 — 수정 창이 물은 것과 같은 칸이어야 한다(#1321).
Future<bool?> showRoutineSuggestionConfirmDialog(
  BuildContext context, {
  required RoutineSuggestion suggestion,
  required String clientName,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final AppLocalizations l = AppLocalizations.of(dialogContext);
      final OnCareTokens tokens = dialogContext.oncare;
      return AppDialog(
        key: const ValueKey<String>('routine-suggestion-confirm'),
        title: l.suggestionConfirmTitle,
        showClose: false,
        footer: AppButtonPair(
          cancelKey: const ValueKey<String>('suggestion-confirm-cancel'),
          cancelLabel: l.actionCancel,
          onCancel: () => Navigator.of(dialogContext).pop(false),
          confirmKey: const ValueKey<String>('suggestion-confirm-submit'),
          confirmLabel: l.suggestionApprove,
          onConfirm: () => Navigator.of(dialogContext).pop(true),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l.suggestionConfirmBody(clientName),
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            Container(
              padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
              decoration: const BoxDecoration(
                color: OnCareColors.surfaceInput,
                borderRadius: OnCareRadius.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${suggestion.name} · '
                    '${routineSuggestionAmountLabel(l, suggestion)}',
                    style: tokens
                        .text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        )
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    routineTypeLabel(l, suggestion.type),
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                  if (suggestion.reason.isNotEmpty) ...<Widget>[
                    const SizedBox(height: OnCareSpacing.s8),
                    Text(
                      suggestion.reason,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 제안 한 줄이 말하는 **양**. 근력은 세트·횟수·중량, 나머지는 시간이다.
///
/// 검토 카드와 최종 검토 dialog 가 **같은 함수**를 쓴다 — 목록에서 읽은 값과
/// 승인 직전에 확인하는 값이 다르면 트레이너가 무엇을 보고 눌렀는지가 흐려진다.
/// 그래서 수정 창 옆에 둔다(그 셋이 같은 칸을 말해야 한다).
///
/// 맨몸 운동의 중량은 `0kg` 이다 — 중량 칸은 비울 수 없고(최솟값 0) 근력을
/// 고르면 언제나 값을 하나 든다. 값이 아예 없는 것은 규칙이 서기 전에 저장된
/// 행뿐이라, 그때만 자리를 비운다.
String routineSuggestionAmountLabel(
  AppLocalizations l,
  RoutineSuggestion suggestion,
) {
  if (suggestion.type != '근력') return l.minutesShort(suggestion.minutes);
  final List<String> parts = <String>[
    if (suggestion.sets != null) l.progSetsValue(suggestion.sets!),
    // 버티는 운동은 회가 아니라 초로 읽는다 — 둘은 배타다(#1969).
    if (suggestion.holdSeconds != null)
      l.progHoldValue(suggestion.holdSeconds!)
    else if (suggestion.reps != null)
      l.progRepsValue(suggestion.reps!),
    if (suggestion.weight != null)
      '${_trimZero(suggestion.weight!)}${l.routineUnitKg}',
  ];
  return parts.isEmpty ? l.minutesShort(suggestion.minutes) : parts.join(' · ');
}

/// 20.0 → `20`, 62.5 → `62.5`.
String _trimZero(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// The minimal edit form for a pending suggestion.
class RoutineSuggestionEditDialog extends StatefulWidget {
  /// Creates the dialog for [suggestion].
  const RoutineSuggestionEditDialog({super.key, required this.suggestion});

  /// The suggestion being edited. Values seed the form.
  final RoutineSuggestion suggestion;

  @override
  State<RoutineSuggestionEditDialog> createState() =>
      _RoutineSuggestionEditDialogState();
}

class _RoutineSuggestionEditDialogState
    extends State<RoutineSuggestionEditDialog> {
  /// 서버 스키마(`RoutineSuggestionApproveRequest`)와 같은 상한. 여기서 막으면
  /// 422 왕복 없이 그 자리에서 알 수 있다.
  static const int _nameMaxLength = 100;
  static const int _reasonMaxLength = 200;

  late final TextEditingController _name = TextEditingController(
    text: widget.suggestion.name,
  );
  late final TextEditingController _reason = TextEditingController(
    text: widget.suggestion.reason,
  );
  late String _type = widget.suggestion.type;
  late int _minutes = widget.suggestion.minutes;
  // 근력의 세 값. 시간과 따로 들고 있어야 유형을 오갈 때 각자의 값이 남는다 —
  // 하나로 쓰면 30분이 30세트가 되어 돌아온다. 제안이 값을 들고 있지 않으면
  // 다른 입력 화면과 같은 기본값으로 시작한다.
  late int _sets = widget.suggestion.sets ?? 3;
  late int _reps = widget.suggestion.reps ?? 10;
  late int _holdSeconds = widget.suggestion.holdSeconds ?? 60;
  // 제안이 든 칸이 곧 이 운동을 재는 단위다. 값이 없는 제안은 이름으로
  // 본다 — 종목표가 버티는 운동이라고 하면 초로 연다. (#1969)
  late bool _isHold =
      widget.suggestion.holdSeconds != null ||
      (widget.suggestion.reps == null &&
          isIsometricExerciseName(widget.suggestion.name));
  late double _weight = widget.suggestion.weight ?? 20;

  bool get _isStrength => _type == '근력';

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    // 이름을 지운 채 보내면 서버가 400 이다. 버튼을 막는 대신 그대로 두는 편이
    // 낫다 — 이름을 지운 것은 대개 다시 쓰려는 중이다.
    if (name.isEmpty) return;
    Navigator.of(context).pop((
      name: name,
      minutes: _minutes,
      type: _type,
      // 근력이 아니면 세 값을 싣지 않는다 — 유산소를 세트로 세는 화면은 없다.
      sets: _isStrength ? _sets : null,
      // 한 세트는 회로든 초로든 한 번만 잰다 — 고르지 않은 쪽은 비운다(#1969).
      reps: _isStrength && !_isHold ? _reps : null,
      holdSeconds: _isStrength && _isHold ? _holdSeconds : null,
      weight: _isStrength ? _weight : null,
      reason: _reason.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDialog(
      title: l.suggestionEditTitle,
      size: AppDialogSize.medium,
      showClose: false,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('suggestion-edit-cancel'),
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('suggestion-edit-submit'),
        confirmLabel: l.suggestionEditSubmit,
        onConfirm: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('suggestion-edit-name'),
            controller: _name,
            label: l.suggestionEditName,
            maxLength: _nameMaxLength,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 유형을 먼저 고른다 — 아래 칸이 세트·횟수·중량인지 시간인지를
          // 이 값이 정한다.
          RoutineCategoryChips(
            keyPrefix: 'suggestion-edit-type',
            value: _type,
            onChanged: (next) => setState(() => _type = next),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (_isStrength) ...<Widget>[
            RoutineSetsField(
              keyPrefix: 'suggestion-edit-sets',
              sets: _sets,
              onChanged: (next) => setState(() => _sets = next),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: RoutineMeasureToggle(
                keyPrefix: 'suggestion-edit-measure',
                isHold: _isHold,
                onChanged: (bool hold) => setState(() => _isHold = hold),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            // 버티는 운동은 `횟수` 자리를 `버티는 시간` 이 대신한다(#1969).
            if (_isHold)
              RoutineHoldSecondsField(
                keyPrefix: 'suggestion-edit-hold',
                holdSeconds: _holdSeconds,
                onChanged: (next) => setState(() => _holdSeconds = next),
              )
            else
              RoutineRepsField(
                keyPrefix: 'suggestion-edit-reps',
                reps: _reps,
                onChanged: (next) => setState(() => _reps = next),
              ),
            const SizedBox(height: OnCareSpacing.s8),
            RoutineWeightField(
              keyPrefix: 'suggestion-edit-weight',
              weight: _weight,
              onChanged: (next) => setState(() => _weight = next),
            ),
          ] else
            RoutineMinutesField(
              keyPrefix: 'suggestion-edit-minutes',
              minutes: _minutes,
              onChanged: (next) => setState(() => _minutes = next),
            ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('suggestion-edit-memo'),
            controller: _reason,
            label: l.suggestionEditMemo,
            hint: l.suggestionEditMemoHint,
            maxLength: _reasonMaxLength,
            maxLines: 3,
            minLines: 2,
          ),
        ],
      ),
    );
  }
}
