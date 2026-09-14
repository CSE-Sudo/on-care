import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주간 리포트를 볼 고객을 고르는 왼쪽 목록.
///
/// 행은 프로그램 탭 회원 목록과 같은 [ClientPickerCard] 다 — 탭을 오갈 때
/// 같은 목록이 다른 모양으로 보이지 않게 한다.
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double rowHeight = clientPickerRowHeight(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(title: l.navClients, icon: clientPickerHeaderIcon),
          const SizedBox(height: OnCareSpacing.s12),
          // 한 번에 5줄만 보이고, 넘치면 목록 안에서 스크롤한다(#1423).
          SizedBox(
            height: rowHeight * clientPickerVisibleRows,
            child: ListView.builder(
              key: const ValueKey<String>('report-client-list-scroll'),
              padding: EdgeInsets.zero,
              itemCount: clients.length,
              itemExtent: rowHeight,
              itemBuilder: (context, index) {
                final client = clients[index];
                return ClientPickerCard(
                  key: ValueKey<String>('report-client-${client.id}'),
                  client: client,
                  selected: client.id == selectedId,
                  onTap: () => onSelect(client.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
