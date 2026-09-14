import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `1:1 PT` — 이 약속이 무엇인가. (#938)
///
/// 상태 칩과 나란히 서지만 뜻이 갈린다. 상태는 "어떻게 됐나"(예정·완료·취소),
/// 이쪽은 "무엇인가" 다. 그래서 톤도 갈라 둔다 — 1:1 PT 는 브랜드 톤, 상담은
/// 중립 톤이다. 끝난 세션은 종류와 상관없이 중립 톤으로 물러난다.
///
/// 좁아지면 **이 알약이 먼저 줄어든다.** 이름과 상태는 잘리면 안 되는 값이라,
/// 글자를 자르는 대신 `FittedBox` 로 통째로 작게 그린다.
class SessionTypeChip extends StatelessWidget {
  const SessionTypeChip({
    super.key,
    required this.label,
    required this.muted,
    this.prominent = false,
    this.outlined = false,
    this.compact = false,
  });

  final String label;

  /// 끝난 세션인가. 상태 칩과 같은 기준으로 함께 물러난다.
  final bool muted;

  /// 상세 카드의 프로필 줄에 서는가. (#1012)
  ///
  /// [AppTag] 는 크기가 하나라 치수가 달라지지 않는다. 호출하는 자리가 뜻을
  /// 남기도록 이름만 남겨 둔다.
  final bool prominent;

  /// 시간표 블록 안에 서는가. (#1013)
  ///
  /// 블록의 둘째 줄은 이름과 종류가 나눠 쓰는 한 줄이다. 줄 높이는 블록이
  /// 이름 글자로 재어 이 알약에 그 높이만 주고, 알약은 `FittedBox` 로 그
  /// 안에 통째로 줄어든다 — 알약 때문에 줄이 두꺼워지면 30분 블록에서 이름
  /// 줄이 통째로 사라진다(#1010).
  final bool compact;

  /// 상담인가. 색을 하나 더 들이는 대신 **브랜드 톤과 중립 톤**으로 종류를
  /// 가른다 — 시간표 블록이 1:1 PT 는 채우고 상담은 비우는 것과 같은 갈래다
  /// (#1013).
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: AppTag(
        key: const ValueKey<String>('session-type-chip'),
        label: label,
        tone: muted || outlined ? AppTagTone.neutral : AppTagTone.brand,
      ),
    );
  }
}

/// 예정·완료·취소·노쇼 — 이 약속이 **어떻게 됐나**. (#871)
///
/// 무엇인가를 말하는 [SessionTypeChip] 과 나란히 서지만 톤으로 결과를
/// 구분한다.
class SessionStatusChip extends StatelessWidget {
  const SessionStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    // 예정(브랜드) · 완료(초록) · 취소/노쇼(주의)로 갈라 둔다. 진행되지 않은
    // 세션이 완료와 같은 색이면 "끝난 수업" 으로 읽히고, 예정과 같은 톤이면
    // 아직 할 일로 읽힌다 — 둘 다 사실이 아니다(#871).
    //
    // 완료를 회색으로 두었더니 시간표 블록의 초록 띠와 어긋났다. 같은 사실을
    // 두 자리가 다른 색으로 말하면 어느 쪽을 믿어야 할지 알 수 없다(#1012).
    final AppTagTone tone = switch (status) {
      ScheduleStatus.done => AppTagTone.success,
      ScheduleStatus.cancelled || ScheduleStatus.noShow => AppTagTone.caution,
      _ => AppTagTone.brand,
    };
    return AppTag(
      // 톤은 계약값(`status`)으로 고르고, 글자는 로케일 문구로 그린다.
      label: scheduleStatusLabel(AppLocalizations.of(context), status),
      tone: tone,
    );
  }
}
