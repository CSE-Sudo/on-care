import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/features/consultations/presentation/pages/consultations_page.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/data/demo_task_history.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 상담 요청 확인 미션이 쓰는 대기 목록 — **한 번만** 읽는다.
///
/// `consultationsProvider`(인박스 화면 전용)는 [ConsultationRepository.watch]
/// 를 그대로 구독하는데, 실서버 구현은 배지처럼 몇 초마다 다시 읽는 폴링
/// 스트림이다. 대시보드 카드에 그 스트림을 그대로 물리면 대시보드를 떠나도
/// 폴링이 계속 돌아 — 스케줄 30일 조회에서 겪은 것과 같은 이유로(
/// dashboard_controller.dart 참고) — 실서버 모드 위젯 테스트에서 타이머가
/// 안 지워지는 문제가 다시 생겼다. `fetch()` 는 원래 일회성 Future라 그대로
/// 쓴다.
final _consultationMissionsProvider =
    FutureProvider.autoDispose<List<ConsultationRequest>>((ref) {
      if (!ref.watch(consultationInboxEnabledProvider)) {
        return Future.value(const <ConsultationRequest>[]);
      }
      return ref.watch(consultationRepositoryProvider).fetch();
    }, name: 'consultationMissions');

/// One concrete 오늘 할 일 item — 상담 요청 하나, 건강 신호가 있는 고객
/// 하나, 프로그램 미등록 고객 하나, 리포트 대상 고객 하나 등.
///
/// [keyword] 가 곧 카테고리다 — 같은 keyword 를 가진 항목끼리 한
/// [_CategorySection] 으로 묶인다.
class _Mission {
  const _Mission({
    required this.key,
    required this.keyword,
    required this.keywordColor,
    required this.title,
    this.client,
    required this.subtitle,
    required this.onTap,
  });

  /// Stable across a day — used for checked/dismissed/carry-over tracking.
  final String key;

  /// 카테고리 이름이자 알약에 적을 짧은 낱말(상담/식단/운동/프로그램/리포트).
  final String keyword;
  final Color keywordColor;

  /// 고객을 못 찾을 때(상담 요청 등록 회원) 쓸 표시 이름.
  final String title;

  /// 로스터에 있는 고객이면 이름 옆에 성별·나이를 회색으로 붙인다.
  final TrainerClient? client;

  final String subtitle;
  final VoidCallback onTap;
}

/// 오늘 할 일 — 상담 요청·건강 신호·프로그램 미등록·리포트 대상 고객을
/// 카테고리별로 묶어 보여준다. 어제 저장분에 남아 있던 항목은 자기
/// 카테고리가 아니라 "지난 할 일"이라는 별도 상자로 모인다.
///
/// 체크(완료 처리, 회색+취소선)와 삭제(오늘 목록에서만 제외)는 서로 다른
/// 동작이다. 실제 상담 수락/거절, 프로그램 전송, 리포트 발송은 각 화면(상담·AI
/// 코칭·리포트)에서 해야 한다 — 여기 체크는 "확인했다"는 트레이너 자신의
/// 표시일 뿐이다.
///
/// 그 표시도 **계정 단위**로 저장한다([dailyTaskHistoryProvider], #1633).
/// 트레이너는 센터 PC 와 태블릿을 오가는데(알림 수신 설정과 같은 이유), 기기
/// 로컬에 두면 한쪽에서 끝낸 일이 다른 쪽에서 다시 할 일로 남고 `지난 할 일`
/// 상자도 기기마다 갈린다. 데모 모드만 계정이 없어 기기에 둔다.
class TodayTasksCard extends ConsumerStatefulWidget {
  /// Creates the card. [entries] is the health-alert roster (같은 정의를
  /// 주의 고객 KPI 가 쓴다).
  const TodayTasksCard({super.key, required this.entries});

  final List<AttentionClient> entries;

  @override
  ConsumerState<TodayTasksCard> createState() => _TodayTasksCardState();
}

class _TodayTasksCardState extends ConsumerState<TodayTasksCard> {
  Set<String> _checkedKeys = <String>{};
  Set<String> _dismissedKeys = <String>{};
  Set<String> _carriedOverKeys = <String>{};
  String? _initializedForDate;

