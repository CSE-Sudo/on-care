import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';

/// 가이드가 짚을 자리들의 열쇠. (#1857)
///
/// 스포트라이트는 "지금 짚는 요소가 화면 어디에 있는가" 를 알아야 구멍을 뚫는다.
/// 화면들이 각자 자기 요소에 이 열쇠를 달아 두면, 덮개는 열쇠로 자리를 읽는다.
///
/// 전역 상수가 아니라 provider 로 둔다 — 같은 열쇠를 두 화면이 동시에 달면
/// Flutter 가 중복으로 보고 화면이 죽는다. 테스트가 앱을 여러 번 띄울 때가
/// 그런 경우다.
class GuideAnchors {
  GuideAnchors();

  final GlobalKey homeAdvice = GlobalKey(debugLabel: 'guide-home-advice');
  final GlobalKey quickAdd = GlobalKey(debugLabel: 'guide-quick-add');
  final GlobalKey dietNutrition = GlobalKey(debugLabel: 'guide-diet-nutrition');
  final GlobalKey exerciseStatus = GlobalKey(
    debugLabel: 'guide-exercise-status',
  );
  final GlobalKey gym = GlobalKey(debugLabel: 'guide-gym');
  final GlobalKey mySettings = GlobalKey(debugLabel: 'guide-my-settings');
  final GlobalKey points = GlobalKey(debugLabel: 'guide-points');

  GlobalKey keyOf(GuideStepId id) => switch (id) {
    GuideStepId.homeAdvice => homeAdvice,
    GuideStepId.quickAdd => quickAdd,
    GuideStepId.dietNutrition => dietNutrition,
    GuideStepId.exerciseStatus => exerciseStatus,
    GuideStepId.gym => gym,
    GuideStepId.mySettings => mySettings,
    GuideStepId.points => points,
  };
}

final guideAnchorsProvider = Provider<GuideAnchors>(
  (ref) => GuideAnchors(),
  name: 'guideAnchors',
);

/// 지금 가이드가 켜져 있는지와 몇 번째 자리를 짚는지.
@immutable
class AppGuideState {
  const AppGuideState({this.active = false, this.index = 0});

  final bool active;
  final int index;

  /// 지금 짚는 자리. 꺼져 있으면 null.
  GuideStepId? get step =>
      active && index < kGuideSteps.length ? kGuideSteps[index] : null;

  /// 지금 머무는 탭. 가이드는 탭을 옮겨 가며 그 화면 위에서 짚는다.
  GuideTab get tab {
    final GuideStepId? current = step;
    return current == null ? GuideTab.home : guideTabOf(current);
  }

  /// 사람에게 보여 주는 번호(1부터).
  int get stepNumber => index + 1;

  int get totalSteps => kGuideSteps.length;

  bool get isFirst => index == 0;

  bool get isLast => index == kGuideSteps.length - 1;

  AppGuideState copyWith({bool? active, int? index}) =>
      AppGuideState(active: active ?? this.active, index: index ?? this.index);
}

/// 첫 홈 진입 가이드의 진행. (#1857)
///
/// 한 번 본 회원에게는 다시 뜨지 않는다 — 끝까지 봤든 건너뛰었든 같다. 그
/// 기억은 기기에 남는다(로그인 계정이 아니라 기기 설정이라, 앱을 지우면 다시
/// 볼 수 있다).
class AppGuideController extends Notifier<AppGuideState> {
  @override
  AppGuideState build() => const AppGuideState();

  /// 가이드 화면이 열리면 부른다 — 온보딩을 마치거나 건너뛴 뒤, 또는 MY 의
  /// `앱 사용 가이드` 에서. 이미 본 회원이면 아무 일도 하지 않는다.
  void start() {
    if (_prefs?.homeGuideDone ?? false) return;
    state = const AppGuideState(active: true);
  }

  void next() {
    if (!state.active) return;
    if (state.isLast) {
      finish();
      return;
    }
    state = state.copyWith(index: state.index + 1);
  }

  /// 방금 지나친 자리를 다시 본다. 첫 자리에서는 할 일이 없다 — 가이드를 여기서
  /// 끝내 버리면 `이전` 이 `건너뛰기` 처럼 동작하게 된다.
  void previous() {
    if (!state.active || state.isFirst) return;
    state = state.copyWith(index: state.index - 1);
  }

  /// 작은 `건너뛰기` — 남은 자리를 보지 않고 끝낸다. 끝까지 본 것과 같이
  /// 다시 뜨지 않는다. 안 그러면 건너뛴 사람은 열 때마다 같은 덮개를 만난다.
  void skip() => finish();

  void finish() {
    state = const AppGuideState();
    _prefs?.setHomeGuideDone(true);
  }

  /// 새 계정으로 가입했으니 가이드를 다시 보여 준다(#1857).
  ///
  /// 본 기억은 기기에 남는다 — 계정이 아니라. 한 기기에서 두 번째 계정을 만들면
  /// 첫 계정이 본 기억 때문에 **가입했는데 가이드가 없는** 일이 생긴다. 가입은
  /// 언제나 처음 쓰는 사람이므로, 그 자리에서 기억을 지운다.
  void resetSeen() {
    state = const AppGuideState();
    _prefs?.setHomeGuideDone(false);
  }

  /// 설정 저장소가 없는 자리(일부 테스트)에서도 가이드는 떠야 한다 — 그때는
  /// "아직 안 봤다" 로 보고, 본 기억만 남기지 않는다.
  AppPrefs? get _prefs {
    try {
      return ref.read(appPrefsProvider);
    } on Object {
      return null;
    }
  }
}

final appGuideControllerProvider =
    NotifierProvider<AppGuideController, AppGuideState>(
      AppGuideController.new,
      name: 'appGuide',
    );
