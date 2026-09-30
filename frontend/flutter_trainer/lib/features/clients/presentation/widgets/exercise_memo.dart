import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 운동 기록 메모의 출처 태그 — `PT 세션 · 9/23`, `개인 운동 · 9/23 코어 강화`,
/// `회원 기록 · 9/23`. (#2332)
///
/// 기록 카드의 작성 창과 회원 메모 창이 같은 말을 쓴다 — 두 자리에서 다르게
/// 부르면 같은 기록을 가리킨다는 것이 읽히지 않는다.
String exerciseMemoTagLabel(AppLocalizations l, TrainerMemoRef ref) {
  final String date = _monthDay(ref.day);
  return switch (ref.kind) {
    TrainerMemoRefKind.ptSession => l.clientMemoTagPtSession(date),
    TrainerMemoRefKind.personal when ref.name.isNotEmpty =>
      l.clientMemoTagPersonalNamed(date, ref.name),
    TrainerMemoRefKind.personal => l.clientMemoTagPersonal(date),
    TrainerMemoRefKind.memberLog => l.clientMemoTagMemberLog(date),
  };
}

/// `2026-09-23` → `9/23`. 읽을 수 없는 값은 그대로 둔다.
String _monthDay(String? day) {
  final DateTime? parsed = day == null ? null : DateTime.tryParse(day);
  if (parsed == null) return day ?? '';
  return '${parsed.month}/${parsed.day}';
}

/// [memo] 가 [ref] 가 가리키는 기록에서 남긴 메모인가.
bool _isFor(TrainerMemo memo, TrainerMemoRef ref) {
  final TrainerMemoRef? mine = memo.ref;
  if (memo.source != TrainerMemoSource.exerciseMemo || mine == null) {
    return false;
  }
  if (ref.id != null) return mine.id == ref.id;
  return mine.kind == TrainerMemoRefKind.memberLog && mine.day == ref.day;
}

/// 운동 기록 카드 오른쪽 위의 메모 자리 — 아이콘과, 남긴 메모가 있으면 개수. (#2332)
///
/// 헤더의 `메모` 버튼과 같은 아이콘이다. 여기서 남긴 메모는 그 창의 같은
/// 목록에 들어간다 — 두 자리가 다른 그림이면 다른 것을 쓰는 곳처럼 보인다.
class ExerciseMemoButton extends ConsumerWidget {
  const ExerciseMemoButton({
    super.key,
    required this.clientId,
    required this.memoRef,
  });

  final String clientId;

  /// 이 카드가 가리키는 기록.
  final TrainerMemoRef memoRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 메모 목록을 읽지 못해도 버튼은 쓸 수 있어야 한다 — 개수만 비운다.
    final int count =
        ref
            .watch(trainerMemosProvider(clientId))
            .valueOrNull
            ?.where((TrainerMemo memo) => _isFor(memo, memoRef))
            .length ??
        0;
    final String key = memoRef.id ?? 'day-${memoRef.day}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (count > 0)
          Text(
            key: ValueKey<String>('exercise-memo-count-$key'),
            '$count',
            style: OnCareTypography.numeric(
              tokens.text(OnCareTypography.caption),
            ).copyWith(color: OnCareColors.textSecondary),
          ),
        AppIconButton(
          key: ValueKey<String>('exercise-memo-open-$key'),
          icon: AppIcons.note,
          tooltip: count > 0
              ? l.clientExerciseMemoCount(count)
              : l.clientExerciseMemoAdd,
          // 남긴 메모가 있는 기록은 브랜드 색으로 — 목록을 훑으며 어디에
          // 적어 두었는지 찾을 수 있다.
          color: count > 0 ? tokens.brand.primary : OnCareColors.textSecondary,
          onPressed: () => showExerciseMemoDialog(
            context,
            clientId: clientId,
            memoRef: memoRef,
          ),
        ),
      ],
    );
  }
}

/// 운동 기록 하나에서 회원 메모를 남기는 작은 창을 연다. (#2332)
Future<void> showExerciseMemoDialog(
  BuildContext context, {
  required String clientId,
  required TrainerMemoRef memoRef,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => _ExerciseMemoDialog(clientId: clientId, memoRef: memoRef),
);

class _ExerciseMemoDialog extends ConsumerStatefulWidget {
  const _ExerciseMemoDialog({required this.clientId, required this.memoRef});

  final String clientId;
  final TrainerMemoRef memoRef;

  @override
  ConsumerState<_ExerciseMemoDialog> createState() =>
      _ExerciseMemoDialogState();
}

class _ExerciseMemoDialogState extends ConsumerState<_ExerciseMemoDialog> {
  /// 백엔드 `TrainerMemoCreateRequest.body` 상한과 같은 값.
  static const int _maxLength = 2000;

  final TextEditingController _draft = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String body = _draft.text.trim();
    if (body.isEmpty || _busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(trainerMemoRepositoryProvider)
          .create(
            widget.clientId,
            body: body,
            source: TrainerMemoSource.exerciseMemo,
            ref: widget.memoRef,
          );
      ref.invalidate(trainerMemosProvider(widget.clientId));
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppToast(context, l.clientExerciseMemoSaved);
    } on AppError catch (error) {
      if (!mounted) return;
      // 입력은 지우지 않는다 — 실패한 저장을 다시 누르는 데 다시 타이핑이
      // 필요하면 안 된다.
      setState(() => _busy = false);
      showAppToast(
        context,
        serverDetailOr(l, error.message, l.clientTrainerMemoSaveFailed),
        type: AppToastType.error,
      );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(
        context,
        l.clientTrainerMemoSaveFailed,
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDialog(
      title: l.clientExerciseMemoAdd,
      size: AppDialogSize.medium,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _busy ? null : () => Navigator.of(context).pop(),
        confirmLabel: l.actionSave,
        onConfirm: _busy ? null : _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 어느 기록에 남기는지 — 메모 창 목록에 붙을 태그와 같은 말이다.
          AppTag(
            key: const ValueKey<String>('exercise-memo-source'),
            label: exerciseMemoTagLabel(l, widget.memoRef),
            icon: AppIcons.exercise,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('exercise-memo-input'),
            controller: _draft,
            maxLines: 4,
            maxLength: _maxLength,
            enabled: !_busy,
            autofocus: true,
            hint: l.clientExerciseMemoHint,
            // 회원에게 가는 피드백과 헷갈리지 않게 적는 자리에서 밝힌다(#2574).
            helper: l.clientTrainerMemoPrivate,
          ),
        ],
      ),
    );
  }
}
