import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The colour that carries [alert]'s meaning.
///
/// 하나의 색은 하나의 뜻만: 남색 = 처리 필요, 빨강 = 주의(목표 초과와 완료율
/// 저조를 함께 포함). 답장 대기의 시급함은 색이 아니라 목록 맨 위에 오는 순서가
/// 말한다.
///
/// 예전에는 완만한 주의를 주황으로 따로 두었는데, 회원이 자기 폰에서 빨갛게 보는
/// 것을 트레이너는 주황으로 봐서 **두 앱이 같은 사실을 다른 세기로** 말했다(#690).
Color alertColor(ClientAlert alert) => switch (alert) {
  ClientAlert.unanswered => OnCareBrand.trainer.primary,
  ClientAlert.sodiumOver => OnCareColors.danger,
  // 회원 앱이 당류 초과를 빨갛게 보여 준다 — 같은 사실을 같은 세기로.
  ClientAlert.sugarOver => OnCareColors.danger,
  ClientAlert.lowCompletion => OnCareColors.danger,
};

/// A pill naming why a client is flagged.
///
/// Shared so the 대시보드 row and the client detail header can never
/// disagree about an alert's colour — the switch above used to be copied
/// into both, comment and all.
class AlertBadge extends StatelessWidget {
  /// Creates a badge for [alert].
  const AlertBadge({super.key, required this.alert, this.showIcon = true});

  /// The reason being shown.
  final ClientAlert alert;

  /// Whether to lead with the warning glyph. The dashboard row sits in a
  /// card already titled 확인 필요 고객, so it drops the icon; the detail
  /// header has no such framing and keeps it.
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final color = alertColor(alert);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showIcon ? 9 : 7,
        vertical: showIcon ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(OnCareRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showIcon) ...<Widget>[
            Icon(Icons.error_outline, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            alert.label(AppLocalizations.of(context)),
            style: TextStyle(
              fontSize: showIcon ? 11 : 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
