import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 운동 기록 메모의 출처 태그 — `운동 기록 · 9/23`(그날 기록 전체, #2508), 예전
/// 메모의 `PT 세션 · 9/23`, `개인운동 · 9/23 코어 강화`, `회원 기록 · 9/23`. (#2332)
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
    TrainerMemoRefKind.day => l.clientMemoTagDay(date),
  };
}

/// `2026-09-23` → `9/23`. 읽을 수 없는 값은 그대로 둔다.
String _monthDay(String? day) {
  final DateTime? parsed = day == null ? null : DateTime.tryParse(day);
  if (parsed == null) return day ?? '';
  return '${parsed.month}/${parsed.day}';
}

/// 메모 분류 칩·태그 이름(#2622). 메모 창 칩과 목록 태그가 같은 말을 쓴다.
String memoCategoryLabel(AppLocalizations l, TrainerMemoCategory category) =>
    switch (category) {
      TrainerMemoCategory.exercise => l.clientMemoCategoryExercise,
      TrainerMemoCategory.diet => l.clientMemoCategoryDiet,
      TrainerMemoCategory.pain => l.clientMemoCategoryPain,
      TrainerMemoCategory.life => l.clientMemoCategoryLife,
      TrainerMemoCategory.none => l.clientMemoTagManual,
    };

/// 메모 창 `운동 기록 연결` 이 보여 주는 기간 — 오늘 포함 14일. (#2622)
///
/// AI 프로그램 추천이 직접 쓴 메모를 읽는 기간(`TRAINER_MEMO_LOOKBACK_DAYS`)과
/// 같다 — 그보다 오래된 기록에 지금 메모를 붙일 일은 드물다.
const int memoRecordLookbackDays = 14;

/// 메모 창 `운동 기록 연결` 드롭다운의 한 줄 — `9/30 (수) PT 세션`. (#2622)
String memoRecordOptionLabel(AppLocalizations l, TrainerMemoRef ref) {
  final DateTime? day = ref.day == null ? null : DateTime.tryParse(ref.day!);
  final String date = day == null
      ? (ref.day ?? '')
      : l.clientMemoRecordDay(
          '${day.month}',
          '${day.day}',
          weekdayNames(l)[day.weekday - 1],
        );
  return switch (ref.kind) {
    TrainerMemoRefKind.ptSession => l.clientMemoRecordPtSession(date),
    TrainerMemoRefKind.personal when ref.name.isNotEmpty =>
      l.clientMemoRecordPersonalNamed(date, ref.name),
    TrainerMemoRefKind.personal => l.clientMemoRecordPersonal(date),
    TrainerMemoRefKind.memberLog => l.clientMemoRecordMemberLog(date),
    TrainerMemoRefKind.day => l.clientMemoRecordExerciseDay(date),
  };
}

/// 운동 이력 한 건이 가리키는 기록 — 운동 탭 출처 줄(PT·개인운동)의 메모
/// 자리와 메모 창 `운동 기록 연결` 이 같은 규칙을 쓴다. 같은 기록이면 어느
/// 자리에서 남겨도 같은 메모가 된다.
TrainerMemoRef memoRefForHistory(RoutineHistoryEntry entry) {
  // 데모 이력은 코드 없이 고정 이름만 갖는다 — 이름으로도 종류를 찾는다.
  final String? code = routineKindCode(entry.label, kind: entry.kind);
  final DateTime? day = historyDayOf(entry);
  // 하루치 개인운동은 날짜로 가리킨다 — `오늘` 개인운동 상자에서 남긴 메모가
  // 지난 날 펼친 줄에서도 같은 자리에 보인다.
  if (code == 'personal_routine' && day != null) {
    return TrainerMemoRef(kind: TrainerMemoRefKind.personal, day: ymd(day));
  }
  return TrainerMemoRef(
    kind: code == 'pt_session'
        ? TrainerMemoRefKind.ptSession
        : TrainerMemoRefKind.personal,
    id: entry.id,
    day: day == null ? null : ymd(day),
    // 고정 이름(`AI 개인운동` 등)은 코드가 있어 화면이 번역한다.
    name: code == null ? entry.label : '',
  );
}

