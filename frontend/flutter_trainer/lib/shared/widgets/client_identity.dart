import 'package:flutter/material.dart';

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 문구·조회 함수는 `shared/utils` 로 옮겼다(#1703). 기존 사용처를 위해 다시 내보낸다.
export 'package:oncare_trainer/shared/utils/client_identity_labels.dart';

/// 트레이너 웹 회원 행의 밀도(#2467).
///
/// 회원 행은 탭마다 따로 그려져, 같은 회원의 이름이 화면마다 14·15·16 에
/// 굵기까지 갈려 있었다. 밀도 세 가지만 두고 아바타 크기·간격·글씨를 여기서
/// 정한다 — 같은 밀도의 행은 어느 탭에서나 같은 글씨다.
enum ClientRowDensity {
  /// 회원 목록·메시지 목록·검색 결과 — 회원을 훑고 고르는 넓은 목록.
  list(AppAvatarSize.large, OnCareSpacing.s12),

  /// 회원 고르기·리포트 작업대·스케줄 세션 카드 — 좁은 열의 촘촘한 목록.
  compact(AppAvatarSize.medium, OnCareSpacing.s8),

  /// 메시지 대화 머리·회원 상세 머리 — 지금 보고 있는 한 사람.
  header(AppAvatarSize.large, OnCareSpacing.s12);

  const ClientRowDensity(this.avatarSize, this.avatarGap);

  /// 행 왼쪽 [ClientAvatar] 의 지름 단계.
  final AppAvatarSize avatarSize;

  /// 아바타와 이름 묶음 사이 간격.
  final double avatarGap;

  TextStyle _nameRole() => switch (this) {
    ClientRowDensity.list => OnCareTypography.strong(
      OnCareTypography.bodyLarge,
    ),
    ClientRowDensity.compact => OnCareTypography.strong(
      OnCareTypography.bodySmall,
    ),
    ClientRowDensity.header => OnCareTypography.titleSmall,
  };
}

/// [density] 행의 이름 글씨. 배치가 달라 [ClientIdentityBlock] 을 쓰지 못하는
/// 자리(회원 상세 머리·이탈 위험 창 등)도 이 값을 쓴다.
TextStyle clientNameStyle(BuildContext context, ClientRowDensity density) =>
    context.oncare
        .text(density._nameRole())
        .copyWith(color: OnCareColors.textPrimary);

/// 이름 옆 `성별 · 나이` 글씨 — 밀도와 상관없이 이름보다 작고 흐리다.
TextStyle clientDemographicsStyle(BuildContext context) => context.oncare
    .text(OnCareTypography.caption)
    .copyWith(color: OnCareColors.textTertiary);

/// [density] 행 둘째 줄(목표·요약·전송일) 글씨. 넓은 목록만 한 단계 크다.
TextStyle clientDetailStyle(BuildContext context, ClientRowDensity density) =>
    density == ClientRowDensity.list
    ? context.oncare
          .text(OnCareTypography.bodySmall)
          .copyWith(color: OnCareColors.textSecondary)
    : context.oncare
          .text(OnCareTypography.caption)
          .copyWith(color: OnCareColors.textTertiary);

/// 회원 행의 이름 묶음 — 첫 줄 `이름  성별 · 나이`, 둘째 줄 목표. (#2467)
///
/// 둘째 줄은 기본이 회원 건강 목표이고 늘 [healthFocusGoalLabel] 을 거친다 —
/// 저장 값은 한국어라, 그대로 적으면 영어 화면에서 이 자리만 한국어로 남았다.
/// 목표 대신 전송일·검색 요약처럼 그 자리의 말을 [detail] 로 줄 수 있고,
/// [showDetail] 을 끄면 첫 줄만 그린다(메시지 목록은 그 자리에 미리보기를 둔다).
/// 둘째 줄 글이 비면 빈 줄로 행 높이를 먹지 않는다(#898).
///
/// 이름과 `성별 · 나이` 는 글자 바닥선을 맞춘다 — 크기가 다른 두 글이 가운데
/// 정렬이면 작은 글이 떠 보인다. 모든 글은 한 줄 말줄임이다.
class ClientIdentityBlock extends StatelessWidget {
  const ClientIdentityBlock({
    super.key,
    required this.client,
    this.density = ClientRowDensity.list,
    this.detail,
    this.detailMaxLines = 1,
    this.showDetail = true,
    this.stacked = false,
  });

  final TrainerClient client;
  final ClientRowDensity density;

  /// 목표 대신 둘째 줄에 적을 글. null 이면 목표다.
  final String? detail;
  final int detailMaxLines;
  final bool showDetail;

  /// `성별 · 나이` 를 이름 옆이 아니라 아래에 쌓는다 — 프로그램 탭 좁은 화면의
  /// 가로로 늘어선 회원 줄처럼 칸 폭이 좁은 자리.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final Widget name = Text(
      client.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: clientNameStyle(context, density),
    );
    final Widget demographics = Text(
      clientDemographicsLabel(context, client),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: clientDemographicsStyle(context),
    );
    final String second = !showDetail
        ? ''
        : detail ??
              healthFocusGoalLabel(AppLocalizations.of(context), client.goal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (stacked) ...<Widget>[name, demographics] else
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(child: name),
              const SizedBox(width: OnCareSpacing.s4),
              Flexible(child: demographics),
            ],
          ),
        if (second.trim().isNotEmpty)
          Text(
            second,
            maxLines: detailMaxLines,
            overflow: TextOverflow.ellipsis,
            style: clientDetailStyle(context, density),
          ),
      ],
    );
  }
}

/// 트레이너 웹의 회원 행 — 아바타 + [ClientIdentityBlock]. (#2467)
///
/// 아바타 크기와 간격은 [density] 가 정한다. [trailing] 은 이름 묶음 오른쪽
/// (세션 종류 알약·읽음 배지처럼 이 행에 딸린 값)이다. 행을 감싸는 카드·
/// 눌림·선택 표시는 부르는 쪽이 정한다 — 목록마다 담는 그릇이 다르다.
class ClientRow extends StatelessWidget {
  const ClientRow({
    super.key,
    required this.client,
    this.density = ClientRowDensity.list,
    this.detail,
    this.detailMaxLines = 1,
    this.showDetail = true,
    this.stacked = false,
    this.trailing,
  });

  final TrainerClient client;
  final ClientRowDensity density;

  /// [ClientIdentityBlock.detail] 과 같다.
  final String? detail;
  final int detailMaxLines;
  final bool showDetail;

  /// [ClientIdentityBlock.stacked] 와 같다.
  final bool stacked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget? trailing = this.trailing;
    return Row(
      children: <Widget>[
        ClientAvatar(name: client.avatar, size: density.avatarSize),
        SizedBox(width: density.avatarGap),
        Expanded(
          child: ClientIdentityBlock(
            client: client,
            density: density,
            detail: detail,
            detailMaxLines: detailMaxLines,
            showDetail: showDetail,
            stacked: stacked,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          trailing,
        ],
      ],
    );
  }
}
