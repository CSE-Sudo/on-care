import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/consultation_request_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 내 상담 요청 전체 내역(#948). 운동 탭은 대기 중이거나 가장 최근 요청 1건만
/// 요약해 보여준다 — 요청이 누적될수록 과거 이력을 확인할 곳이 없었다. 이
/// 화면은 그 전체 이력을 진행 중/지난 요청으로 나눠 보여준다.
///
/// `consultationRequestControllerProvider` 가 이미 `GET /consultations/me`
/// 전체를 들고 있어 별도 API 호출이 필요 없다.
class ConsultationHistoryPage extends ConsumerWidget {
  const ConsultationHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        // 빈 화면도 목록과 같은 최대 폭 틀 안에 둔다.
        if (requests.isEmpty) AppEmptyState(title: l.exConsultHistoryEmpty),
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
              onCancel: () async {
                // 되돌릴 수 없는 쪽이다 — 확정은 파괴적 채움으로, 유지는
                // 중립 버튼으로 그려 두 동작의 위험도 차이가 보이게 한다
                // (#1429).
                final bool confirmed = await showAppConfirmDialog(
                  context: context,
                  title: l.exConsultHistoryCancelTitle,
                  message: l.exConsultHistoryCancelBody,
                  cancelLabel: l.exCancelKeep,
                  confirmLabel: l.actionCancel,
                  destructive: true,
                );
                if (confirmed) {
                  await ref
                      .read(consultationRequestControllerProvider.notifier)
                      .cancel(r.id);
                }
              },
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