/// 최근 [memoRecordLookbackDays] 일 동안 메모를 이을 수 있는 기록, 최신 날
/// 먼저. (#2622, #2508)
///
/// 운동 탭이 출처(개인운동·회원 추가·PT)마다 메모 자리를 두므로 기록 연결도
/// 그 출처 하나를 고른다 — 한 날 안에서는 화면과 같은 순서(개인운동 → 회원
/// 추가 → PT)다. 여기서 이은 메모는 운동 탭 그 줄의 메모 개수에 들어간다.
final memoRecordOptionsProvider = FutureProvider.autoDispose
    .family<List<TrainerMemoRef>, String>((ref, clientId) async {
      final DateTime now = nowKst();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final DateTime from = DateTime(
        today.year,
        today.month,
        today.day - (memoRecordLookbackDays - 1),
      );
      bool inRange(DateTime day) {
        final DateTime d = DateTime(day.year, day.month, day.day);
        return !d.isBefore(from) && !d.isAfter(today);
      }

      final Map<String, List<RoutineHistoryEntry>> entriesByDay =
          <String, List<RoutineHistoryEntry>>{};
      final List<RoutineHistoryEntry> history = await ref.watch(
        clientHistoryProvider(clientId).future,
      );
      for (final RoutineHistoryEntry entry in history) {
        final DateTime? day = historyDayOf(entry);
        // id 를 잃은 옛 기록은 운동 탭에도 메모 자리가 없다.
        if (day == null || !inRange(day) || entry.id.isEmpty) continue;
        (entriesByDay[ymd(day)] ??= <RoutineHistoryEntry>[]).add(entry);
      }

      // 회원 추가 기록은 주 단위 운동 조회에 실려 온다(운동 탭과 같은 출처).
      // 이력이 이미 말하는 운동(PT 완료·개인운동 완료)은 뺀다 — 운동 탭
      // `회원 추가` 줄과 같은 규칙이다.
      final Set<String> memberLogDays = <String>{};
      final ClientRepository repo = ref.watch(clientRepositoryProvider);
      for (
        DateTime monday = weekStartOf(from);
        !monday.isAfter(today);
        monday = DateTime(monday.year, monday.month, monday.day + 7)
      ) {
        final ClientExerciseWeek week = await repo.fetchExerciseWeek(
          clientId,
          weekStart: monday,
        );
        for (final (int i, String label) in week.dayLabels.indexed) {
          final DateTime day = DateTime(
            monday.year,
            monday.month,
            monday.day + i,
          );
          if (!inRange(day)) continue;
          final List<RoutineHistoryEntry> entries =
              entriesByDay[ymd(day)] ?? const <RoutineHistoryEntry>[];
          final Set<String> inHistory = <String>{
            for (final RoutineHistoryEntry entry in entries)
              for (final ClientExerciseItem item in entry.exercises)
                item.name.trim(),
          };
          final List<ClientExerciseItem> items =
              week.itemsByDayLabel[label] ?? const <ClientExerciseItem>[];
          if (items.any(
            (ClientExerciseItem item) =>
                item.isMemberLog && !inHistory.contains(item.name.trim()),
          )) {
            memberLogDays.add(ymd(day));
          }
        }
      }

      bool isPt(RoutineHistoryEntry entry) =>
          routineKindCode(entry.label, kind: entry.kind) == 'pt_session';
      final List<String> days = <String>{
        ...entriesByDay.keys,
        ...memberLogDays,
      }.toList()..sort((a, b) => b.compareTo(a));
      return <TrainerMemoRef>[
        for (final String day in days) ...<TrainerMemoRef>[
          for (final RoutineHistoryEntry entry
              in entriesByDay[day] ?? const <RoutineHistoryEntry>[])
            if (!isPt(entry)) memoRefForHistory(entry),
          if (memberLogDays.contains(day))
            TrainerMemoRef(kind: TrainerMemoRefKind.memberLog, day: day),
          for (final RoutineHistoryEntry entry
              in entriesByDay[day] ?? const <RoutineHistoryEntry>[])
            if (isPt(entry)) memoRefForHistory(entry),
        ],
      ];
    });

/// 두 기록 연결이 같은 기록을 가리키는가 — 드롭다운 선택 비교에 쓴다.
bool sameMemoRecord(TrainerMemoRef a, TrainerMemoRef b) =>
    a.kind == b.kind && a.id == b.id && a.day == b.day;

/// [memo] 가 [ref] 가 가리키는 기록에서 남긴 메모인가.
///
/// 날짜([TrainerMemoRefKind.day])는 그날 운동 기록에 남긴 메모를 모두 센다 —
/// 예전에 PT 세션·개인운동·회원 기록 카드마다 남긴 메모도 그날 것이다.
bool _isFor(TrainerMemo memo, TrainerMemoRef ref) {
  final TrainerMemoRef? mine = memo.ref;
  if (memo.source != TrainerMemoSource.exerciseMemo || mine == null) {
    return false;
  }
  if (ref.kind == TrainerMemoRefKind.day) return mine.day == ref.day;
  if (ref.id != null) return mine.id == ref.id;
  // 날짜로 가리킨 상자(개인운동·회원 추가) — 같은 상자, 같은 날.
  return mine.id == null && mine.kind == ref.kind && mine.day == ref.day;
}

