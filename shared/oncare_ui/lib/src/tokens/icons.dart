import 'package:flutter/material.dart';

/// 특정 아이콘 하나만 굵기를 따로 두는 예외(#1803).
@immutable
class OnCareIconWeight {
  const OnCareIconWeight(this.icon, this.weight);

  final IconData icon;

  /// 가변 글꼴 `wght` 축 값(100~700).
  final double weight;
}

/// 공용 컴포넌트가 그리는 아이콘 묶음과 그 글꼴 변형(#1803).
///
/// 브랜드·밀도 다음으로 앱이 테마에 넣을 수 있는 값이다. 트레이너웹은 기본값
/// [material](지금의 Material Icons `_rounded`, 변형 없음)을 그대로 쓰고, 회원앱은
/// 자기 아이콘 목록에서 만든 Material Symbols 묶음을 넣는다. 이 패키지는 아이콘
/// 글꼴 패키지에 기대지 않는다 — 트레이너웹의 의존성·번들이 달라지지 않게 하기
/// 위해서다.
///
/// 컴포넌트는 앱 이름으로 분기하지 않고 뜻(뒤로·닫기·빈 화면 …)으로만 고른다.
@immutable
class OnCareIconSet {
  const OnCareIconSet({
    required this.name,
    required this.back,
    required this.close,
    required this.previous,
    required this.next,
    required this.disclosure,
    required this.dropdown,
    required this.calendarExpand,
    required this.calendarCollapse,
    required this.search,
    required this.add,
    required this.remove,
    required this.check,
    required this.info,
    required this.success,
    required this.caution,
    required this.error,
    required this.empty,
    required this.offline,
    required this.image,
    required this.attachImage,
    required this.send,
    required this.file,
    required this.reward,
    this.timeInput,
    this.timeDial,
    this.fill,
    this.weight,
    this.grade,
    this.minOpticalSize,
    this.maxOpticalSize,
    this.weightOverrides = const <OnCareIconWeight>[],
  });

  /// 기본 묶음 — Material Icons `_rounded`. 글꼴 변형을 싣지 않아 [Icon] 과 똑같이
  /// 그린다.
  static const OnCareIconSet material = OnCareIconSet(
    name: 'material',
    back: Icons.chevron_left_rounded,
    close: Icons.close_rounded,
    previous: Icons.chevron_left_rounded,
    next: Icons.chevron_right_rounded,
    disclosure: Icons.chevron_right_rounded,
    dropdown: Icons.keyboard_arrow_down_rounded,
    calendarExpand: Icons.arrow_drop_down_rounded,
    calendarCollapse: Icons.arrow_drop_up_rounded,
    search: Icons.search_rounded,
    add: Icons.add_rounded,
    remove: Icons.remove_rounded,
    check: Icons.check_rounded,
    info: Icons.info_rounded,
    success: Icons.check_circle_rounded,
    caution: Icons.warning_rounded,
    error: Icons.error_rounded,
    empty: Icons.inbox_rounded,
    offline: Icons.cloud_off_rounded,
    image: Icons.image_rounded,
    attachImage: Icons.add_photo_alternate_rounded,
    send: Icons.send_rounded,
    file: Icons.picture_as_pdf_rounded,
    reward: Icons.star_rounded,
  );

  /// 디버그·카탈로그 표시용 이름.
  final String name;

  /// 뒤로가기([AppBackButton]).
  final IconData back;

  /// 닫기([AppCloseButton])·검색어 지우기.
  final IconData close;

  /// 달력 이전·다음 이동.
  final IconData previous;
  final IconData next;

  /// 섹션 제목의 `더 보기` 꺾쇠.
  final IconData disclosure;

  /// 선택 입력의 펼침 화살표.
  final IconData dropdown;

  /// 날짜 선택창 머리의 삼각형 — 달 보기 열기(▾)·닫기(▴).
  final IconData calendarExpand;
  final IconData calendarCollapse;

  final IconData search;

  /// 하단 내비 `+`·수량 늘리기.
  final IconData add;

  /// 수량 줄이기.
  final IconData remove;

  /// 메뉴에서 고른 항목 표시.
  final IconData check;

  /// 안내 배너·토스트 톤.
  final IconData info;
  final IconData success;
  final IconData caution;
  final IconData error;

  /// 빈 화면 기본 아이콘.
  final IconData empty;

  /// 불러오기 실패 화면.
  final IconData offline;

  /// 이미지 자리 표시.
  final IconData image;

  /// 채팅 사진 첨부.
  final IconData attachImage;

  /// 채팅 전송.
  final IconData send;

  /// 채팅 첨부 파일 카드.
  final IconData file;

  /// 토스트에 붙는 적립 표시(`+50P`)의 별.
  final IconData reward;

  /// 시각 선택기의 입력 모드 전환(키보드·시계). 비우면 Flutter 기본 아이콘이다.
  final IconData? timeInput;
  final IconData? timeDial;

  /// 가변 글꼴 축 값. 비우면 싣지 않는다 — 가변 글꼴이 아닌 Material Icons 는 비워 둔다.
  final double? fill;
  final double? weight;
  final double? grade;

  /// 광학 크기(`opsz`) 범위. 둘 다 있으면 그리는 크기를 이 범위로 잘라 쓴다.
  final double? minOpticalSize;
  final double? maxOpticalSize;

  /// [weight] 와 다른 굵기로 그릴 아이콘.
  final List<OnCareIconWeight> weightOverrides;

  /// [icon] 을 그릴 굵기.
  double? weightOf(IconData? icon) {
    for (final OnCareIconWeight override in weightOverrides) {
      if (override.icon == icon) return override.weight;
    }
    return weight;
  }

  /// [size] 로 그릴 때의 광학 크기. 범위가 없으면 `null` 이다.
  double? opticalSizeFor(double? size) {
    final double? min = minOpticalSize;
    final double? max = maxOpticalSize;
    if (size == null || min == null || max == null) return null;
    return size.clamp(min, max);
  }

  /// [size] 로 그릴 [icon] 의 가변 글꼴 축 값. [Icon] 이 스스로 만드는 것과 같은
  /// 목록이라, 캔버스에 글자로 직접 찍어도 위젯으로 그린 것과 모양이 같다.
  /// 축을 비워 둔 묶음(Material Icons)에서는 빈 목록이다.
  List<FontVariation> fontVariationsFor(IconData? icon, double? size) {
    final double? weight = weightOf(icon);
    final double? opticalSize = opticalSizeFor(size);
    return <FontVariation>[
      if (fill != null) FontVariation('FILL', fill!),
      if (weight != null) FontVariation('wght', weight),
      if (grade != null) FontVariation('GRAD', grade!),
      if (opticalSize != null) FontVariation('opsz', opticalSize),
    ];
  }

  @override
  String toString() => 'OnCareIconSet.$name';
}
