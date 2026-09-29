import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/consultations/data/dtos/consultation_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 상담 일정의 `상담 요청 내용` — 회원이 신청할 때 적은 운동 목표·문의 글. (#2584)
///
/// 읽기 전용이다. 트레이너가 적는 자리는 아래 상담 메모이고, 이 상자는 회원이
/// 보낸 것을 그대로 보여 준다. 예전에는 수락이 문의 글을 일정 메모에 넣어
/// `트레이너 메모` 제목 아래 회원 글이 떴다.
///
/// 목표·문의의 이름표는 상담 인박스 카드와 같다 — 같은 요청을 두 화면이 다른
/// 말로 부르지 않는다.
class SessionConsultationBox extends StatelessWidget {
  const SessionConsultationBox({super.key, required this.consultation});

  final ScheduleConsultation consultation;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle labelStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    final TextStyle valueStyle = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textPrimary);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 64, child: Text(label, style: labelStyle)),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
    return AppTile(
      key: const ValueKey<String>('session-consultation-request'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.schedConsultRequest,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s2),
          row(
            l.consultExerciseGoal,
            label(exerciseGoalLabels(l), consultation.goalCode),
          ),
          if (consultation.message != null)
            row(l.consultMessage, consultation.message!),
        ],
      ),
    );
  }
}