/// 운동 기록 메모 자리 — 아이콘과, 남긴 메모가 있으면 개수. (#2332)
///
/// 운동 탭은 출처(개인운동·회원 추가·PT)마다 알약 줄 오른쪽 끝에 하나다
/// (#2508) — `오늘` 상자와 이번 주·전체 펼친 날이 같다.
///
/// 헤더의 `메모` 버튼과 같은 아이콘이다. 여기서 남긴 메모는 그 창의 같은
/// 목록에 들어간다 — 두 자리가 다른 그림이면 다른 것을 쓰는 곳처럼 보인다.
///
/// 메모가 없을 때 아이콘만 두면 무엇을 하는 버튼인지 읽히지 않는다 — 그때는
/// `+ 메모 추가` 다.
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
    // 날짜로 가리킨 상자(개인운동·회원 추가)는 같은 날이라도 다른 자리다 —
    // 키에 종류를 넣어 한 화면에서 겹치지 않게 한다.
    final String key =
        memoRef.id ??
        (memoRef.kind == TrainerMemoRefKind.day
            ? 'day-${memoRef.day}'
            : '${memoRef.kind.wire}-${memoRef.day}');
    void open() =>
        showExerciseMemoDialog(context, clientId: clientId, memoRef: memoRef);
    if (count == 0) {
      return AppButton(
        key: ValueKey<String>('exercise-memo-open-$key'),
        onPressed: open,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
        leadingIcon: AppIcons.add,
        label: l.clientTrainerMemoAdd,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          key: ValueKey<String>('exercise-memo-count-$key'),
          '$count',
          style: OnCareTypography.numeric(
            tokens.text(OnCareTypography.caption),
          ).copyWith(color: tokens.brand.primary),
        ),
        AppIconButton(
          key: ValueKey<String>('exercise-memo-open-$key'),
          icon: AppIcons.note,
          tooltip: l.clientExerciseMemoCount(count),
          // 남긴 메모가 있는 기록은 개수와 아이콘을 같은 브랜드 색으로 —
          // 목록을 훑으며 어디에 적어 두었는지 찾을 수 있다.
          color: tokens.brand.primary,
          onPressed: open,
        ),
      ],
    );
  }
}

/// 운동 기록 하나의 메모 창을 연다. (#2332)
///
/// 이 기록에 남긴 메모가 있으면 그 메모들을 먼저 보여 주고 아래에서 더 쓴다.
/// 없으면 바로 새 메모를 쓴다.
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
  static const int _maxLength = 500;

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
    final OnCareTokens tokens = context.oncare;
    final List<TrainerMemo> memos =
        ref
            .watch(trainerMemosProvider(widget.clientId))
            .valueOrNull
            ?.where((TrainerMemo memo) => _isFor(memo, widget.memoRef))
            .toList() ??
        const <TrainerMemo>[];
    return AppDialog(
      key: const ValueKey<String>('exercise-memo-dialog'),
      title: memos.isEmpty
          ? l.clientExerciseMemoAdd
          : l.clientExerciseMemoCount(memos.length),
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
            // 회원 메모 창 목록의 운동 기록 메모 태그와 같은 파랑이다 — 같은
            // 태그가 두 자리에서 다른 색이면 다른 것으로 읽힌다.
            tone: AppTagTone.brand,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 이 기록에 남긴 메모 — 최신 먼저(목록이 그 순서로 온다). 고치거나
          // 지우는 일은 헤더 `메모` 창이 맡는다.
          for (final TrainerMemo memo in memos) ...<Widget>[
            AppTile(
              key: ValueKey<String>('exercise-memo-item-${memo.id}'),
              tone: AppTileTone.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    memo.body,
                    style: tokens
                        .text(OnCareTypography.body)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    _memoTime(memo.createdAt),
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.caption),
                    ).copyWith(color: OnCareColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          if (memos.isNotEmpty) const SizedBox(height: OnCareSpacing.s4),
          AppTextField(
            key: const ValueKey<String>('exercise-memo-input'),
            controller: _draft,
            maxLines: memos.isEmpty ? 4 : 2,
            maxLength: _maxLength,
            enabled: !_busy,
            // 남긴 메모를 보러 연 창에서는 입력칸이 먼저 잡지 않는다.
            autofocus: memos.isEmpty,
            hint: l.clientExerciseMemoHint,
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // 회원 메모 창과 같은 줄 — 왼쪽에 공개 범위(회원에게 가는 피드백과
          // 헷갈리지 않게, #2574), 오른쪽 끝에 글자 수.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  l.clientTrainerMemoPrivate,
                  style: context.oncare
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _draft,
                builder: (context, value, _) => Text(
                  key: const ValueKey<String>('exercise-memo-counter'),
                  '${value.text.characters.length}/$_maxLength',
                  style: OnCareTypography.numeric(
                    context.oncare.text(OnCareTypography.caption),
                  ).copyWith(color: OnCareColors.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 메모를 남긴 때 — 회원 메모 창 목록과 같은 `2026.09.23 14:05`.
String _memoTime(DateTime at) {
  // 회원 메모 창과 같은 KST 벽시계다(#2893) — 브라우저 시간대를 따르면 두
  // 창이 같은 메모를 다른 시각으로 보인다.
  final DateTime local = toKst(at);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}.${two(local.month)}.${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
