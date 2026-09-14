import 'package:flutter/material.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';

/// 주간 리포트를 볼 고객을 고르는 왼쪽 목록.
///
/// 프로그램 탭 회원 목록과 **같은 위젯**([ClientPickerList])이다 — 카드 제목·
/// 아이콘, 행 높이·여백, 고른 모양, 고른 회원을 따라가는 스크롤까지 같다.
/// 다른 것은 행 키(`report-client-*`)와 목록 스크롤 키뿐이다.
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
    return ClientPickerList(
      clients: clients,
      selectedId: selectedId,
      onSelect: onSelect,
      rowKeyPrefix: 'report-client',
      scrollKey: 'report-client-list-scroll',
    );
  }
}
