import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/exercise_goals_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `운동 현황` 의 기본 기간 — 0 = 오늘, 1 = 이번 주, 2 = 전체.
const int kExerciseActivityPeriodDefault = 0;

/// 오늘/이번 주/전체 토글. 탭을 벗어났다 들어오면 기본값으로 돌아가야 하는
/// 임시 UI 상태라 Riverpod 에 둔다(#861).
final exerciseActivityPeriodProvider = StateProvider<int>(
  (ref) => kExerciseActivityPeriodDefault,
  name: 'exerciseActivityPeriod',
);

/// 기간 토글의 칸(0·1·2) → 서버가 아는 기간 이름. 식단 탭과 같은 말을 쓴다
/// (`today`·`week`·`all`). 토글이 정수인 것은 화면 사정이고, 서버·조언이 아는
/// 것은 이름이다 — 그 사이를 여기 한 곳에서만 옮긴다. (#1574)
String exerciseAdvicePeriod(int tab) => switch (tab) {
  1 => kPeriodWeek,
  2 => kPeriodAll,
  _ => kPeriodToday,
};

/// 세 기간 카드의 **공통 높이**. 토글을 눌러도 카드가 커졌다 작아졌다 하지
/// 않도록 셋을 같은 높이로 고정한다.
const double kActivityCardHeight = 218;

// ── 차트 고유 치수 ─────────────────────────────────────────────────────

/// 글자 배율을 따라 카드·머리줄이 커지다 멈추는 상한.
const double _kMaxLayoutScale = 1.6;

/// 도넛·링 지름의 하한·상한과, 그 옆 유형별 값 목록에 남기는 폭.
const double _kRingMinSize = 96;
const double _kRingMaxSize = 150;
const double _kRingDetailReserve = 170;

/// 오늘 카드에서 유형별 값 목록이 차지하는 폭.
const double _kDayDetailWidth = 150;

/// 도넛 두께(지름 대비).
const double _kDonutStrokeFactor = 0.13;

/// 세 링 사이 틈과 가운데 구멍(반지름 대비).
const double _kRingGap = 3;
const double _kRingHoleFactor = 0.22;

/// 원호 끝 그림자 — 넓고 흐린 것과 좁고 진한 것의 퍼짐·흐림·진하기.
const double _kCapShadowOuterSpread = 4;
const double _kCapShadowOuterBlur = 12;
const double _kCapShadowOuterAlpha = 0.75;
const double _kCapShadowInnerSpread = 1;
const double _kCapShadowInnerBlur = 5;
const double _kCapShadowInnerAlpha = 0.65;

/// `전체` 그래프 — 한 주가 차지하는 가로, 막대 두께, 막대 최소 높이, 기록
/// 없는 주의 그루터기 높이, 고르지 않은 막대의 흐림.
const double _kWeekSlot = 26;
const double _kBurnBarWidth = 12;
const double _kBurnBarMinHeight = 3;
const double _kBurnStubHeight = 4;
const double _kDimmedBarOpacity = 0.35;

/// 패키지 [PeriodScrollChart] 가 막대 아래에 두는 축 라벨 줄의 높이(간격 포함).
const double _kAxisLabelExtent = OnCareSpacing.s8 + 16;

/// 그래프 목표 위 여유(최고값 대비).
const double _kChartHeadroom = 1.12;

/// 달 경계 파선의 한 칸과 주기.
const double _kGridDash = 3;
const double _kGridDashStep = 6;

/// `전체` 카드 머리줄의 글자 배율 1 기준 높이.
const double _kAllPeriodHeaderHeight = 44;

// ── 유형별 색·라벨·단위 ────────────────────────────────────────────────

/// 유형별 색 (#1152). 유산소 → 근력 → 스트레칭으로 **한 계열 안에서 점점
/// 연해진다** — 셋이 같은 축(운동 유형)이라 색상까지 흩어 놓으면 서로 무관한
/// 지표처럼 읽힌다. 진하기가 곧 순서다.
///
/// 값은 브랜드 토큰(`exerciseCardio/Strength/Stretching`)이다. 화면에서는
/// `context.oncare.brand` 를 넘기고, 넘기지 않으면 회원앱 브랜드를 쓴다.
///
/// 소모 칼로리([kBurnColor])는 이 램프보다 한 단계 더 진하다 — 유형이 아니라
/// 셋이 함께 만든 결과라, 램프의 어느 단계와도 겹치면 안 된다.
Color kindColor(
  ExerciseLoadKind kind, [
  OnCareBrand brand = OnCareBrand.member,
]) => switch (kind) {
  ExerciseLoadKind.cardio => brand.exerciseCardio,
  ExerciseLoadKind.strength => brand.exerciseStrength,
  ExerciseLoadKind.flexibility => brand.exerciseStretching,
};

String kindLabel(AppLocalizations l, ExerciseLoadKind kind) => switch (kind) {
  ExerciseLoadKind.cardio => l.exTypeCardio,
  ExerciseLoadKind.strength => l.exTypeStrength,
  ExerciseLoadKind.flexibility => l.exTypeFlexibility,
};

/// 유형의 **원래 단위**로 읽는다 — 유산소·스트레칭은 분, 근력은 세트.
String kindValueText(AppLocalizations l, ExerciseLoadKind kind, double v) =>
    switch (kind) {
      ExerciseLoadKind.cardio ||
      ExerciseLoadKind.flexibility => l.unitMinutesValue(v.round()),
      ExerciseLoadKind.strength => l.exProgramSets(v.round()),
    };

/// 소모 칼로리 색. 유산소·근력·스트레칭 세 유형과 **다른 색**이어야 한다
/// (#1127) — 도넛과 링이 재는 것은 유형이 아니라 그 셋이 함께 만든 결과다.
/// 유형 램프보다 한 단계 더 진한 브랜드 `strong` 이다. (#1152)
final Color kBurnColor = OnCareBrand.member.strong;

/// 화면에서 쓰는 소모 칼로리 색 — 테마 브랜드의 `strong`.
Color _burnColor(BuildContext context) => context.oncare.brand.strong;