  void _initializeIfNewDay(Set<String> missionKeys, DailyTaskHistory history) {
    final today = ymd(nowKst());
    if (_initializedForDate == today) return;
    _initializedForDate = today;
    final snapshot = history.read(today);
    final DateTime yesterdayDay = nowKst().subtract(const Duration(days: 1));
    final yesterdayDate = ymd(yesterdayDay);
    // 어제 기록이 없으면 데모 이력을 본다 — 그 안의 미완료 키는 데모 전용이라
    // 오늘의 실제 항목을 이월로 끌어가지 않는다(#1203).
    final yesterday =
        history.read(yesterdayDate) ??
        ref.read(demoTaskHistoryProvider).snapshotFor(yesterdayDay);
    _dismissedKeys = snapshot == null
        ? <String>{}
        : Set<String>.of(snapshot.dismissedKeys);
    // 체크한 키를 저장해 둔 날은 그 키만 되살린다(#1716). 옛 기록만 있는 날은
    // pending 에서 추정한다 — 그때는 마지막 저장 뒤에 생긴 미션도 체크로 보인다.
    final Set<String>? completed = snapshot?.completedKeys;
    _checkedKeys = snapshot == null
        ? <String>{}
        : completed != null
        ? completed.intersection(missionKeys).difference(_dismissedKeys)
        : missionKeys
              .where(
                (k) =>
                    !snapshot.pendingKeys.contains(k) &&
                    !_dismissedKeys.contains(k),
              )
              .toSet();
    _carriedOverKeys = yesterday == null
        ? <String>{}
        : yesterday.pendingKeys.intersection(missionKeys);
  }

  /// 저장된 상태를 아직 못 읽었으면 체크·삭제를 받지 않는다 — 빈 상태에서
  /// 저장하면 다른 기기에서 해 둔 체크를 덮어쓴다. 읽기에 실패했으면 알리고
  /// 다시 읽는다.
  bool _ensureReady() {
    if (_initializedForDate != null) return true;
    if (ref.read(dailyTaskHistoryProvider).hasError) {
      showAppToast(
        context,
        AppLocalizations.of(context).dashTaskLoadFailed,
        type: AppToastType.error,
      );
      ref.invalidate(dailyTaskHistoryProvider);
    }
    return false;
  }

  Future<void> _toggle(_Mission mission, Set<String> allKeys) async {
    if (!_ensureReady()) return;
    // 체크 해제 = 완료 취소다. 되돌리면 할 일 진행률 그래프에서도 그 완료가
    // 빠지는데, 그 사실이 체크박스 하나 누르는 것만으로는 안 보인다 —
    // 회원 앱 운동탭의 "완료 취소" 확인창과 같은 안내를 준다. 체크(완료)는
    // 되돌릴 게 없어 바로 처리한다.
    if (_checkedKeys.contains(mission.key)) {
      final l = AppLocalizations.of(context);
      final name = mission.client?.name ?? mission.title;
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: l.dashTaskUncheckTitle(name),
        message: l.dashTaskUncheckBody,
        cancelLabel: l.actionCancel,
        confirmLabel: l.dashTaskUncheckConfirm,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() {
      if (!_checkedKeys.remove(mission.key)) _checkedKeys.add(mission.key);
    });
    unawaited(_persist(allKeys));
  }

