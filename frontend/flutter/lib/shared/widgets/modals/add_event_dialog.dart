import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/domain/repositories/schedule_repository.dart';
import 'package:oncare/features/schedule/domain/schedule_format.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/features/schedule/presentation/schedule_category_color.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_toast.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 드롭다운에 놓는 순서. 값은 서버로 나가는 계약(`ScheduleCategory`)이고, 사람이
/// 읽는 이름은 `scheduleCategoryLabel` 이 로케일에 맞춰 그린다(#847). 예전에는
/// 한국어 문구 자체를 선택 상태로 들고 있어 영어 로케일에서 목록이 한국어로
/// 남았다.
const List<ScheduleCategory> _categories = <ScheduleCategory>[
  ScheduleCategory.hospital,
  ScheduleCategory.exercise,
  ScheduleCategory.meal,
  ScheduleCategory.medication,
  ScheduleCategory.other,
];

/// 새 일정을 만든다. [initialDate] 를 주면 그 날짜로 열린다 — 캘린더에서 날짜를
/// 눌러 들어오는 흐름이 쓴다.
///
/// 저장에 성공하면 `true` 로 닫힌다. 부른 쪽이 목록을 다시 읽을지 판단한다.
///
/// 회원앱의 입력 폼은 바텀시트다(#1690 확정) — 이름은 호출부 호환을 위해 둔다.
Future<bool?> showAddEventDialog(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showAppSheet<bool>(
    // 캘린더·하루 시트 위에 겹쳐 뜨므로 같은 규칙으로 루트 Navigator 에 올린다.
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext ctx) => _EventDialog(initialDate: initialDate),
  );
}

/// 이미 있는 일정을 고친다. 저장에 성공하면 `true` 로 닫힌다.
Future<bool?> showEditEventDialog(BuildContext context, ScheduleEvent event) {
  return showAppSheet<bool>(
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext ctx) => _EventDialog(existing: event),
  );
}

/// 저장된 `HH:mm` 을 피커가 쓰는 값으로 되돌린다. 형식이 어긋난 옛 기록도 있을
/// 수 있으므로(#785 이전에 만들어진 것) 못 읽으면 '시간 없음' 으로 둔다.
TimeOfDay? parseWireTime(String value) {
  if (!isScheduleTime(value) || value.isEmpty) return null;
  return TimeOfDay(
    hour: int.parse(value.substring(0, 2)),
    minute: int.parse(value.substring(3, 5)),
  );
}

/// 서버 계약 형식(`YYYY-MM-DD`). 화면에는 로케일 형식으로 보여 주고, 나갈 때만
/// 이 형식으로 바꾼다 — 사용자가 형식을 맞출 일이 없어야 한다.
String wireDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 서버 계약 형식(`HH:mm`, 24시간). 시드 일정도 같은 형식이다.
String wireTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

/// 추가와 수정이 같은 화면을 쓴다. 두 흐름에서 고를 수 있는 값이 같아야 하고,
/// 형식을 지키는 방식도 한 벌이어야 한다 — 수정에서만 자유 입력이 되면 #785 로
/// 막은 구멍이 다시 열린다.
class _EventDialog extends ConsumerStatefulWidget {
  const _EventDialog({this.existing, this.initialDate});

  /// null 이면 새로 만드는 흐름이다.
  final ScheduleEvent? existing;

  /// 새로 만들 때의 기본 날짜. 지정하지 않으면 오늘.
  final DateTime? initialDate;

