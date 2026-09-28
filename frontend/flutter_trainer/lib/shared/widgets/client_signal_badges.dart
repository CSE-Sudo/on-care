import 'package:flutter/material.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/one_line_overflow.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// PT 관리 신호 배지 한 개(#2467).
///
/// [detailed] 면 근거 수치까지 적고(`칼로리 22% 과다`) 주의 아이콘을 단다 —
/// 회원 상세·대화 머리·이탈 위험 창처럼 이 사람을 열어 무엇을 손볼지 정하는
/// 자리다. 아니면 목록 배지와 같은 짧은 문구(`칼로리 과다`)다.
class ClientSignalTag extends StatelessWidget {
  const ClientSignalTag({
    super.key,
    required this.signal,
    this.detailed = true,
    this.onTap,
  });

  final ClientSignal signal;
  final bool detailed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTag(
      label: detailed ? signal.detailLabel(l) : signal.badgeLabel(l),
      icon: detailed ? AppIcons.error : null,
      tone: signal.kind.tone,
      onTap: onTap,
    );
  }
}

/// 신호 배지 한 줄 — 넘치면 `+N` 으로 묶고 눌러 펼친다(#2330·#2467).
///
/// 급한 순으로 한 줄에 들어가는 만큼 세우고, 넘치는 것은 `+N` 으로 묶는다.
/// `+N` 을 누르면 이 자리에서 전부 펼치고(줄바꿈), `접기` 로 다시 한 줄이 된다.
/// 회원 상세 머리와 메시지 대화 머리가 이 한 벌을 쓴다.
///
/// 펼친 줄에서 배지 하나가 줄 폭보다 길면(좁은 패널 · 큰 글씨) 줄여서
/// 들인다(#2337). 말줄임하지 않는다 — `칼로리 22% 과…` 처럼 잘린 문구·숫자는
/// 다른 값으로 읽힌다. 접힌 줄은 폭 제약 없이 재므로 여기서 달라지지 않는다.
///
/// 키는 [keyPrefix] 로 짓는다 — 줄 `<prefix>-signals`, 배지
/// `<prefix>-alert-<wire>`, 펼치기 `<prefix>-signals-more-<N>`, 접기
/// `<prefix>-signals-less`.
class ClientSignalBadges extends StatefulWidget {
  const ClientSignalBadges({
    super.key,
    required this.signals,
    required this.keyPrefix,
    this.onOpen,
  });

  final List<ClientSignal> signals;
  final String keyPrefix;

  /// 배지를 누르면 부른다. null 이면 배지는 누를 수 없다(`+N` 은 늘 눌린다).
  final ValueChanged<ClientSignal>? onOpen;

  @override
  State<ClientSignalBadges> createState() => _ClientSignalBadgesState();
}

class _ClientSignalBadgesState extends State<ClientSignalBadges> {
  bool _expanded = false;

  List<Widget> _badges() {
    final ValueChanged<ClientSignal>? onOpen = widget.onOpen;
    return <Widget>[
      for (final ClientSignal signal in widget.signals)
        KeyedSubtree(
          key: ValueKey<String>(
            '${widget.keyPrefix}-alert-${signal.kind.wire}',
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ClientSignalTag(
              signal: signal,
              onTap: onOpen == null ? null : () => onOpen(signal),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Key lineKey = ValueKey<String>('${widget.keyPrefix}-signals');
    if (_expanded) {
      return Wrap(
        key: lineKey,
        spacing: OnCareSpacing.s8,
        runSpacing: OnCareSpacing.s4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ..._badges(),
          AppTag(
            key: ValueKey<String>('${widget.keyPrefix}-signals-less'),
            label: l.clientSignalLess,
            onTap: () => setState(() => _expanded = false),
          ),
        ],
      );
    }
    return OneLineOverflow(
      key: lineKey,
      spacing: OnCareSpacing.s8,
      items: _badges(),
      moreBuilder: (int hidden) => AppTag(
        key: ValueKey<String>('${widget.keyPrefix}-signals-more-$hidden'),
        label: l.clientSignalMore(hidden),
        onTap: () => setState(() => _expanded = true),
      ),
    );
  }
}