DateTime _thisMonday() {
  final DateTime n = nowKst();
  final DateTime d = DateTime(n.year, n.month, n.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

DateTime _today() {
  final DateTime n = nowKst();
  return DateTime(n.year, n.month, n.day);
}

/// 글자 배율을 따라 커지되 [_kMaxLayoutScale] 에서 멈추는 배수.
double _layoutScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, _kMaxLayoutScale);

/// `397/500` — 값과 목표를 한 덩어리로. 목표를 따로 떼어 적으면 머리 줄이
/// 길어져 카드 폭을 다 먹는다.
String _valueOfGoal(String locale, double value, double goal) {
  final NumberFormat nf = NumberFormat.decimalPattern(locale);
  return '${nf.format(value.round())}/${nf.format(goal.round())}';
}

/// 원호의 **끝(캡)** 아래에 깔 그림자. 넓고 흐린 것 위에 좁고 진한 것을 겹쳐
/// 찍어, 끝이 아래 트랙(또는 한 바퀴 돈 같은 색 원)에 묻히지 않게 한다.
///
/// 그리기 전에 캔버스를 **그 링의 두께**로 자른다 — 자르지 않으면 흐린 가장자리가
/// 링 밖으로 번져 도넛 주위에 얼룩이 남는다.
void _paintCapShadow(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double capAngle,
) {
  final Path ring = Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: center, radius: radius + stroke / 2))
    ..addOval(Rect.fromCircle(center: center, radius: radius - stroke / 2));
  final Offset cap =
      center + Offset(math.cos(capAngle), math.sin(capAngle)) * radius;
  canvas
    ..save()
    ..clipPath(ring)
    // 두 겹으로 깐다. 넓고 흐린 것이 링 위에 얹힌 느낌을 만들고, 좁고 진한
    // 것이 끝의 위치를 못 박는다. 링을 따라온 끝이 어디인지는 이 그림자만으로
    // 읽혀야 하므로, 가장 연한 링(스트레칭) 위에서도 보이도록 진하고 넓게 둔다.
    ..drawCircle(
      cap,
      stroke / 2 + _kCapShadowOuterSpread,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          OnCareColors.overlayInk,
          _kCapShadowOuterAlpha,
        )!
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _kCapShadowOuterBlur,
        ),
    )
    ..drawCircle(
      cap,
      stroke / 2 + _kCapShadowInnerSpread,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          OnCareColors.overlayInk,
          _kCapShadowInnerAlpha,
        )!
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _kCapShadowInnerBlur,
        ),
    )
    ..restore();
}

/// 그 달의 몇 번째 주인지 — `8월 1주차` 의 1.
int _weekOfMonth(DateTime monday) => ((monday.day - 1) ~/ 7) + 1;

/// 운동 현황 — 오늘 / 이번 주 / 전체.
///
/// 세 화면이 보는 축은 **소모 칼로리**다. 유산소는 분, 근력은 세트, 스트레칭은
/// 분으로 재는 값이라 서로 더할 수 없는데, 칼로리는 셋이 함께 만든 하나의
/// 결과라서 도넛과 막대의 높이로 쓸 수 있다. 유형별 값은 언제나 **제 단위**로
/// 따로 적는다.
class ExerciseActivityStatus extends ConsumerStatefulWidget {
  const ExerciseActivityStatus({required this.week, super.key});

  /// 오늘 체크한 AI 루틴까지 반영된 이번 주 기록(`exerciseWeekViewProvider`).
  final ExerciseWeek week;

  @override
  ConsumerState<ExerciseActivityStatus> createState() =>
      _ExerciseActivityStatusState();
}