  Future<void> _dismiss(String key, Set<String> allKeys) async {
    if (!_ensureReady()) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l.dashTaskDismissTitle,
      message: l.dashTaskDismissBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _dismissedKeys.add(key);
      _checkedKeys.remove(key);
    });
    unawaited(_persist(allKeys.difference(<String>{key})));
  }

  Future<void> _persist(Set<String> allKeys) async {
    final checked = _checkedKeys.intersection(allKeys);
    final carriedCompleted = checked.intersection(_carriedOverKeys).length;
    try {
      await ref
          .read(dailyTaskHistoryProvider.notifier)
          .save(
            ymd(nowKst()),
            DailyTaskSnapshot(
              total: allKeys.length,
              completedToday: checked.length - carriedCompleted,
              completedCarriedOver: carriedCompleted,
              pendingKeys: allKeys.difference(checked),
              dismissedKeys: Set<String>.of(_dismissedKeys),
              completedKeys: checked,
            ),
          );
    } on AppError {
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context).dashTaskSaveFailed,
        type: AppToastType.error,
      );
    }
  }

  List<_Mission> _buildMissions(AppLocalizations l) {
    final clients =
        ref.watch(clientsProvider).valueOrNull ?? const <TrainerClient>[];
    final consultations =
        ref.watch(_consultationMissionsProvider).valueOrNull ??
        const <ConsultationRequest>[];

    // 주의 신호(답장 대기 제외)가 있는 회원만 — 답장은 `상담`·메시지가 맡는다.
    // 할 일은 그 회원의 **가장 급한 주의 신호** 하나다(#2244).
    final health = <(TrainerClient, ClientSignal)>[
      for (final entry in widget.entries)
        for (final signal in entry.signals.take(1))
          if (signal.kind.isAttention) (entry.client, signal),
    ];
    final missingProgram = clients.where(
      (c) =>
          c.active &&
          (c.lastRoutine.trim().isEmpty || c.lastRoutine.trim() == '-'),
    );
    final activeClients = clients.where((c) => c.active);
    // 데모·새 계정의 이월 항목(#1203). 실제 이력이 시작되면 사라진다. 이력을
    // 읽기 전에는 실제 기록이 있는지 모르므로 띄우지 않는다.
    final demoCarriedOver = ref.watch(dailyTaskHistoryProvider).hasValue
        ? ref
              .watch(demoTaskHistoryProvider)
              .snapshotFor(nowKst().subtract(const Duration(days: 1)))
        : null;
    final TrainerClient? demoCarryOverClient = activeClients.isEmpty
        ? null
        : activeClients.first;

    return <_Mission>[
      for (final request in consultations.where((r) => r.isPending))
        _Mission(
          key: 'consultation-${request.id}',
          keyword: l.dashTodoConsultation,
          keywordColor: context.oncare.brand.primary,
          title: request.memberName,
          subtitle: l.dashTodoConsultationSubtitle(
            request.preferredDate.month,
            request.preferredDate.day,
          ),
          onTap: () => showConsultationsDialog(context),
        ),
      for (final (client, signal) in health)
        _Mission(
          key: 'feedback-${signal.kind.wire}-${client.id}',
          keyword: signal.kind.isDiet ? l.dashTodoDiet : l.dashTodoWorkout,
          keywordColor: OnCareColors.danger,
          title: client.name,
          client: client,
          // 목록 배지보다 자세히 — 무엇을 얼마나 손볼지 정하는 자리라 근거
          // 수치를 붙인다(`칼로리 22% 과다`, `단백질 목표의 64%`).
          subtitle: signal.detailLabel(l),
          onTap: () => context.go(
            AppRoutes.clientDetail(
              client.id,
              section: signal.kind.detailSection,
            ),
          ),
        ),
      for (final client in missingProgram)
        _Mission(
          key: 'program-${client.id}',
          keyword: l.dashTodoProgram,
          keywordColor: context.oncare.brand.primary,
          title: client.name,
          client: client,
          subtitle: l.dashTodoProgramSubtitle,
          onTap: () => context.go(AppRoutes.coachingFor(client.id)),
        ),
      // 데모 이월 항목은 실제 미션 뒤에 붙인다 — 카드가 이 목록의 순서대로
      // 카테고리를 채우므로, 앞에 두면 실제 할 일이 한 칸씩 밀린다.
      if (demoCarriedOver != null && demoCarryOverClient != null)
        _Mission(
          key: DemoTaskHistory.kDemoCarryOverKey,
          keyword: l.dashTodoDiet,
          keywordColor: OnCareColors.danger,
          title: demoCarryOverClient.name,
          client: demoCarryOverClient,
          subtitle: l.dashTodoCarriedOverDemoSubtitle,
          onTap: () => context.go(
            AppRoutes.clientDetail(
              demoCarryOverClient.id,
              section: ClientSignalKind.calorieOff.detailSection,
            ),
          ),
        ),
      for (final client in activeClients)
        _Mission(
          key: 'report-${client.id}',
          keyword: l.dashTodoReport,
          keywordColor: context.oncare.brand.primary,
          title: client.name,
          client: client,
          subtitle: l.dashTodoReportSubtitle,
          onTap: () => context.go(AppRoutes.reportFor(client.id)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final missions = _buildMissions(l);
    final missionKeys = <String>{for (final m in missions) m.key};
    final history = ref.watch(dailyTaskHistoryProvider).valueOrNull;
    if (history != null) _initializeIfNewDay(missionKeys, history);
    final allKeys = missionKeys.difference(_dismissedKeys);
    final visible = missions.where((m) => allKeys.contains(m.key)).toList();

    final remaining = allKeys.difference(_checkedKeys).length;
    final allDone = allKeys.isNotEmpty && remaining == 0;

    // 항목이 하나도 없어도 다섯 카테고리는 항상 그 자리에 있다 — 매일 다시
    // 확인할 자리가 매번 다른 곳에서 나타났다 사라지면 습관이 안 붙는다.
    // "지난 할 일" 은 고정 카테고리가 아니라 넘어온 일이 있을 때만 뜬다(#2228).
    final categoryOrder = <MapEntry<String, Color>>[
      MapEntry(l.dashTodoConsultation, context.oncare.brand.primary),
      MapEntry(l.dashTodoWorkout, OnCareColors.danger),
      MapEntry(l.dashTodoDiet, OnCareColors.danger),
      MapEntry(l.dashTodoProgram, context.oncare.brand.primary),
      MapEntry(l.dashTodoReport, context.oncare.brand.primary),
    ];
    final carriedOver = <_Mission>[];
    final byCategory = <String, List<_Mission>>{
      for (final entry in categoryOrder) entry.key: <_Mission>[],
    };
    for (final mission in visible) {
      if (_carriedOverKeys.contains(mission.key)) {
        carriedOver.add(mission);
        continue;
      }
      byCategory[mission.keyword]?.add(mission);
    }

    // 상자마다 제목으로 키를 단다 — "지난 할 일" 이 빠졌다 들어오면 자리
    // 순서로 짝지어진 펼침 상태가 옆 카테고리로 한 칸씩 밀린다.
    final sections = <Widget>[
      if (carriedOver.isNotEmpty)
        _CategorySection(
          key: ValueKey<String>(l.dashTaskCarriedOverTitle),
          title: l.dashTaskCarriedOverTitle,
          // 할 일 진행률 차트의 "지난 할 일" 막대와 같은 색이다(#2214).
          color: OnCareColors.chartGoalLine,
          tinted: true,
          missions: carriedOver,
          checkedKeys: _checkedKeys,
          onToggle: (m) => unawaited(_toggle(m, allKeys)),
          onDismiss: (key) => _dismiss(key, allKeys),
        ),
      for (final category in categoryOrder)
        _CategorySection(
          key: ValueKey<String>(category.key),
          title: category.key,
          color: category.value,
          missions: byCategory[category.key]!,
          checkedKeys: _checkedKeys,
          onToggle: (m) => unawaited(_toggle(m, allKeys)),
          onDismiss: (key) => _dismiss(key, allKeys),
        ),
    ];

    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: AppSectionHeader(title: l.dashTodayTasks)),
              Text(
                allKeys.isEmpty || allDone
                    ? l.dashTasksReviewed
                    : l.dashTasksNeedReview(remaining),
                style: tokens
                    .text(OnCareTypography.label)
                    .copyWith(
                      color: allKeys.isEmpty || allDone
                          ? OnCareColors.success
                          : tokens.brand.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 카테고리 다섯은 항목이 없어도 항상 그 자리에 있다 — "오늘 할 일이
          // 하나도 없다"는 빈 화면이 아니라 카테고리마다 "없음"으로 읽힌다. 화면
          // 안에 들어오면 그대로, 넘치면 카드 자체가 커지는 대신 이 안에서만
          // 스크롤된다 — 옆 칸(오늘의 일정 + 활동 피드백)과 상관없이 미션이
          // 몇십 건이어도 대시보드 전체가 한없이 길어지지 않는다.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(child: Column(children: sections)),
          ),
        ],
      ),
    );
  }
}