  @override
  ConsumerState<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends ConsumerState<_EventDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );

  /// 날짜는 늘 값이 있다. 피커로만 고르므로 형식이 어긋날 수 없다.
  late DateTime _date = _initialDate();

  /// 시간은 선택 항목이다 — 서버 계약에서도 빈 문자열을 허용한다.
  late TimeOfDay? _time = widget.existing == null
      ? null
      : parseWireTime(widget.existing!.time);

  late ScheduleCategory _category = _initialCategory();
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  DateTime _initialDate() {
    final ScheduleEvent? existing = widget.existing;
    if (existing != null && isScheduleDate(existing.date)) {
      return DateTime.parse(existing.date);
    }
    return widget.initialDate ?? nowKst();
  }

  ScheduleCategory _initialCategory() =>
      widget.existing?.category ?? _categories.first;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = nowKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      // 지난 일정도 기록할 수 있어야 하고, 앞으로도 넉넉히 잡을 수 있어야 한다.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// 일정은 시각 **하나**만 갖는다(서버 계약 `time`). 시작·종료를 고르는
  /// 기간 피커가 아니라 한 시각 피커를 쓴다 — 저장되는 값의 뜻이 그대로다.
  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showAppTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final AppToastHost toast = AppToastHost.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final title = _title.text.trim();
    // 날짜는 피커가 늘 채우므로 제목만 확인하면 된다.
    if (title.isEmpty) {
      toast.show(l.eventTitleRequired, kind: AppToastKind.error);
      return;
    }
    setState(() => _saving = true);
    final ScheduleRepository repo = ref.read(scheduleRepositoryProvider);
    final ScheduleCategory category = _category;
    final String date = wireDate(_date);
    final String time = _time == null ? '' : wireTime(_time!);
    try {
      if (_isEdit) {
        // 네 항목을 모두 보낸다 — 화면이 값을 다 들고 있으므로 부분 전송으로
        // 아낄 것이 없고, 무엇이 바뀌었는지 추적할 필요도 없어진다.
        await repo.updateEvent(
          widget.existing!.id,
          date: date,
          time: time,
          title: title,
          category: category,
        );
      } else {
        await repo.createEvent(
          date: date,
          time: time,
          title: title,
          category: category,
        );
      }
      // 오늘 일정이면 대시보드 "오늘의 일정"에 반영된다.
      ref.invalidate(dashboardSummaryProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      toast.show(
        _isEdit ? l.eventEditFailed : l.eventAddFailed,
        kind: AppToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MaterialLocalizations m = MaterialLocalizations.of(context);
    return AppSheet(
      title: _isEdit ? l.eventEditTitle : l.eventAddTitle,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        confirmLabel: _saving
            ? (_isEdit ? l.eventSaving : l.eventAdding)
            : (_isEdit ? l.eventSave : l.eventAdd),
        onConfirm: _saving ? null : _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            controller: _title,
            label: l.eventTitleLabel,
            hint: l.eventTitleHint,
            enabled: !_saving,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          // 날짜·시간은 직접 칠 수 없다. 예전에는 자유 입력이라 `2026/05/14`
          // 처럼 계약을 벗어난 값이 저장되고, 조회는 `YYYY-MM-DD` 를 전제해
          // 걸러 내서 넣은 일정이 어디에도 보이지 않았다(#785).
          _TapField(
            key: const Key('addEventDate'),
            label: l.eventDateLabel,
            value: m.formatMediumDate(_date),
            icon: Icons.calendar_today_rounded,
            onTap: _saving ? null : _pickDate,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          _TapField(
            key: const Key('addEventTime'),
            label: l.eventTimeLabel,
            // 시간은 선택이라 비워 둘 수 있다. 비었다는 것을 값 자리에서
            // 그대로 말해 준다.
            value: _time == null ? l.eventTimeNone : m.formatTimeOfDay(_time!),
            muted: _time == null,
            icon: Icons.schedule_rounded,
            onTap: _saving ? null : _pickTime,
            onClear: _time == null || _saving
                ? null
                : () => setState(() => _time = null),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppSelectField<ScheduleCategory>(
            value: _category,
            onChanged: _saving
                ? null
                : (ScheduleCategory? value) {
                    if (value != null) setState(() => _category = value);
                  },
            items: <DropdownMenuItem<ScheduleCategory>>[
              for (final ScheduleCategory c in _categories)
                DropdownMenuItem<ScheduleCategory>(
                  value: c,
                  child: Text(scheduleCategoryLabel(l, c)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 눌러서 고르는 값 한 칸. [AppTextField] 와 같은 모양(위 라벨 + 테마의 입력
/// 채움·테두리·반경)을 쓰되 글자를 직접 칠 수는 없다 — 형식이 어긋난 값이 애초에
/// 만들어지지 않게 하는 것이 목적이다. 모양 숫자는 모두 테마·토큰이 정한다.
class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
    this.muted = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  /// null 이면 저장 중이라 잠긴 상태다.
  final VoidCallback? onTap;

  /// 지울 수 있는 값(시간)일 때만 준다.
  final VoidCallback? onClear;

  /// 값이 비어 있음을 알리는 자리표시일 때 흐리게 그린다.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: tokens
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        InkWell(
          onTap: onTap,
          borderRadius: OnCareRadius.mdAll,
          child: InputDecorator(
            decoration: InputDecoration(
              enabled: onTap != null,
              constraints: BoxConstraints(
                minHeight: tokens.density.inputMedium,
              ),
              contentPadding: const EdgeInsets.only(left: OnCareSpacing.s12),
              prefixIcon: Icon(
                icon,
                size: OnCareSize.iconMedium,
                color: OnCareColors.textTertiary,
              ),
              suffixIcon: onClear == null
                  ? null
                  : AppIconButton(
                      icon: Icons.close_rounded,
                      tooltip: l.eventClearField(label),
                      color: OnCareColors.textTertiary,
                      onPressed: onClear,
                    ),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.body)
                  .copyWith(
                    color: muted
                        ? OnCareColors.textTertiary
                        : OnCareColors.textPrimary,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}