class _ExerciseActivityStatusState
    extends ConsumerState<ExerciseActivityStatus> {
  /// MY 건강 목표에서 저장한 값. 저장한 적이 없으면 권장값이다 (#1139).
  ExerciseLoadGoals get _goals => ref.watch(exerciseLoadGoalsProvider);

  List<ExerciseDayLoad> get _loads =>
      dayLoadsOfWeek(widget.week, _thisMonday());

  ExerciseDayLoad get _todayLoad {
    final DateTime d = _today();
    return _loads.firstWhere(
      (ExerciseDayLoad e) => e.date == d,
      orElse: () => ExerciseDayLoad(date: d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int period = ref.watch(exerciseActivityPeriodProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 제목과 기간 토글은 한 줄에. 식단 탭 `영양 요약` 과 같은 자리다.
        Row(
          key: const ValueKey<String>('exercise-section-header'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: OnCareSpacing.s8,
                ),
                child: AppSectionHeader(
                  // 하단 탭의 운동 아이콘과 같은 것을 쓴다 (#1126) — 이 화면이
                  // 어느 탭의 것인지 제목 줄에서 바로 읽힌다.
                  icon: AppIcons.exercise,
                  title: l.exActivityTitle,
                ),
              ),
            ),
            Flexible(
              flex: 2,
              child: FittedBox(
                // 세 라벨은 줄이지 않는다 — `이번 주` 가 `이번…` 으로 잘려 무엇을
                // 고르는 자리인지 사라졌다 (#1182). 폭이 모자라면 토글을 통째로
                // 줄인다.
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AppSegmentedToggle<int>(
                  key: const ValueKey<String>('exercise-period-toggle'),
                  segments: <AppSegment<int>>[
                    AppSegment<int>(value: 0, label: l.exToday),
                    AppSegment<int>(value: 1, label: l.exThisWeek),
                    AppSegment<int>(value: 2, label: l.exPeriodAll),
                  ],
                  selected: period,
                  onChanged: (int i) =>
                      ref.read(exerciseActivityPeriodProvider.notifier).state =
                          i,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (period == 0)
          ExerciseDayLoadCard(
            load: _todayLoad,
            goals: _goals,
            streakDays: widget.week.streakDays,
          )
        else if (period == 1)
          ExerciseWeekLoadCard(loads: _loads, goals: _goals)
        else
          _AllPeriodView(goals: _goals),
      ],
    );
  }
}

// ── 오늘 ──────────────────────────────────────────────────────────────

/// 오늘 = **소모 칼로리 도넛 하나** + 유형별로 얼마나 했는지 적은 줄.
///
/// 유형마다 목표를 세워 링 셋을 겹치던 때보다 읽을 것이 적다. 오늘 답해야 할
/// 질문은 "얼마나 태웠나" 하나이고, 유산소 몇 분·근력 몇 세트는 그 숫자의
/// 내역이라 글자로 충분하다.
class ExerciseDayLoadCard extends StatelessWidget {
  const ExerciseDayLoadCard({
    required this.load,
    this.goals = kDefaultExerciseLoadGoals,
    this.isToday = true,
    this.streakDays,
    super.key,
  });

  final ExerciseDayLoad load;
  final ExerciseLoadGoals goals;

  /// 지난 날짜 상세에서도 같은 카드를 쓴다.
  final bool isToday;

  /// 며칠 연속 운동 중인지. **오늘 카드에만** 있다. null 이면 그리지 않는다.
  final int? streakDays;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final int? streak = streakDays;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (streak != null) ...<Widget>[
            _StreakLine(days: streak),
            const SizedBox(height: OnCareSpacing.s4),
          ],
          // 소모 칼로리는 도넛 **안에서** 말한다 (#1127) — 링 옆에 같은 숫자를
          // 또 적으면 한 화면에서 같은 말이 두 번 나온다.
          //
          // 도넛은 **왼쪽**, 유형별 값은 오른쪽이다 (#1151). 라벨과 값은 폭을
          // 묶어 서로 멀어지지 않게 한다.
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double donut = math.min(
                  c.maxHeight,
                  (c.maxWidth - _kRingDetailReserve).clamp(
                    _kRingMinSize,
                    _kRingMaxSize,
                  ),
                );
                return Row(
                  // 도넛과 상세를 한 덩어리로 **카드 가운데**에 세운다.
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _BurnDonut(
                      calories: load.calories,
                      goal: goals.dailyBurnKcal,
                      size: donut,
                      locale: locale,
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    // 상세는 폭을 못 박아 줄들이 서로 붙어 읽힌다. 자리가
                    // 모자라면(좁은 화면·큰 글자) `Flexible` 이 그만큼 줄여 준다.
                    Flexible(
                      child: SizedBox(
                        width: _kDayDetailWidth,
                        child: Center(
                          // 좁아지면 목록을 **한 번에** 줄인다 (#1170). 폭은
                          // 가장 긴 줄에 맞춘다 (#1173).
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: IntrinsicWidth(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                // 세 줄이 같은 너비로 서야 값의 오른쪽 끝이
                                // 가지런하다. (#1173)
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  for (final ExerciseLoadKind k
                                      in ExerciseLoadKind.values)
                                    _KindTextRow(
                                      label: kindLabel(l, k),
                                      value: kindValueText(
                                        l,
                                        k,
                                        load.valueOf(k),
                                      ),
                                    ),
                                  // 세 유형은 0 이어도 줄로 남는다. `기타` 는
                                  // **한 날에만** 맨 아래 회색 한 줄로 붙는다
                                  // (#1352).
                                  if (load.otherMinutes > 0)
                                    _KindTextRow(
                                      label: l.exTypeOtherChip,
                                      value: l.unitMinutesValue(
                                        load.otherMinutes.round(),
                                      ),
                                      muted: true,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// `⚡ 5일 연속 운동 중이에요!` — 주의 톤 태그.
class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 카드 안의 다른 글자와 같은 자리에서 시작하지만, 이 한 줄만 주황 태그로
    // 깔아 **응원 문구**임을 표시한다. 불꽃은 소모 칼로리 도넛이 쓰므로 연속은
    // '기세' 쪽 기호로 갈라 둔다. 좁으면 태그째 줄인다.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: AppTag(
          label: days > 0 ? l.exStreakCheer(days) : l.exStreakStart,
          tone: AppTagTone.caution,
          icon: AppIcons.streak,
        ),
      ),
    );
  }
}

/// `▪ 유산소     15분` — 목표 없이 **한 값만** 적는 줄.
class _KindTextRow extends StatelessWidget {
  const _KindTextRow({
    required this.label,
    required this.value,
    this.color,
    this.goal,
    this.muted = false,
  });

  final String label;
  final String value;

  /// 세 유형 아래 덧붙는 `기타` 줄인가. 목표도 색도 없는 값이라 **회색**으로
  /// 한 단계 물려 적는다 (#1352).
  final bool muted;

  /// 색 점. 옆에 같은 색의 링이 있는 화면(이번 주)에서만 준다.
  final Color? color;

  /// `/150분` 처럼 값 뒤에 붙는 목표. 값보다 연하게 적는다.
  final String? goal;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color? c = color;
    final String? g = goal;
    return Padding(
      padding: const EdgeInsets.only(
        bottom: OnCareSpacing.s4,
        left: OnCareSpacing.s8,
        right: OnCareSpacing.s8,
      ),
      child: Row(
        children: <Widget>[
          if (c != null) ...<Widget>[
            AppChartSwatch(color: c),
            const SizedBox(width: OnCareSpacing.s8),
          ],
          // **줄마다 따로 줄이지 않는다** (#1170) — 좁아질 때는 목록 전체가 한
          // 번에 줄어든다. 칸을 `Expanded` 로 나누지도 않는다 (#1173).
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(
                  color: muted
                      ? OnCareColors.textTertiary
                      : OnCareColors.textSecondary,
                ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: value),
                if (g != null)
                  TextSpan(
                    text: g,
                    style: const TextStyle(color: OnCareColors.textSecondary),
                  ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            style: tokens
                .text(OnCareTypography.numeric(OnCareTypography.label))
                .copyWith(
                  color: muted
                      ? OnCareColors.textTertiary
                      : OnCareColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

/// 링 12시에 얹는 유형 기호 (#1128).
///
/// 이 링이 무엇인지(소모·유산소·근력·스트레칭)와 어디서 출발했는지를 말한다.
/// 자리를 고정해 두어야 링끼리 견줄 수 있다 — 어디까지 왔는지는 원호 끝의
/// 그림자가 짚는다.
const IconData _kBurnStartIcon = AppIcons.calories;

IconData ringStartIcon(ExerciseLoadKind kind) => switch (kind) {
  ExerciseLoadKind.cardio => AppIcons.running,
  ExerciseLoadKind.strength => AppIcons.strength,
  ExerciseLoadKind.flexibility => AppIcons.flexibility,
};

/// 링 위 [angle] 자리에 기호를 얹는다. 기본값은 12시(원호의 시작)다.
void paintRingCapIcon(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double stroke,
  required IconData icon,
  double angle = -math.pi / 2,
}) {
  final double glyph = stroke * 0.78;
  if (glyph < 6) return;
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: glyph,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: OnCareColors.textOnFill,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final Offset at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
  tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
}

/// 한 바퀴를 넘긴 원호가 **다시 도는 몫**(0 이상 1 미만).
///
/// 넘친 몫을 1 에서 자르면 두 바퀴를 넘긴 순간(209%, 300% …) 끝이 12시로
/// 되돌아가, 그 자리에 고정으로 얹는 유형 기호 아래 캡 표시가 숨는다 —
/// 자르지 말고 **바퀴마다 감아 돌린다** (#1178).
double ringOverflowTurn(double ratio) {
  if (!ratio.isFinite) return 0;
  return ratio - ratio.floorToDouble();
}

/// 부동소수점 오차를 감안한 허용 오차 (#1462).
const double _kRingMultipleEpsilon = 1e-6;

/// [filled] 가 목표의 정확한 양의 정수 배(1, 2, 3 …)에 아주 가까운가.
///
/// 이 자리에서는 원호 끝이 12시의 고정 시작 기호와 겹친다 — 캡 그림자와
/// 진행 끝 `>` 기호를 여기 또 그리면 검은 얼룩과 아이콘 중복으로 보인다
/// (#1462). 0(아직 시작 전)은 배수로 치지 않는다.
bool isAtRingMultiple(double filled) {
  if (!filled.isFinite || filled < 1 - _kRingMultipleEpsilon) return false;
  final double nearest = filled.roundToDouble();
  return nearest >= 1 && (filled - nearest).abs() <= _kRingMultipleEpsilon;
}

/// 원호의 **끝**에 얹는 얇고 작은 흰 `>`. 어디까지 왔는지와 어느 쪽으로 도는지를
/// 함께 짚는다. 링이 너무 얇으면 기호가 링을 다 덮으므로 그리지 않는다.
void paintRingCapChevron(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double stroke,
  required double angle,
}) {
  final double arm = stroke * 0.16;
  if (arm < 1.4) return;
  final Offset at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    // 접선 방향으로 눕힌다 — 시계 방향으로 도는 원호에서는 각도 + 90도다.
    ..rotate(angle + math.pi / 2)
    ..drawPath(
      Path()
        ..moveTo(-arm * 0.55, -arm)
        ..lineTo(arm * 0.55, 0)
        ..lineTo(-arm * 0.55, arm),
      Paint()
        ..color = OnCareColors.textOnFill
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(stroke * 0.07, 1)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    )
    ..restore();
}

/// 소모 칼로리 도넛 하나. 목표를 넘기면 **한 바퀴를 넘어 계속 돈다**.
class _BurnDonut extends StatelessWidget {
  const _BurnDonut({
    required this.calories,
    required this.goal,
    required this.size,
    required this.locale,
  });

  final double calories;
  final double goal;
  final double size;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double ratio = goal <= 0 ? 0 : calories / goal;
    final Color color = _burnColor(context);
    return Semantics(
      label:
          '${l.exBurnTodayTitle} ${l.unitKcalValue(calories.round())}, '
          '${l.exGoalValue(l.unitKcalValue(goal.round()))}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: ChartReveal(
            curve: Curves.linear,
            replayKey: calories,
            builder: (BuildContext context, double t) => CustomPaint(
              painter: _DonutPainter(
                ratio: ratio,
                t: t,
                color: color,
                // 홈 운동 카드가 쓰는 것과 같은 말이다.
                caption: l.homeExerciseBurned,
                center: NumberFormat.decimalPattern(
                  locale,
                ).format(calories.round()),
                // 도넛 안에서 `411` 아래 `/300kcal` 로 읽힌다 (#1127).
                unit:
                    '/${NumberFormat.decimalPattern(locale).format(goal.round())}'
                    '${l.unitKcal}',
                startIcon: _kBurnStartIcon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.ratio,
    required this.t,
    required this.color,
    required this.center,
    required this.unit,
    this.caption = '',
    this.startIcon,
  });

  final double ratio;
  final double t;
  final Color color;

  /// 값 **위**에 얹는 회색 머리 — 이 링이 무엇을 재는지 (#1352).
  final String caption;

  final String center;
  final String unit;

  /// 12시 방향 링 머리에 얹을 기호. null 이면 그리지 않는다. (#1128)
  final IconData? startIcon;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double stroke = size.width * _kDonutStrokeFactor;
    final double r = size.width / 2 - stroke / 2;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = OnCareColors.onWhite(color, OnCareAlpha.medium),
    );
    final double filled = ratio * t;
    // 기호가 설 자리 = 원호의 끝. 아직 시작 전(0)이면 12시다.
    double capAngle = -math.pi / 2;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    // 정확한 목표 배수(100%, 200% …)에서는 캡 그림자와 끝 기호를 그리지
    // 않는다 (#1462).
    final bool atMultiple = isAtRingMultiple(filled);
    if (filled >= 1 - _kRingMultipleEpsilon) {
      // 한 바퀴는 **끝이 없는 원**으로.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = color,
      );
      final double over = atMultiple ? 0 : ringOverflowTurn(filled);
      capAngle = -math.pi / 2 + math.pi * 2 * over;
      if (!atMultiple) {
        _paintCapShadow(canvas, c, r, stroke, capAngle);
        if (over > 0) {
          canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * over, false, arc);
        }
      }
    } else if (filled > 0) {
      capAngle = -math.pi / 2 + math.pi * 2 * filled;
      _paintCapShadow(canvas, c, r, stroke, capAngle);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * filled, false, arc);
    }
    // 안쪽 구멍의 지름. 세 줄 다 이 폭 안에 들어간다.
    final double inner = (r - stroke / 2) * 1.75;
    // 머리 → 값 → 목표 순으로 쌓아 **구멍 한가운데**에 세운다 (#1352).
    final TextStyle minor = OnCareTypography.strong(OnCareTypography.caption);
    _paintCenteredLines(canvas, c, <TextPainter>[
      if (caption.isNotEmpty)
        _layout(
          caption,
          size.width * 0.085,
          minor,
          OnCareColors.textTertiary,
          maxWidth: inner,
        ),
      _layout(
        center,
        size.width * 0.2,
        OnCareTypography.numeric(OnCareTypography.display),
        OnCareColors.textPrimary,
        maxWidth: inner,
      ),
      _layout(
        unit,
        size.width * 0.105,
        minor,
        OnCareColors.textTertiary,
        maxWidth: inner,
      ),
    ], gap: size.width * 0.012);
    // 끝에 얇은 `>` 를 얹는다. 정확한 목표 배수에서는 그리지 않는다 (#1462).
    if (filled > 0 && !atMultiple) {
      paintRingCapChevron(
        canvas,
        center: c,
        radius: r,
        stroke: stroke,
        angle: capAngle,
      );
    }
    // 유형 기호는 12시에 고정한다.
    final IconData? icon = startIcon;
    if (icon != null) {
      paintRingCapIcon(
        canvas,
        center: c,
        radius: r,
        stroke: stroke,
        icon: icon,
      );
    }
  }

  TextPainter _layout(
    String s,
    double size,
    TextStyle role,
    Color color, {
    double? maxWidth,
  }) {
    // 캔버스에 직접 그리는 글자는 테마를 타지 않는다 — 역할 스타일(앱 폰트
    // 포함)을 손으로 붙여 준다. 기본 폰트로 떨어지면 웹에서 두부(□)로 나온다
    // (#1352). 크기는 도넛 지름을 따른다.
    TextPainter at(double fontSize) => TextPainter(
      text: TextSpan(
        text: s,
        style: role.copyWith(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final TextPainter tp = at(size);
    // 도넛 **안**에 들어가야 한다. 넘치면 그만큼 글자를 줄인다. (#1127)
    if (maxWidth != null && tp.width > maxWidth) {
      return at(size * (maxWidth / tp.width));
    }
    return tp;
  }

  /// [lines] 를 [center] 기준으로 가로·세로 모두 가운데에 쌓아 그린다.
  void _paintCenteredLines(
    Canvas canvas,
    Offset center,
    List<TextPainter> lines, {
    required double gap,
  }) {
    if (lines.isEmpty) return;
    final double total =
        lines.fold<double>(0, (double a, TextPainter tp) => a + tp.height) +
        gap * (lines.length - 1);
    double y = center.dy - total / 2;
    for (final TextPainter tp in lines) {
      tp.paint(canvas, Offset(center.dx - tp.width / 2, y));
      y += tp.height + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.t != t ||
      old.ratio != ratio ||
      old.color != color ||
      old.center != center ||
      old.unit != unit ||
      old.caption != caption;
}

// ── 이번 주 ────────────────────────────────────────────────────────────

/// 이번 주 = **주간 소모 칼로리 한 줄** + 유형별 목표 링 셋 + 그 값.
///
/// 홈 탭 운동 카드도 이 카드를 그대로 쓴다 (#1183) — 같은 한 주를 두 화면이
/// 다른 그림으로 말하지 않게, 오늘 카드([ExerciseDayLoadCard])와 같은 방식으로
/// 공개해 둔다.
class ExerciseWeekLoadCard extends StatelessWidget {
  const ExerciseWeekLoadCard({
    required this.loads,
    this.goals = kDefaultExerciseLoadGoals,
    this.surface = true,
    super.key,
  });

  final List<ExerciseDayLoad> loads;
  final ExerciseLoadGoals goals;

  /// 흰 카드 바탕을 직접 그릴지. 홈처럼 **이미 카드 안**에 놓일 때는 끈다.
  final bool surface;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final OnCareBrand brand = context.oncare.brand;
    if (loads.isEmpty) {
      return _Card(
        surface: surface,
        child: Center(child: _Muted(l.exLoadEmpty)),
      );
    }
    final ExerciseLoadGoals g = goals;
    final double weekKcal = loads.fold<double>(
      0,
      (double a, ExerciseDayLoad d) => a + d.calories,
    );
    return _Card(
      surface: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HeadlineLine(
            caption: l.exBurnWeekTitle,
            value: _valueOfGoal(locale, weekKcal, g.weeklyBurnKcal),
            unit: l.unitKcal,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) => Row(
                children: <Widget>[
                  _GoalRings(
                    loads: loads,
                    goals: g,
                    size: math.min(
                      c.maxHeight,
                      (c.maxWidth - _kRingDetailReserve).clamp(
                        _kRingMinSize,
                        _kRingMaxSize,
                      ),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s16),
                  Expanded(
                    child: Center(
                      // 목록 전체를 **한 번에** 줄인다 (#1170).
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: IntrinsicWidth(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (final ExerciseLoadKind k
                                  in ExerciseLoadKind.values)
                                _KindTextRow(
                                  color: kindColor(k, brand),
                                  label: kindLabel(l, k),
                                  value: '${_sum(loads, k).round()}',
                                  goal:
                                      '/${kindValueText(l, k, g.weeklyGoalOf(k))}',
                                ),
                              // 기타는 목표가 없다 — 한 주에 기록이 있을 때만
                              // 맨 아래 회색 한 줄로 붙는다 (#1352).
                              if (_otherSum(loads) > 0)
                                _KindTextRow(
                                  color: OnCareColors.lineStrong,
                                  label: l.exTypeOtherChip,
                                  value: l.unitMinutesValue(
                                    _otherSum(loads).round(),
                                  ),
                                  muted: true,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _sum(List<ExerciseDayLoad> loads, ExerciseLoadKind k) =>
      loads.fold<double>(0, (double a, ExerciseDayLoad d) => a + d.valueOf(k));

  double _otherSum(List<ExerciseDayLoad> loads) => loads.fold<double>(
    0,
    (double a, ExerciseDayLoad d) => a + d.otherMinutes,
  );
}

/// 크기가 다른 세 링. 바깥부터 유산소 → 근력 → 스트레칭.
class _GoalRings extends StatelessWidget {
  const _GoalRings({
    required this.loads,
    required this.goals,
    required this.size,
  });

  final List<ExerciseDayLoad> loads;
  final ExerciseLoadGoals goals;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareBrand brand = context.oncare.brand;
    final List<double> ratios = <double>[
      for (final ExerciseLoadKind k in ExerciseLoadKind.values)
        () {
          final double goal = goals.weeklyGoalOf(k);
          if (goal <= 0) return 0.0;
          return loads.fold<double>(
                0,
                (double a, ExerciseDayLoad d) => a + d.valueOf(k),
              ) /
              goal;
        }(),
    ];
    return Semantics(
      label: <String>[
        for (int i = 0; i < ExerciseLoadKind.values.length; i++)
          '${kindLabel(l, ExerciseLoadKind.values[i])} ${(ratios[i] * 100).round()}%',
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: ChartReveal(
            curve: Curves.linear,
            replayKey: ratios.join(','),
            builder: (BuildContext context, double t) => CustomPaint(
              painter: _RingsPainter(
                ratios: ratios,
                t: t,
                colors: <Color>[
                  for (final ExerciseLoadKind k in ExerciseLoadKind.values)
                    kindColor(k, brand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.ratios, required this.t, required this.colors});

  final List<double> ratios;
  final double t;

  /// 링마다의 유형 색 — [ratios] 와 같은 순서.
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;
    final double hole = radius * _kRingHoleFactor;
    final double stroke = (radius - _kRingGap * 2 - hole) / 3;
    double r = radius - stroke / 2;
    for (int i = 0; i < ratios.length; i++) {
      final Color color = colors[i];
      final Rect rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = OnCareColors.onWhite(color, OnCareAlpha.medium),
      );
      final double ratio = ratios[i] * chartStagger(t, i, 3);
      // 기호가 설 자리 = 이 링 원호의 끝. 아직 시작 전이면 12시다.
      double capAngle = -math.pi / 2;
      final Paint arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      // 정확한 목표 배수에서는 캡 그림자와 끝 기호를 그리지 않는다(#1462).
      final bool atMultiple = isAtRingMultiple(ratio);
      if (ratio >= 1 - _kRingMultipleEpsilon) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = color,
        );
        final double over = atMultiple ? 0 : ringOverflowTurn(ratio);
        capAngle = -math.pi / 2 + math.pi * 2 * over;
        if (!atMultiple) {
          _paintCapShadow(canvas, c, r, stroke, capAngle);
          if (over > 0) {
            canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * over, false, arc);
          }
        }
      } else if (ratio > 0) {
        capAngle = -math.pi / 2 + math.pi * 2 * ratio;
        _paintCapShadow(canvas, c, r, stroke, capAngle);
        canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * ratio, false, arc);
      }
      // 끝에 얇은 `>` 를 얹는다 — 세 링이 각자 어디까지 왔는지 짚는다.
      if (ratio > 0 && !atMultiple) {
        paintRingCapChevron(
          canvas,
          center: c,
          radius: r,
          stroke: stroke,
          angle: capAngle,
        );
      }
      // 유형 기호는 링마다 12시에 고정한다.
      paintRingCapIcon(
        canvas,
        center: c,
        radius: r,
        stroke: stroke,
        icon: ringStartIcon(ExerciseLoadKind.values[i]),
      );
      r -= stroke + _kRingGap;
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.t != t || old.ratios != ratios || old.colors != colors;
}

/// 막대 하나. 기록이 없는 칸은 0 짜리 막대가 아니라 **그루터기**로 그린다 —
/// 0 높이 막대는 아무것도 없는 것처럼 보여, 쉰 주와 아직 오지 않은 주가
/// 구분되지 않는다.
///
/// 등장 애니메이션은 [PeriodScrollChart] 가 막대를 바닥에서 드러내며 맡는다.
class _BurnBar extends StatelessWidget {
  const _BurnBar({
    required this.value,
    required this.max,
    required this.height,
    required this.width,
    required this.dimmed,
    this.parts = const <ExerciseLoadKind, double>{},
  });

  final double value;
  final double max;
  final double height;
  final double width;
  final bool dimmed;

  /// 그 주의 유형별 시간(분). 막대 **높이**는 소모 칼로리이고, 막대 **안**은
  /// 이 몫으로 나뉜다. 비어 있으면 한 색으로 채운다(#1177).
  final Map<ExerciseLoadKind, double> parts;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) {
      return Container(
        width: width,
        height: _kBurnStubHeight,
        decoration: const BoxDecoration(
          color: OnCareColors.surfaceInput,
          borderRadius: OnCareRadius.xsAll,
        ),
      );
    }
    final OnCareBrand brand = context.oncare.brand;
    final double total = parts.values.fold<double>(
      0,
      (double a, double b) => a + b,
    );
    final double barHeight = math.max(
      (value / max).clamp(0.0, 1.0) * height,
      _kBurnBarMinHeight,
    );
    final Widget fill = total <= 0
        ? ColoredBox(color: _burnColor(context))
        : Column(
            // 가로로 늘려야 한다 — 가운데 정렬(기본값)이면 조각마다 폭이
            // 0 이 되어 막대가 통째로 사라진다.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 위에서부터 스트레칭·근력·유산소 순으로 쌓는다.
              for (final ExerciseLoadKind k in ExerciseLoadKind.values.reversed)
                Expanded(
                  flex: ((parts[k] ?? 0) * 100).round().clamp(0, 1 << 30),
                  child: ColoredBox(color: kindColor(k, brand)),
                ),
            ],
          );
    return Opacity(
      opacity: dimmed ? _kDimmedBarOpacity : 1,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: OnCareRadius.xs),
        child: SizedBox(width: width, height: barHeight, child: fill),
      ),
    );
  }
}

// ── 전체 ───────────────────────────────────────────────────────────────

/// 한 주치 묶음 — 전체 그래프의 막대 하나.
class _WeekBucket {
  const _WeekBucket({
    required this.monday,
    required this.calories,
    required this.cardioMinutes,
    required this.strengthSets,
    required this.strengthMinutes,
    required this.flexibilityMinutes,
    required this.otherMinutes,
  });

  final DateTime monday;
  final double calories;
  final double cardioMinutes;
  final int strengthSets;

  /// 근력에 쓴 **시간**. 화면에는 세트로 적지만, 막대를 유형별로 나눌 때는
  /// 셋을 같은 단위(분)로 놓아야 몫이 뜻을 갖는다(#1177).
  final double strengthMinutes;

  final double flexibilityMinutes;

  /// 목표가 없는 나머지 운동. 오늘·이번 주와 같이 분만 적는다.
  final double otherMinutes;

  /// 막대를 나누는 몫 — 셋 모두 분이다.
  Map<ExerciseLoadKind, double> get minutesByKind => <ExerciseLoadKind, double>{
    ExerciseLoadKind.cardio: cardioMinutes,
    ExerciseLoadKind.strength: strengthMinutes,
    ExerciseLoadKind.flexibility: flexibilityMinutes,
  };

  double valueOf(ExerciseLoadKind kind) => switch (kind) {
    ExerciseLoadKind.cardio => cardioMinutes,
    ExerciseLoadKind.strength => strengthSets.toDouble(),
    ExerciseLoadKind.flexibility => flexibilityMinutes,
  };
}

/// 전체 = **주 하나가 막대 하나**인 얇은 막대 그래프.
///
/// 하루 단위로 그리면 열두 주가 여든네 칸이 되어 어느 주가 좋았는지 읽히지
/// 않는다. 주로 묶으면 오르내림이 그대로 보이고, 한 칸을 누르면 그 주의
/// 유산소·근력·스트레칭이 머리줄에 펼쳐진다.
class _AllPeriodView extends ConsumerWidget {
  const _AllPeriodView({required this.goals});

  final ExerciseLoadGoals goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    return ref
        .watch(exerciseAllPeriodProvider)
        .when(
          loading: () => const _Card(child: Center(child: AppLoading.inline())),
          error: (Object _, StackTrace _) =>
              _Card(child: Center(child: _Muted(l.exLoadError))),
          data: (List<ExerciseDayBar> days) {
            if (days.isEmpty) {
              return _Card(child: Center(child: _Muted(l.exLoadEmpty)));
            }
            final Map<DateTime, List<ExerciseDayBar>> byWeek =
                <DateTime, List<ExerciseDayBar>>{};
            for (final ExerciseDayBar d in days) {
              final DateTime monday = d.date.subtract(
                Duration(days: d.date.weekday - 1),
              );
              byWeek.putIfAbsent(monday, () => <ExerciseDayBar>[]).add(d);
            }
            final List<DateTime> mondays = byWeek.keys.toList()..sort();
            final List<_WeekBucket> weeks = <_WeekBucket>[
              for (final DateTime m in mondays)
                _WeekBucket(
                  monday: m,
                  calories: byWeek[m]!.fold<double>(
                    0,
                    (double a, ExerciseDayBar d) => a + d.calories,
                  ),
                  cardioMinutes: byWeek[m]!.fold<double>(
                    0,
                    (double a, ExerciseDayBar d) => a + d.cardio,
                  ),
                  strengthSets: byWeek[m]!.fold<int>(
                    0,
                    (int a, ExerciseDayBar d) => a + d.strengthSets.round(),
                  ),
                  strengthMinutes: byWeek[m]!.fold<double>(
                    0,
                    (double a, ExerciseDayBar d) => a + d.strength,
                  ),
                  flexibilityMinutes: byWeek[m]!.fold<double>(
                    0,
                    (double a, ExerciseDayBar d) => a + d.stretching,
                  ),
                  otherMinutes: byWeek[m]!.fold<double>(
                    0,
                    (double a, ExerciseDayBar d) => a + d.other,
                  ),
                ),
            ];
            return _AllPeriodBody(weeks: weeks, goals: goals);
          },
        );
  }
}

class _AllPeriodBody extends StatefulWidget {
  const _AllPeriodBody({required this.weeks, required this.goals});

  final List<_WeekBucket> weeks;
  final ExerciseLoadGoals goals;

  @override
  State<_AllPeriodBody> createState() => _AllPeriodBodyState();
}

class _AllPeriodBodyState extends State<_AllPeriodBody> {
  /// 고른 주와 지금 화면에 들어와 있는 주의 범위. 옆으로 밀면 머리의 평균이
  /// **보이는 구간**을 따라간다 — 여덟 달치를 통째로 평균 내면 어느 달을 보고
  /// 있든 같은 숫자라, 그래프를 미는 의미가 없다.
  final PeriodChartSelection _selection = PeriodChartSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _selection,
    builder: (BuildContext context, Widget? _) => _buildCard(context),
  );

  Widget _buildCard(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final OnCareBrand brand = context.oncare.brand;
    final List<_WeekBucket> weeks = widget.weeks;
    final int? sel = _selection.selected;
    final _WeekBucket? picked = sel == null || sel >= weeks.length
        ? null
        : weeks[sel];
    final (int, int) range = _selection.visible ?? (0, weeks.length - 1);
    final int from = range.$1.clamp(0, weeks.length - 1);
    final int to = range.$2.clamp(from, weeks.length - 1);
    final List<_WeekBucket> visible = weeks.sublist(from, to + 1);
    // 보이는 주를 모두(기록 없는 주 포함) 평균 낸다 — 예전 규칙 그대로다.
    final double visibleAverage = visible.isEmpty
        ? 0
        : visible.fold<double>(0, (double a, _WeekBucket w) => a + w.calories) /
              visible.length;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 머리줄은 **고른 주가 있든 없든 같은 높이**를 쓴다 (#1194).
          SizedBox(
            height: _kAllPeriodHeaderHeight * _layoutScale(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 6,
                  child: PeriodChartHeadline(
                    selected: picked != null,
                    child: _HeadlineLine(
                      caption: picked == null
                          ? l.exBurnAllTitle
                          : l.exWeekOfMonthLabel(
                              picked.monday.month,
                              _weekOfMonth(picked.monday),
                            ),
                      // 고른 주가 없으면 **지금 보이는 구간의 주 평균**이다.
                      value: _valueOfGoal(
                        locale,
                        picked?.calories ?? visibleAverage,
                        widget.goals.weeklyBurnKcal,
                      ),
                      unit: l.unitKcal,
                    ),
                  ),
                ),
                // 고른 주의 내역은 kcal **오른쪽**에 붙는다 (#1129).
                if (picked != null) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    flex: 5,
                    // `기타` 까지 네 줄이 되는 주도 있다 — 그때는 목록 전체가
                    // 한 번에 줄어 같은 높이 안에 들어간다.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final ExerciseLoadKind k
                              in ExerciseLoadKind.values)
                            _AllPeriodDetailLine(
                              label: kindLabel(l, k),
                              value: kindValueText(l, k, picked.valueOf(k)),
                              color: kindColor(k, brand),
                            ),
                          // `기타` 는 유형이 아니다 — 회색으로 둔다.
                          if (picked.otherMinutes > 0)
                            _AllPeriodDetailLine(
                              label: l.exTypeOtherChip,
                              value: l.unitMinutesValue(
                                picked.otherMinutes.round(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (picked == null && visible.isNotEmpty) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  // 평균이 어느 구간의 것인지 기간을 옆에 붙여 둔다.
                  Expanded(
                    flex: 4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${DateFormat.Md(locale).format(visible.first.monday)}'
                        ' ~ '
                        '${DateFormat.Md(locale).format(visible.last.monday.add(const Duration(days: 6)))}',
                        maxLines: 1,
                        style: context.oncare
                            .text(
                              OnCareTypography.strong(OnCareTypography.caption),
                            )
                            .copyWith(color: OnCareColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Expanded(
            child: _WeeklyBurnChart(
              weeks: weeks,
              goal: widget.goals.weeklyBurnKcal,
              selection: _selection,
              locale: locale,
            ),
          ),
        ],
      ),
    );
  }
}

/// 고른 주의 유형별 내역 한 줄 — `유산소 195분`.
///
/// 색은 **유형 이름에만** 주고, 그 색은 옆 막대·링과 **같은 [kindColor]** 다
/// (#1364). 값(`195분`, `12세트`)은 검정이다.
class _AllPeriodDetailLine extends StatelessWidget {
  const _AllPeriodDetailLine({
    required this.label,
    required this.value,
    this.color,
  });

  /// 유형 이름. 이 조각만 [color] 로 칠한다.
  final String label;

  /// 그 유형의 값. 언제나 검정이다.
  final String value;

  /// 유형 색([kindColor]). null 이면 회색 — 유형이 아닌 `기타` 줄이다.
  final Color? color;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: label,
            style: TextStyle(color: color ?? OnCareColors.textSecondary),
          ),
          TextSpan(
            text: ' $value',
            style: const TextStyle(color: OnCareColors.textPrimary),
          ),
        ],
      ),
      maxLines: 1,
      style: context.oncare.text(
        OnCareTypography.strong(OnCareTypography.caption),
      ),
    ),
  );
}

/// `전체` 주간 소모 칼로리 막대 — 패키지 [PeriodScrollChart] 위에 그린다.
///
/// 한 주는 [_kWeekSlot] 폭을 차지하고, 화면에 다 안 들어가면 **옆으로 밀어**
/// 본다 — 폭에 맞춰 칸을 좁히면 주가 늘어날수록 막대가 실오라기가 된다. 주가
/// 적으면 칸을 넓혀 폭을 채운다. 가장 최근 주(오른쪽 끝)에서 시작한다.
class _WeeklyBurnChart extends StatelessWidget {
  const _WeeklyBurnChart({
    required this.weeks,
    required this.goal,
    required this.selection,
    required this.locale,
  });

  final List<_WeekBucket> weeks;
  final double goal;
  final PeriodChartSelection selection;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double peak = <double>[
      goal,
      for (final _WeekBucket w in weeks) w.calories,
    ].fold<double>(1, (double a, double b) => b > a ? b : a);
    final double max = peak * _kChartHeadroom;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double chartH = math.max(c.maxHeight - _kAxisLabelExtent, 0);
        // 목표치 칸을 뺀 그래프 폭에 몇 주가 들어가는지.
        final double axis =
            chartGoalAxisWidth * MediaQuery.textScalerOf(context).scale(1) +
            chartGoalAxisGap;
        final int fit = ((c.maxWidth - axis) / _kWeekSlot).floor();
        final int perScreen = math.max(1, math.min(fit, weeks.length));
        final double goalRatio = (goal / max).clamp(0.0, 1.0);
        return SizedBox(
          key: const Key('exerciseAllPeriodChart'),
          height: c.maxHeight,
          // 목표치는 그래프 왼쪽 칸에 두 줄로 적고(#1071), 목표선은 스크롤 안쪽에
          // 얹힌다 — 둘 다 패키지 그래프가 그린다.
          child: PeriodScrollChart(
            count: weeks.length,
            height: chartH,
            daysPerScreen: perScreen,
            selectedIndex: selection.selected,
            onSelected: selection.select,
            onVisibleRangeChanged: selection.setVisible,
            goalBottom: chartH * goalRatio,
            goalLabel: '${l.homeGoal}\n${goal.round()}',
            revealKey: 'all-burn',
            boldSelectedLabel: true,
            // 눈금선과 달 경계는 막대 **뒤에** 깔린다.
            background: _ChartGridPainter(
              monthBreaks: <int>[
                for (int i = 1; i < weeks.length; i++)
                  if (weeks[i].monday.month != weeks[i - 1].monday.month) i,
              ],
              count: weeks.length,
            ),
            // 달이 바뀌는 칸에만 적는다 — 모든 칸에 적으면 글자가 서로 겹친다.
            labelBuilder: (int i) =>
                i == 0 || weeks[i].monday.month != weeks[i - 1].monday.month
                ? DateFormat.MMM(locale).format(weeks[i].monday)
                : '',
            barBuilder: (BuildContext context, int i) => Semantics(
              label:
                  '${weeks[i].monday.month}/${weeks[i].monday.day} ${weeks[i].calories.round()}',
              child: ExcludeSemantics(
                child: _BurnBar(
                  parts: weeks[i].minutesByKind,
                  value: weeks[i].calories,
                  max: max,
                  height: chartH,
                  width: _kBurnBarWidth,
                  dimmed: selection.selected != null && selection.selected != i,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChartGridPainter extends CustomPainter {
  _ChartGridPainter({required this.monthBreaks, required this.count});

  /// 달이 바뀌는 칸의 인덱스.
  final List<int> monthBreaks;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = OnCareColors.lineSubtle
      ..strokeWidth = OnCareSize.hairline;
    for (final double f in <double>[0, 0.5, 1]) {
      final double y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    if (count <= 0) return;
    final double step = size.width / count;
    final Paint dash = Paint()
      ..color = OnCareColors.lineStrong
      ..strokeWidth = OnCareSize.hairline;
    for (final int i in monthBreaks) {
      final double x = step * i;
      for (double y = 0; y < size.height; y += _kGridDashStep) {
        canvas.drawLine(Offset(x, y), Offset(x, y + _kGridDash), dash);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartGridPainter old) =>
      old.count != count || old.monthBreaks != monthBreaks;
}

// ── 공통 조각 ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.surface = true});

  final Widget child;

  /// 카드 바탕·테두리·안쪽 여백을 직접 그릴지. 홈 카드 안에 놓일 때는 끈다 —
  /// 높이 규칙만 남아 두 화면의 카드가 같은 크기로 선다.
  final bool surface;

  @override
  Widget build(BuildContext context) {
    // 높이는 고정이되 **글자 배율을 따라간다**. 세 기간 카드가 같은 높이여야
    // 토글을 눌러도 화면이 출렁이지 않는데, 배율만 커지면 그 고정 높이 안에서
    // 내용이 넘친다(#766 계열).
    final double height = kActivityCardHeight * _layoutScale(context);
    if (!surface) {
      return SizedBox(width: double.infinity, height: height, child: child);
    }
    return SizedBox(
      // 운동 탭의 카드만 이 열쇠를 갖는다 — 홈에 놓인 같은 카드까지 잡히면
      // "카드가 하나" 를 세는 테스트가 두 개를 보게 된다.
      key: const Key('exerciseActivityCard'),
      width: double.infinity,
      height: height,
      child: AppCard(
        // 좌우는 세로보다 넉넉하게 둔다.
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s24,
          vertical: OnCareSpacing.s12,
        ),
        child: child,
      ),
    );
  }
}

/// `오늘 소모  320 kcal` — 한 줄짜리 머리.
class _HeadlineLine extends StatelessWidget {
  const _HeadlineLine({
    required this.caption,
    required this.value,
    required this.unit,
  });

  final String caption;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            caption,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Text(
            value,
            style: tokens
                .text(OnCareTypography.numeric(OnCareTypography.display))
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.oncare
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textTertiary),
  );
}
