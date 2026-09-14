import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
// 같은 이름의 회원을 가르는 `남성 · 35세` 문구만 쓴다 — 그리는 위젯은 쓰지 않는다.
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show clientDemographicsLabel;
import 'package:oncare_ui/oncare_ui.dart';

/// 주간 리포트를 볼 고객을 고르는 왼쪽 목록.
class ReportClientPicker extends StatelessWidget {
  const ReportClientPicker({
    super.key,
    required this.clients,
    required this.selectedId,
    required this.onSelect,
  });

  final List<TrainerClient> clients;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// 한 번에 보이는 행 수. 넘치면 목록 안에서 스크롤한다(#1423).
  static const int _visibleRows = 5;

  /// 제목·부제 두 줄짜리 [AppListRow] 한 행의 웹 밀도 높이. 목록 칸 높이를
  /// 정하는 데만 쓴다 — 행은 글자 배율에 따라 스스로 자라고, 칸이 모자라면
  /// 스크롤한다.
  static const double _rowExtent = 68;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(title: l.navClients, icon: Icons.people_rounded),
          const SizedBox(height: OnCareSpacing.s12),
          SizedBox(
            height: _rowExtent * _visibleRows,
            child: ListView.separated(
              key: const ValueKey<String>('report-client-list-scroll'),
              itemCount: clients.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: OnCareSpacing.s4),
              itemBuilder: (context, index) {
                final client = clients[index];
                return AppListRow(
                  key: ValueKey<String>('report-client-${client.id}'),
                  selected: client.id == selectedId,
                  onTap: () => onSelect(client.id),
                  leading: AppAvatar(name: client.name),
                  title: client.name,
                  // 어느 고객의 리포트를 열지 고르는 자리다 — 이름만으로는
                  // 고를 근거가 되지 않는다(#898).
                  subtitle: client.goal.trim().isEmpty ? null : client.goal,
                  trailing: Text(
                    clientDemographicsLabel(context, client),
                    maxLines: 1,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
