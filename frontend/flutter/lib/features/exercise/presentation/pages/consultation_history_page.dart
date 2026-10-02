import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/consultation_request_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 내 상담 요청 전체 내역(#948). 운동 탭은 대기 중이거나 가장 최근 요청 1건만
/// 요약해 보여준다 — 요청이 누적될수록 과거 이력을 확인할 곳이 없었다. 이
/// 화면은 그 전체 이력을 진행 중/지난 요청으로 나눠 보여준다.
///
/// `consultationRequestControllerProvider` 가 이미 `GET /consultations/me`
/// 전체를 들고 있어 별도 API 호출이 필요 없다. 다만 열 때마다 그 목록을 다시
/// 받는다(#2067) — 이 화면이 보여 주는 것은 트레이너의 결정과 사유인데, 들고 있던
/// 목록은 결정 전 것일 수 있다.
class ConsultationHistoryPage extends ConsumerStatefulWidget {
  const ConsultationHistoryPage({super.key});

  @override
  ConsumerState<ConsultationHistoryPage> createState() =>
      _ConsultationHistoryPageState();
}

class _ConsultationHistoryPageState
    extends ConsumerState<ConsultationHistoryPage> {
  /// 열 때 받는 서버 목록을 기다리는 중인가. (#2858)
  bool _loading = true;

  /// 열 때 받는 서버 목록이 실패했는가. (#2858)
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 서버 목록을 받는다. 들고 있는 목록이 비어 있을 때 읽는 중·실패를 '요청
  /// 없음' 과 가르는 근거다(#2858) — 예전에는 셋 다 빈 상태 문구로 보여, 신청을
  /// 낸 회원이 다시 신청하려다 중복 대기에 막혔다.
  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    final bool ok = await ref
        .read(consultationRequestControllerProvider.notifier)
        .refresh();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = !ok;
    });
  }

  /// 확인 뒤 취소한다. 실패하면 안내하고 카드를 그대로 둔다(#2858). 이미
  /// 트레이너가 결정했거나 서버에 없는 요청이면 서버 목록을 다시 받아 카드를
  /// 실제 상태로 바꾼다.
  Future<void> _cancel(AppLocalizations l, ConsultationRequest r) async {
    // 되돌릴 수 없는 쪽이다 — 확정은 파괴적 채움으로, 유지는 중립 버튼으로
    // 그려 두 동작의 위험도 차이가 보이게 한다(#1429).
    final bool confirmed = await showAppConfirmDialog(
      context: context,
      title: l.exConsultHistoryCancelTitle,
      message: l.exConsultHistoryCancelBody,
      cancelLabel: l.exCancelKeep,
      // `예약 취소` 와 같이 무엇을 취소하는지 붙인다(#2554).
      confirmLabel: l.exConsultHistoryCancelAction,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final AppToastHost toast = AppToastHost.of(context);
    final ConsultationRequestController controller = ref.read(
      consultationRequestControllerProvider.notifier,
    );
    try {
      await controller.cancel(r.id);
    } on ConsultationNoLongerPending {
      toast.show(l.exConsultCancelStale);
      await controller.refresh();
    } on ConsultationNotFound {
      toast.show(l.exConsultCancelStale);
      await controller.refresh();
    } on Object {
      toast.show(l.exConsultCancelFailed, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ConsultationRequest> requests = ref.watch(
      consultationRequestControllerProvider,
    );
    final List<ConsultationRequest> inProgress = requests
        .where(
          (ConsultationRequest r) => r.status == ConsultationStatus.pending,
        )
        .toList(growable: false);
    // 서버가 이미 최신순으로 준다(#948) — 다시 정렬하지 않는다.
    final List<ConsultationRequest> past = requests
        .where(
          (ConsultationRequest r) => r.status != ConsultationStatus.pending,
        )
        .toList(growable: false);

    return AppPage(
      header: AppTopBar(title: l.exConsultHistoryTitle),
      children: <Widget>[
        // 빈 화면도 목록과 같은 최대 폭 틀 안에 둔다. 들고 있는 목록이 비었을
        // 때는 읽는 중·실패·정말 없음을 가른다(#2858) — 실제로 낸 요청이 없을
        // 때만 빈 상태 문구다.
        if (requests.isEmpty)
          if (_loading)
            const AppLoading(
              key: Key('consult-history-loading'),
              placement: AppStatePlacement.card,
            )
          else if (_failed)
            AppErrorState(
              key: const Key('consult-history-error'),
              title: l.exConsultHistoryLoadError,
              retryLabel: l.actionRetry,
              onRetry: () => unawaited(_load()),
              placement: AppStatePlacement.card,
            )
          else
            AppEmptyState(title: l.exConsultHistoryEmpty),
        if (inProgress.isNotEmpty) ...<Widget>[
          Text(
            l.exConsultHistoryInProgress,
            style: context.oncare
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          for (final ConsultationRequest r in inProgress) ...<Widget>[
            ConsultationRequestCard(
              key: ValueKey<String>('consult-history-${r.id}'),
              request: r,
              onCancel: () => _cancel(l, r),
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
        ],
        // `지난 요청` 소제목은 두지 않는다(#1429). 완료·취소는 카드가 상태로
        // 말하고 있어, 소제목은 같은 목록을 한 겹 더 나누기만 했다. 진행 중
        // 묶음과 같은 간격으로 이어 붙어 카드 흐름이 끊기지 않는다.
        for (final ConsultationRequest r in past) ...<Widget>[
          ConsultationRequestCard(
            key: ValueKey<String>('consult-history-${r.id}'),
            request: r,
          ),
          const SizedBox(height: OnCareSpacing.cardGap),
        ],
      ],
    );
  }
}