/// One 카테고리 상자 — 헤더(이름·남은 건수)를 누르면 그 카테고리의 미션
/// 목록이 펼쳐지는 아코디언. 기본은 접힌 상태다.
class _CategorySection extends StatefulWidget {
  const _CategorySection({
    super.key,
    required this.title,
    required this.color,
    required this.missions,
    required this.checkedKeys,
    required this.onToggle,
    required this.onDismiss,
    this.tinted = false,
  });

  final String title;
  final Color color;
  final List<_Mission> missions;
  final Set<String> checkedKeys;
  final ValueChanged<_Mission> onToggle;
  final ValueChanged<String> onDismiss;

  /// "지난 할 일" 상자만 다른 색으로 — 나머지 카테고리와 한눈에 갈린다.
  final bool tinted;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _expanded = false;

  static TextStyle _countStyle(OnCareTokens tokens) =>
      tokens.text(OnCareTypography.strong(OnCareTypography.caption));

  /// 헤더 오른쪽 "남은 건수·완료 + 화살표" 묶음.
  Widget _status(String label, Color color, IconData icon) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: _countStyle(tokens).copyWith(color: color)),
        Icon(
          icon,
          size: OnCareSize.iconMedium,
          color: OnCareColors.textDisabled,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final remaining = widget.missions
        .where((m) => !widget.checkedKeys.contains(m.key))
        .length;
    // 그날 할 일이 처음부터 없는 칸은 "완료"가 아니라 "없음"이다 — 둘 다
    // 초록 "완료"면 끝낸 일과 없던 일이 구분되지 않는다. 펼칠 것도 없다(#2228).
    final empty = widget.missions.isEmpty;

    final OnCareTokens tokens = context.oncare;
    return Container(
      margin: const EdgeInsets.only(bottom: OnCareSpacing.s8),
      decoration: BoxDecoration(
        color: widget.tinted
            ? OnCareColors.onWhite(widget.color, OnCareAlpha.subtle)
            : OnCareColors.surfacePage,
        // 테두리는 모든 상자가 같은 옅은 선이다 — "지난 할 일" 만 색 농도로 칠한
        // 테두리는 다른 상자보다 진해 튀었다(#2214). 구분은 점 색과 바탕으로 한다.
        border: Border.all(color: OnCareColors.lineSubtle),
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            key: ValueKey<String>('dashboard-category-toggle-${widget.title}'),
            onTap: empty ? null : () => setState(() => _expanded = !_expanded),
            borderRadius: OnCareRadius.mdAll,
            child: Padding(
              padding: const EdgeInsets.all(OnCareSpacing.s12),
              child: Row(
                children: <Widget>[
                  AppStatusDot(color: widget.color),
                  const SizedBox(width: OnCareSpacing.s8),
                  Text(
                    widget.title,
                    style: tokens
                        .text(OnCareTypography.label)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                  const Spacer(),
                  if (empty)
                    // 펼칠 수 없는 칸은 화살표 없이 "없음"만 두되, 다른 칸의
                    // "완료 >" 가 차지하는 칸의 가운데에 선다 — 그 묶음을 보이지
                    // 않게 깔아 자리(폭·줄 높이)만 잡고 위에 얹는다.
                    Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Visibility(
                          visible: false,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: _status(
                            l.dashTaskCategoryDone,
                            OnCareColors.success,
                            Icons.chevron_right_rounded,
                          ),
                        ),
                        Text(
                          l.dashTaskCategoryEmpty,
                          style: _countStyle(
                            tokens,
                          ).copyWith(color: OnCareColors.textTertiary),
                        ),
                      ],
                    )
                  else
                    _status(
                      remaining == 0
                          ? l.dashTaskCategoryDone
                          : l.dashTaskCategoryRemaining(remaining),
                      remaining == 0
                          ? OnCareColors.success
                          : OnCareColors.textSecondary,
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.chevron_right_rounded,
                    ),
                ],
              ),
            ),
          ),
          // 펼친 채로 마지막 항목을 지우면 빈 칸이 열린 채 남지 않게 한다.
          if (_expanded && !empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OnCareSpacing.s8,
                0,
                OnCareSpacing.s8,
                OnCareSpacing.s8,
              ),
              child: Column(
                children: <Widget>[
                  for (final mission in widget.missions)
                    _MissionRow(
                      key: ValueKey<String>('dashboard-mission-${mission.key}'),
                      mission: mission,
                      checked: widget.checkedKeys.contains(mission.key),
                      onToggle: () => widget.onToggle(mission),
                      onDismiss: () => widget.onDismiss(mission.key),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({
    super.key,
    required this.mission,
    required this.checked,
    required this.onToggle,
    required this.onDismiss,
  });

  final _Mission mission;
  final bool checked;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final nameStyle = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(
          color: checked ? OnCareColors.textDisabled : OnCareColors.textPrimary,
        );
    final captionStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
      child: Material(
        color: OnCareColors.surfaceCard,
        shape: const RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: BorderSide(color: OnCareColors.lineSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: mission.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
            child: Row(
              children: <Widget>[
                Checkbox(value: checked, onChanged: (_) => onToggle()),
                const SizedBox(width: OnCareSpacing.s4),
                AppTag(
                  label: mission.keyword,
                  tone: mission.keywordColor == OnCareColors.danger
                      ? AppTagTone.danger
                      : AppTagTone.brand,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                // 고객 정보와 세부 내용을 한 줄에 이어 붙인다 — 아코디언 안은
                // 가로로 넉넉해서, 굳이 두 줄로 쌓아 세로 자리를 쓸 이유가
                // 없다.
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          mission.client?.name ?? mission.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),
                      if (mission.client != null) ...<Widget>[
                        const SizedBox(width: OnCareSpacing.s4),
                        Flexible(
                          child: Text(
                            clientDemographicsLabel(context, mission.client!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: captionStyle,
                          ),
                        ),
                      ],
                      if (mission.subtitle.isNotEmpty) ...<Widget>[
                        Text(' · ', style: captionStyle),
                        Flexible(
                          child: Text(
                            mission.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: captionStyle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AppIconButton(
                  key: ValueKey<String>(
                    'dashboard-mission-dismiss-${mission.key}',
                  ),
                  icon: Icons.delete_outline_rounded,
                  tooltip: l.actionDelete,
                  onPressed: onDismiss,
                  color: OnCareColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
