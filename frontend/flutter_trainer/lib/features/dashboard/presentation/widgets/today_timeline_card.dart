import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_chips.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `HH:mm`.
String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Today's timeline, condensed for the dashboard: a "지금 · 다음 수업" 배너
/// 위에, 시간·상태 점·누구+무엇·상태 알약이 이어진다. 빈 시간(공백 슬롯)은
/// 오늘의 예약이 무엇인지와 무관해 아예 그리지 않는다 — 여기는 "오늘 할
/// 일"이 아니라 "오늘 누굴 보나" 목록이다.
class TodayTimelineCard extends ConsumerWidget {
  /// Creates the card.
  const TodayTimelineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final schedule = ref.watch(todayScheduleProvider);
    final clients =
        ref.watch(clientsProvider).valueOrNull ?? const <TrainerClient>[];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(
            title: l.dashTodaySchedule,
            icon: AppIcons.calendar,
            actionLabel: l.dashSeeAll,
            onAction: () => context.go(AppRoutes.scheduleAt()),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          schedule.when(
            loading: () => const AppLoading(placement: AppStatePlacement.card),
            error: (e, _) => AppEmptyState(
              title: l.dashScheduleLoadFailed,
              icon: AppIcons.offline,
              placement: AppStatePlacement.card,
            ),
            data: (sessions) {
              final booked = sessions.where((s) => !s.isGap).toList();
              if (booked.isEmpty) {
                return AppEmptyState(
                  title: l.dashNoScheduleToday,
                  icon: AppIcons.eventBusy,
                  placement: AppStatePlacement.card,
                );
              }
              // 담당이 끊긴 회원의 일정은 준비할 수업이 아니다(#2589).
              final next = booked
                  .where((s) => s.isUpcoming && !s.memberDetached)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (next.isNotEmpty) ...<Widget>[
                    _NextUpBanner(
                      now: nowKst(),
                      next: next.first,
                      client: findClientIdentity(
                        clients,
                        clientId: next.first.clientId,
                        clientName: next.first.clientName,
                      ),
                    ),
                    const SizedBox(height: OnCareSpacing.s8),
                  ],
                  for (final session in booked)
                    _Row(
                      key: ValueKey<String>('dashboard-schedule-${session.id}'),
                      session: session,
                      client: session.memberDetached
                          ? null
                          : findClientIdentity(
                              clients,
                              clientId: session.clientId,
                              clientName: session.clientName,
                            ),
                      // 로스터에 없는 고객(상담으로 잡힌 가망 고객)도 이름만
                      // 부른다 — 스케줄 탭과 같은 표기다(#1012). 담당이 끊긴
                      // 회원은 화면 언어의 `해제 회원` 이다(#2589).
                      fallbackName: session.memberDetached
                          ? l.schedDetachedMember
                          : session.clientName,
                      onTap: () => context.go(
                        AppRoutes.scheduleAt(
                          date: session.date,
                          sessionId: session.id,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "지금 16:03  다음 수업 17:00 · 신규 고객  56분 뒤" — 오늘의 다음 일정이
/// 무엇이고 얼마나 남았는지, 그리고 그 일정에 맞는 행동(수업 준비/메모)을
/// 목록을 훑지 않고도 알 수 있게 한 줄로 요약한다.
///
/// 바탕은 옅은 회색(`surfaceInput`)이고 테두리가 없다(#2202). 예전에는 안내
/// 배너(`AppBanner` info)처럼 옅은 남색 + 남색 테두리였는데, 바로 아래
/// 활동 피드백 카드(카드형 `AppBanner`)와 바탕·채움 버튼이 같아 두 영역이 한
/// 덩어리처럼 보였다. 회색 카드 안 구획([AppTileTone.neutral])에 한 줄 요약
/// 글자와 키가 달린 동작 버튼을 담는다.
class _NextUpBanner extends StatelessWidget {
  const _NextUpBanner({required this.now, required this.next, this.client});

  final DateTime now;
  final ScheduleSession next;
  final TrainerClient? client;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final name = client?.name ?? next.clientName;
    final nextMinutes = clockMinutes(next.time);
    final minutesLeft = nextMinutes == null
        ? 0
        : (nextMinutes - (now.hour * 60 + now.minute)).clamp(0, 24 * 60);
    // 상담은 "메모 남기기"로, 그 외(1:1 PT 등)는 "PT 준비하기"로 갈린다 —
    // 상담엔 준비할 프로그램이 없고, PT엔 남길 상담 메모가 없다. 계약값으로
    // 가른다(#2867).
    final isConsultation = next.isConsultation;
    final clientId = client?.id;
    final TextStyle base = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);

    return AppTile(
      tone: AppTileTone.neutral,
      child: Row(
        children: <Widget>[
          AppIcon(
            AppIcons.clock,
            size: OnCareSize.iconMedium,
            color: tokens.brand.primary,
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: base,
                children: <InlineSpan>[
                  TextSpan(text: l.dashScheduleNowLabel(_hm(now))),
                  const TextSpan(text: '   '),
                  TextSpan(
                    text: l.dashScheduleNextSession(next.time, name),
                    style: const TextStyle(color: OnCareColors.textPrimary),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: l.dashScheduleMinutesLeft(minutesLeft),
                    style: OnCareTypography.strong(
                      base,
                    ).copyWith(color: tokens.brand.primary),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          AppButton(
            key: const ValueKey<String>('dashboard-next-session-cta'),
            // 상담은 트레이너만 보는 메모, 로스터에 없는 회원의 PT 는 회원에게
            // 가는 피드백을 남기러 간다(#2574).
            label: isConsultation
                ? l.dashLeaveMemo
                : clientId == null
                ? l.dashLeaveFeedback
                : l.dashPreparePt,
            onPressed: () => context.go(
              isConsultation || clientId == null
                  // 날짜만 실어 보내면 그날 첫 일정이 열려, 정작 메모를
                  // 남기려던 상담이 아닌 다른 일정이 선택된다(#1422).
                  // 스케줄 화면은 `session` 을 받아 그 일정을 고를 수 있다.
                  ? AppRoutes.scheduleAt(date: next.date, sessionId: next.id)
                  : AppRoutes.coachingFor(clientId),
            ),
            size: OnCareButtonSize.small,
            leadingIcon: AppIcons.forward,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.session,
    required this.client,
    required this.fallbackName,
    required this.onTap,
  });

  final ScheduleSession session;
  final TrainerClient? client;

  /// 로스터에서 못 찾은 고객을 부를 이름.
  final String fallbackName;

  final VoidCallback onTap;

  /// 시간 칸 폭 — `18:00–18:50` 이 한 줄에 들어간다.
  static const double _timeColumnWidth = 92;

  /// 오른쪽 상태 칸 앞에 늘 서는 폭 — 시간 칸 · 상태 점과 그 뒤 간격 ·
  /// 이름 칸 뒤 간격.
  static const double _leadingWidth =
      _timeColumnWidth + OnCareSize.dot + OnCareSpacing.s8 + OnCareSpacing.s4;

  Color _dotColor(BuildContext context) {
    if (session.isDone) return OnCareColors.success;
    if (session.isUpcoming) return context.oncare.brand.primary;
    return OnCareColors.textDisabled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final isConsultation = session.isConsultation;
    // 완료된 세션은 시간도 함께 물러난다 — 종류 알약이 완료 때 회색으로
    // 바래는 것과 같은 기준이다. 아직 끝나지 않은 시간은 "지금 처리해야
    // 할 일"이라 검은 글씨로 또렷하게 남는다.
    final timeColor = session.isDone
        ? OnCareColors.textTertiary
        : OnCareColors.textPrimary;
    // "준비"는 아직 끝나지 않은 수업이 프로그램을 미리 짜 뒀는가이고,
    // "전송"(PT)/"작성"(상담)은 끝난 뒤 실제로 회원에게 나간 결과다 — 같은
    // 세션이 두 라벨을 동시에 달 일은 없다. 되지 않은 쪽도 회색으로나마
    // 항상 보여준다 — 라벨이 아예 없으면 "아직 안 했다"와 "이 세션엔 해당
    // 없다"를 구분할 수 없다. 상담이 끝나기 전만 예외(아직 남길 메모
    // 자체가 없다).
    String? statusTagLabel;
    AppTagTone statusTagTone = AppTagTone.brand;
    if (isConsultation) {
      if (session.isDone) {
        final written = session.note.trim().isNotEmpty;
        statusTagLabel = written
            ? l.dashSessionNoteWritten
            : l.dashSessionNoteNotWritten;
        statusTagTone = written ? AppTagTone.caution : AppTagTone.neutral;
      }
    } else if (session.isDone) {
      statusTagLabel = session.programSent
          ? l.dashSessionSent
          : l.dashSessionSentNo;
      statusTagTone = session.programSent
          ? AppTagTone.success
          : AppTagTone.neutral;
    } else {
      final prepared = session.program.isNotEmpty;
      statusTagLabel = prepared
          ? l.dashSessionPrepared
          : l.dashSessionPreparedNo;
      statusTagTone = prepared ? AppTagTone.brand : AppTagTone.neutral;
    }

    final TextStyle nameStyle = tokens
        .text(OnCareTypography.label)
        .copyWith(color: OnCareColors.textPrimary);

    return InkWell(
      onTap: onTap,
      borderRadius: OnCareRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: OnCareSpacing.s8,
          horizontal: OnCareSpacing.s4,
        ),
        // 오른쪽 칸(완료/예정 + 상태 알약)이 둘로 쌓이면 왼쪽보다 키가 커진다
        // — Row 기본값인 가운데 정렬이라 시간·점도 그 가운데로 맞춰진다.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) => Row(
            children: <Widget>[
              // 큰 글씨(배율 1.3 부터)에서는 시간이 칸보다 길다 — 줄여서
              // 들인다(#2433). 예전에는 `12:00–12:` 처럼 잘려 다른 시간으로
              // 읽혔다.
              SizedBox(
                width: _timeColumnWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    timeRangeLabel(l, session),
                    maxLines: 1,
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.label),
                    ).copyWith(color: timeColor),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: OnCareSpacing.s8),
                child: AppStatusDot(color: _dotColor(context)),
              ),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      flex: 3,
                      child: client == null
                          ? Text(
                              fallbackName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    client!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: nameStyle,
                                  ),
                                ),
                                const SizedBox(width: OnCareSpacing.s4),
                                Flexible(
                                  child: Text(
                                    clientDemographicsLabel(context, client!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tokens
                                        .text(OnCareTypography.caption)
                                        .copyWith(
                                          color: OnCareColors.textTertiary,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(width: OnCareSpacing.s4),
                    // 이름이 길어 좁아지면 종류 태그가 먼저 줄어든다 — `Flexible`
                    // 로 상한을 받고 `FittedBox` 로 그 안에서 축소된다.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        // 저장된 종류는 계약값이라 화면 언어로 옮겨 적는다
                        // — 스케줄 탭 카드·주간 표와 같은 문구다(#2867).
                        child: AppTag(
                          label: sessionTypeLabel(l, session.type),
                          tone: session.isDone
                              ? AppTagTone.neutral
                              : AppTagTone.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              // 완료/예정 알약과 나란히, 세로로는 이 줄 전체 기준 가운데 —
              // 아래에 쌓지 않아야 왼쪽 시간·점과 같은 높이로 읽힌다.
              //
              // 시간·점을 뺀 폭보다 길면(좁은 화면 · 큰 글씨) 줄여서 들인다
              // (#2433). 들어갈 때는 그대로라 평소 모양은 달라지지 않는다.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, c.maxWidth - _leadingWidth),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (statusTagLabel != null) ...<Widget>[
                        AppTag(label: statusTagLabel, tone: statusTagTone),
                        const SizedBox(width: OnCareSpacing.s4),
                      ],
                      SessionStatusChip(status: session.status),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
