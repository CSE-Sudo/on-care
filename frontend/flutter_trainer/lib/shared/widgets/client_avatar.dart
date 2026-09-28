import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이니셜 글씨 크기 : 지름.
const double _kInitialFactor = 0.34;

/// 회원 아바타가 칠하는 남색 두 톤 — 위 왼쪽 [OnCareBrand.primary] 에서 아래
/// 오른쪽 [OnCareBrand.strong] 으로. 테스트가 같은 값을 바로 비교하도록 밖에
/// 둔다(#2448).
final List<Color> clientAvatarColors = <Color>[
  OnCareBrand.trainer.primary,
  OnCareBrand.trainer.strong,
];

/// 트레이너 웹의 **회원 프로필 원** 한 벌(#2448).
///
/// 리포트 탭 `전송 완료` 목록의 남색 원 + 흰 이니셜이 기준이다. 예전에는
/// 그 자리만 이 위젯을 쓰고 나머지 탭(고객 관리·메시지·스케줄·프로그램·
/// 대시보드·검색 등)은 공용 [AppAvatar] 의 옅은 하늘색 채움 + 남색 글씨를
/// 써서, 같은 회원의 원이 탭마다 다른 색으로 보였다. 회원 원은 전부 이
/// 위젯을 거치고, 트레이너 본인 원(사이드바·MY)만 [AppAvatar] 로 남긴다.
///
/// 크기는 [AppAvatarSize] 를 그대로 받아 옮겨 쓰기 쉽게 한다. [name] 이
/// 한 글자(`TrainerClient.avatar`)면 그대로, 이름 전체면 [AppAvatar] 와
/// 같은 규칙으로 이니셜을 뽑는다. [online] 이면 오른쪽 아래 상태 점을 단다.
class ClientAvatar extends StatelessWidget {
  /// Creates an avatar showing [name]'s initial.
  const ClientAvatar({
    super.key,
    required this.name,
    this.size = AppAvatarSize.medium,
    this.online,
  });

  /// 한 글자 라벨(예: 김) 또는 이름 전체.
  final String name;

  /// 지름 단계.
  final AppAvatarSize size;

  /// null 이면 상태 점을 달지 않는다. true 초록, false 회색.
  final bool? online;

  /// [name] 에서 뽑은 이니셜. 한글은 첫 글자, 로마자 한 단어는 두 글자,
  /// 여러 단어면 첫·끝 단어의 첫 글자다.
  String get initials {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return (parts.first.characters.first + parts.last.characters.first)
          .toUpperCase();
    }
    return trimmed.characters
        .take(trimmed.runes.every((r) => r < 128) ? 2 : 1)
        .toString()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final double d = size.dimension;
    final Widget circle = Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: clientAvatarColors,
        ),
      ),
      child: Text(
        initials,
        // 이니셜은 지름에 비례한다 — 굵기·서체는 역할에서, 크기만 지름에서.
        style: OnCareTypography.titleSmall.copyWith(
          color: OnCareColors.textOnFill,
          fontSize: d * _kInitialFactor,
        ),
      ),
    );

    final bool? status = online;
    final double dot = d * 0.25;
    return Semantics(
      label: name,
      image: true,
      child: status == null
          ? circle
          : SizedBox(
              width: d,
              height: d,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  circle,
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status
                            ? OnCareColors.success
                            : OnCareColors.textDisabled,
                        border: Border.all(
                          color: OnCareColors.surfaceCard,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
