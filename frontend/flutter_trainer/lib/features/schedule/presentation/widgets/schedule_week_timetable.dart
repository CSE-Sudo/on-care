import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_chips.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 월~일 주간 시간표 — 왼쪽 시간축과 요일 열의 격자. (#988)
///
/// 이전 주 보기는 요일마다 세션 칩을 위에서부터 차곡차곡 쌓았다. 그래서
/// **빈 시간이 화면에 없었다** — 10시 세션과 19시 세션이 세로로 붙어 있어
/// 그 사이가 9시간 비어 있다는 사실을 칩의 글씨를 읽기 전에는 알 수 없었다.
/// 트레이너가 주 보기를 여는 이유가 "어디에 넣을 수 있나" 인데, 정작 그
/// 질문에 답하지 못하는 표현이었다.
///
/// 지금은 세로축이 **시각**이다. 블록의 위치는 시작 시각, 높이는 소요 시간이라
/// 빈 시간이 빈 칸으로 남는다. 한 시간마다 눈금선이 있어 요일 사이를 가로로
/// 훑어 같은 시간대를 비교할 수 있다.
///
/// 보이는 주는 항상 월요일에서 일요일까지다. `오늘 − 3일` 로 잡던 때에는 매일
/// 다른 요일에서 시작해, 화면이 말하는 "주" 와 사람이 말하는 "이번 주" 가
/// 어긋났다.
class ScheduleWeekTimetable extends ConsumerWidget {
  /// Creates the week timetable.
  const ScheduleWeekTimetable({
    super.key,
    required this.weekStart,
    required this.sessions,
    required this.selectedDay,
    required this.selectedSessionId,
    required this.onPickDay,
    required this.onPickSession,
    this.bodyOverride,
  });

  /// 보이는 주의 월요일.
  final DateTime weekStart;

  /// 그 주 전체의 세션. 공백 슬롯은 그리지 않는다 — 빈 시간은 이제 격자가
  /// 말한다.
  final List<ScheduleSession> sessions;

  /// 상세 패널이 보고 있는 날.
  final DateTime selectedDay;

  /// 상세 패널이 보고 있는 세션. 그 블록만 테두리로 도드라진다.
  final String? selectedSessionId;

  final ValueChanged<DateTime> onPickDay;
  final ValueChanged<ScheduleSession> onPickSession;

  /// 격자 대신 그릴 것 — 주를 불러오는 중이거나 실패했을 때. 요일 머리글은 늘
  /// 남는다: 주를 넘길 때마다 날짜 줄이 스피너로 사라지면 화면이 깜빡이고,
  /// 무엇보다 **날짜를 고를 자리가 잠깐 없어진다**(review PR 245).
  final Widget? bodyOverride;

  /// 한 시간 칸의 최대 높이. 이보다 커질 이유는 없다 — 블록에 담을 것이 두
  /// 줄뿐이라 남는 자리는 여백이 된다.
  static const double maxHourHeight = 104;

  /// 한 시간 칸의 최소 높이. 30분 블록에 **시간·이름 두 줄**이 들어가는 값이다.
  ///
  /// 필요한 높이 = 세로 여백 2×2 + `caption`(보이는 12 × 줄 높이 1.4) × 2 ≈ 38.
  /// 30분이 그만큼이려면 한 시간은 76 이상이어야 한다. 80 으로 조금 띄워 둔다 —
  /// 딱 맞춰 두면 글꼴이 바뀌는 것만으로 이름 줄이 통째로 사라진다.
  static const double minHourHeight = 80;

  /// 왼쪽 시간축 폭.
  static const double gutterWidth = 48;

  /// 요일 머리글 높이.
  static const double headerHeight = 46;

  /// 블록의 최소 높이 — 0분·아주 짧은 행도 손가락으로 짚을 수 있어야 한다.
  static const double _minBlockHeight = 24;

  /// 세션이 없어도 늘 보여 주는 시간대(자정부터의 분).
  ///
  /// **07:30 에서 시작한다.** 07:00 을 창의 첫 줄로 두면 그 라벨을 올릴 자리가
  /// 위에 없어 카드 경계에 잘린다. 반만 보이는 라벨은 읽히지도 않으면서 잘린
  /// 것처럼 보이므로, 그 30분을 아예 창에 넣지 않는다(#1010).
  static const int defaultStartMinute = 7 * 60 + 30;

  /// 끝도 30분을 더 둔다. 23:00 을 창의 마지막 줄로 두면 그 라벨 아래에 여백이
  /// 없어, 07:00 이 위에서 잘리던 것과 같은 일이 아래에서 벌어진다(#1010).
  static const int defaultEndMinute = 23 * 60 + 30;

  /// 창의 양 끝을 맞추는 단위. 30분보다 잘게 맞추면 첫 눈금이 어중간한 자리에
  /// 걸려 시간축이 읽히지 않는다.
  static const int windowStep = 30;

  /// `HH:mm` 을 자정부터의 분으로. 형식이 다르면 null — 시각을 모르는 행은
  /// 시간표에 앉힐 자리가 없다.
  static int? minutesOfDay(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// 이 주가 보여야 할 시간 창(자정부터의 분). 기본 창을 세션이 넘으면 그만큼
  /// 넓힌다 — 06:00 수업이 화면 밖에 있으면 시간표가 거짓말을 한다.
  static ({int start, int end}) visibleWindow(List<ScheduleSession> sessions) {
    var start = defaultStartMinute;
    var end = defaultEndMinute;
    for (final s in sessions) {
      if (s.isGap) continue;
      final from = minutesOfDay(s.time);
      if (from == null) continue;
      final to = from + math.max<int>(s.durationMinutes, 30);
      start = math.min(start, (from ~/ windowStep) * windowStep);
      end = math.max(end, ((to + windowStep - 1) ~/ windowStep) * windowStep);
    }
    start = start.clamp(0, minutesPerDay - windowStep);
    end = end.clamp(start + windowStep, minutesPerDay);
    return (start: start, end: end);
  }

  /// 하루의 분.
  static const int minutesPerDay = 24 * 60;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final days = <DateTime>[
      for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i)),
    ];
    // 로스터는 여기서 한 번만 구독한다. 블록마다 구독하면 주에 그려지는 수만큼
    // 구독이 생기고, 로스터가 갱신될 때 그 블록들이 각자 다시 빌드된다.
    final roster =
        ref.watch(clientsProvider).valueOrNull ?? const <TrainerClient>[];
    final names = <String, String>{
      for (final s in sessions)
        s.id:
            _rosterClient(
              roster,
              clientId: s.clientId,
              clientName: s.clientName,
            )?.name ??
            s.clientName,
    };
    final window = visibleWindow(sessions);
    final byDate = <String, List<ScheduleSession>>{};
    for (final s in sessions) {
      if (s.isGap || minutesOfDay(s.time) == null) continue;
      byDate.putIfAbsent(s.date, () => <ScheduleSession>[]).add(s);
    }
    final today = ymd(nowKst());

    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: OnCareColors.surfaceCard,
          borderRadius: OnCareRadius.mdAll,
          border: Border.all(color: OnCareColors.lineStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: headerHeight,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: gutterWidth),
                  for (final day in days)
                    Expanded(
                      child: _DayHeader(
                        day: day,
                        isToday: ymd(day) == today,
                        selected: ymd(day) == ymd(selectedDay),
                        onTap: () => onPickDay(day),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              height: OnCareSize.hairline,
              color: OnCareColors.lineStrong,
            ),
            Expanded(
              child:
                  bodyOverride ??
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double hours = (window.end - window.start) / 60;
                      // 남는 높이에 맞춰 칸을 늘리고 줄인다. 들어갈 수 있으면
                      // 스크롤 없이 한 주가 통째로 보이고, 모자라면 최소 높이
                      // 까지 줄인 뒤 그때부터 스크롤한다(#1010).
                      final double hourHeight = (constraints.maxHeight / hours)
                          .clamp(minHourHeight, maxHourHeight);
                      return SingleChildScrollView(
                        key: const Key('schedule-timetable-scroll'),
                        child: SizedBox(
                          height: hours * hourHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _TimeGutter(
                                window: window,
                                hourHeight: hourHeight,
                              ),
                              for (final day in days)
                                Expanded(
                                  child: _DayColumn(
                                    day: day,
                                    window: window,
                                    hourHeight: hourHeight,
                                    sessions:
                                        byDate[ymd(day)] ??
                                        const <ScheduleSession>[],
                                    selectedSessionId: selectedSessionId,
                                    names: names,
                                    onPickSession: onPickSession,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
            if (bodyOverride == null && byDate.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: OnCareSpacing.s8,
                ),
                child: Text(
                  l.schedEmptyWeek,
                  textAlign: TextAlign.center,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 세션이 가리키는 로스터 회원. id 가 맞으면 그 회원, 없으면 이름이 **정확히
/// 한 명**을 가리킬 때만 그 회원이다(`shared/widgets/client_identity.dart` 의
/// `findClientIdentity` 와 같은 규칙 — 화면 위젯 파일을 끌어오지 않으려고
/// 여기 둔다).
TrainerClient? _rosterClient(
  List<TrainerClient> clients, {
  required String? clientId,
  required String clientName,
}) {
  for (final client in clients) {
    if (clientId != null && client.id == clientId) return client;
  }
  final sameName = clients.where((client) => client.name == clientName);
  return sameName.length == 1 ? sameName.single : null;
}

/// 요일 머리글 한 칸 — `월` 과 날짜. 누르면 그 날을 고른다.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final weekend = day.weekday >= DateTime.saturday;

    return InkWell(
      key: ValueKey<String>('schedule-day-${ymd(day)}'),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.brand.surface : Colors.transparent,
          border: const Border(
            left: BorderSide(color: OnCareColors.lineSubtle),
          ),
        ),
        // 큰 글자 배율(#849 관문은 1.3 을 쓴다)에서 두 줄이 머리글 높이를
        // 넘는다. 글자를 자르는 대신 통째로 작게 그린다.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                weekdayNames(l)[day.weekday - 1],
                style: chartAxisLabelStyle(context).copyWith(
                  color: weekend
                      ? OnCareColors.textTertiary
                      : OnCareColors.textSecondary,
                ),
              ),
              Text(
                '${day.day}',
                style: OnCareTypography.numeric(
                  tokens.text(OnCareTypography.titleSmall),
                ).copyWith(
                  color: isToday
                      ? tokens.brand.primary
                      : OnCareColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 왼쪽 시간축 — 눈금선이 그어지는 자리에 그 시각을 적는다.
///
/// 창이 정각에서 시작하지 않으므로(07:30) 라벨을 칸 단위로 쌓지 않고 **분으로
/// 앉힌다.** 라벨은 눈금선에 걸치게 올려 둔다 — 칸 한가운데 적으면 어느 선이
/// 그 시각인지 읽는 사람이 한 번 더 생각해야 한다.
class _TimeGutter extends StatelessWidget {
  const _TimeGutter({required this.window, required this.hourHeight});

  final ({int start, int end}) window;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = OnCareTypography.numeric(
      chartAxisLabelStyle(context),
    );
    final double labelHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1);
    final double gridHeight = (window.end - window.start) / 60 * hourHeight;
    final int firstHour = (window.start + 59) ~/ 60;

    return SizedBox(
      width: ScheduleWeekTimetable.gutterWidth,
      child: Stack(
        children: <Widget>[
          for (var hour = firstHour; hour * 60 <= window.end; hour++)
            Positioned(
              // 창의 양 끝에서는 라벨을 격자 안으로 밀어 넣는다. 반만 보이는
              // 라벨을 남기느니 눈금에서 조금 어긋나는 편이 낫다.
              top:
                  ((hour * 60 - window.start) / 60 * hourHeight -
                          labelHeight / 2)
                      .clamp(0.0, math.max(gridHeight - labelHeight, 0.0)),
              right: OnCareSpacing.s8,
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

/// 하루 열 — 눈금 격자 위에 세션 블록을 앉힌다.
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.window,
    required this.hourHeight,
    required this.sessions,
    required this.selectedSessionId,
    required this.names,
    required this.onPickSession,
  });

  final DateTime day;
  final ({int start, int end}) window;
  final double hourHeight;
  final List<ScheduleSession> sessions;
  final String? selectedSessionId;

  /// 세션 id → 화면이 부를 이름.
  final Map<String, String> names;

  final ValueChanged<ScheduleSession> onPickSession;

  /// 블록과 열 경계 사이의 틈(좌우 각각).
  static const double _laneInset = OnCareSpacing.s2;

  @override
  Widget build(BuildContext context) {
    final placed = _placeSessions(sessions);
    final windowStart = window.start;
    final windowMinutes = window.end - window.start;
    final firstHour = (windowStart + 59) ~/ 60;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // 격자 — 일정이 없는 시간대도 칸으로 남는다. 창이 정각에서
              // 시작하지 않으므로 칸을 쌓지 않고 정각마다 선을 앉힌다.
              for (var hour = firstHour; hour * 60 < window.end; hour++)
                Positioned(
                  top: (hour * 60 - windowStart) / 60 * hourHeight,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: OnCareSize.hairline,
                    color: OnCareColors.lineSubtle,
                  ),
                ),
              for (final p in placed)
                Positioned(
                  top:
                      (p.startMinute - windowStart).clamp(0, windowMinutes) /
                      60 *
                      hourHeight,
                  left: width * p.lane / p.lanes + _laneInset,
                  // 열이 좁은데 같은 시간대가 여럿 겹치면 음수가 된다. 음수 폭은
                  // `BoxConstraints` 단정에 걸려 시간표를 통째로 죽인다 — 겹침
                  // 수는 트레이너가 만드는 값이라 막아 둔다.
                  width: math.max(
                    width / p.lanes - _laneInset * 2,
                    OnCareSize.hairline,
                  ),
                  // 끝나는 시각도 창 안으로 자른다. 자정을 넘는 세션은 창의
                  // 끝(24시)까지만 그려야 격자 아래로 삐져나오지 않는다.
                  height: math.max(
                    (p.endMinute.clamp(
                              windowStart,
                              windowStart + windowMinutes,
                            ) -
                            p.startMinute.clamp(
                              windowStart,
                              windowStart + windowMinutes,
                            )) /
                        60 *
                        hourHeight,
                    ScheduleWeekTimetable._minBlockHeight,
                  ),
                  child: _SessionBlock(
                    session: p.session,
                    name: names[p.session.id] ?? p.session.clientName,
                    selected: p.session.id == selectedSessionId,
                    onTap: () => onPickSession(p.session),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 시간표에 앉은 세션 한 건 — 시작·끝(분)과 겹침을 나눠 쓰는 열 번호.
class _Placed {
  const _Placed({
    required this.session,
    required this.startMinute,
    required this.endMinute,
    required this.lane,
    required this.lanes,
  });

  final ScheduleSession session;
  final int startMinute;
  final int endMinute;
  final int lane;
  final int lanes;
}

/// 겹치는 세션을 나란히 세운다.
///
/// 겹치는 것끼리 묶어(뭉치) 그 뭉치 안에서만 폭을 나눈다. 하루 전체를 기준으로
/// 나누면 아침에 한 번 겹쳤다는 이유로 저녁 세션까지 반으로 얇아진다.
List<_Placed> _placeSessions(List<ScheduleSession> sessions) {
  final spans = <({ScheduleSession session, int start, int end})>[];
  for (final s in sessions) {
    final start = ScheduleWeekTimetable.minutesOfDay(s.time);
    if (start == null) continue;
    // 0분짜리 행도 손가락으로 짚을 수 있어야 한다.
    final end = start + math.max<int>(s.durationMinutes, 30);
    spans.add((session: s, start: start, end: end));
  }
  spans.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.session.id.compareTo(b.session.id);
  });

  final placed = <_Placed>[];
  var cluster = <({ScheduleSession session, int start, int end})>[];
  var clusterEnd = -1;

  void flush() {
    if (cluster.isEmpty) return;
    final laneEnds = <int>[];
    final laneOf = <int>[];
    for (final span in cluster) {
      var lane = laneEnds.indexWhere((end) => end <= span.start);
      if (lane < 0) {
        laneEnds.add(span.end);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = span.end;
      }
      laneOf.add(lane);
    }
    for (var i = 0; i < cluster.length; i++) {
      placed.add(
        _Placed(
          session: cluster[i].session,
          startMinute: cluster[i].start,
          endMinute: cluster[i].end,
          lane: laneOf[i],
          lanes: laneEnds.length,
        ),
      );
    }
    cluster = <({ScheduleSession session, int start, int end})>[];
    clusterEnd = -1;
  }

  for (final span in spans) {
    if (cluster.isNotEmpty && span.start >= clusterEnd) flush();
    cluster.add(span);
    clusterEnd = math.max(clusterEnd, span.end);
  }
  flush();
  return placed;
}

/// 시간표 위의 세션 한 건.
///
/// 블록이 답해야 하는 것은 **언제·누구와·무엇을** 이다. 이전 칩에는 시작 시각과
/// 이름뿐이라, 언제 끝나는지와 `1:1 PT` 인지 `상담` 인지를 알려면 눌러 봐야
/// 했다(#988). 높이가 허락하는 만큼 위에서부터 채운다 — 30분짜리 블록에 세 줄을
/// 밀어 넣으면 셋 다 읽히지 않는다.
class _SessionBlock extends StatelessWidget {
  const _SessionBlock({
    required this.session,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final ScheduleSession session;

  /// 화면이 부를 이름.
  final String name;

  final bool selected;
  final VoidCallback onTap;

  /// 상담인가. 종류는 색을 하나 더 들이는 대신 **채움과 비움**으로 가른다 —
  /// 1:1 PT 는 연한 브랜드 면으로 채우고, 상담은 흰 바탕에 브랜드 윤곽선을
  /// 두른다(#1013).
  bool get _isConsultation => session.type == SessionType.consultation;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final Color tone = tokens.brand.primary;
    // **왼쪽 띠의 색은 상태**를 말한다 — 예정(브랜드)·완료(초록)·취소/노쇼
    // (주의). 면(종류)과 갈래가 달라 두 값이 서로를 덮지 않는다.
    final Color statusTone = switch (session.status) {
      ScheduleStatus.done => OnCareColors.success,
      ScheduleStatus.cancelled || ScheduleStatus.noShow => OnCareColors.caution,
      _ => tone,
    };
    // 끝난 세션은 종류(브랜드)가 아니라 **상세 카드와 같은 회색**으로 물러난다.
    // 왼쪽 띠가 이미 초록(완료)으로 결과를 말하는데, 면까지 브랜드 색이면 종류가
    // 아직 진행 중인 것처럼 두 번 읽혔다(#1012, #1013).
    const Color finishedTone = OnCareColors.textDisabled;
    final Color surface = _isConsultation
        ? OnCareColors.surfaceCard
        : (session.isFinished
              ? OnCareColors.surfaceInput
              : tokens.brand.surface);
    final start = ScheduleWeekTimetable.minutesOfDay(session.time) ?? 0;
    final end = start + session.durationMinutes;
    final type = sessionTypeLabel(l, session.type);
    // 블록은 두 줄이다: `10–11` / `김민수 1:1 PT`. 세 줄이던 때에는 30분
    // 세션이 칸의 절반을 차지해 하루가 한 화면에 들어오지 않았다(#1010).
    //
    // 정각의 `:00` 은 읽는 데 보태는 것이 없어 뗀다. 툴팁과 시맨틱스에는 자른
    // 값이 아니라 온전한 시각을 남긴다 — 소리로 듣는 쪽은 줄일 이유가 없다.
    final range = l.schedTimeRange(session.time, _hhmm(end));
    final detail = l.sessionTypeAndDuration(type, session.durationMinutes);
    // 소요 시간은 첫 줄에 적지 않는다. 시각 옆 `(60분)` 은 좁은 블록에서
    // 자리만 먹고, 종류·이름을 훑는 데 보태는 것이 없었다 — 필요하면 툴팁·
    // 시맨틱스(`detail`)에 남아 있다.
    final TextStyle lineStyle = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );

    return Tooltip(
      message: '$range · $name · $detail',
      child: Semantics(
        button: true,
        label: '$range $name $detail',
        // 라벨이 이미 같은 값을 말한다. 자식 텍스트까지 읽히면 블록 하나가 두 번
        // 낭독되어 시간표를 훑기 어렵다.
        excludeSemantics: true,
        child: Material(
          color: surface,
          borderRadius: OnCareRadius.xsAll,
          child: InkWell(
            // 일정 한 건이 달력에 그려졌음을 가리키는 키. 일 보기 타임라인이
            // 쓰던 이름을 그대로 이어받는다 — E2E 가 이 이름으로 찾는다.
            key: ValueKey<String>('schedule-session-${session.id}'),
            onTap: onTap,
            borderRadius: OnCareRadius.xsAll,
            // 상태 띠를 `Border` 의 왼쪽 변으로 그리면 네 변의 색이 달라져,
            // 둥근 모서리와 함께 쓸 수 없다("borderRadius can only be given on
            // borders with uniform colors"). 띠를 자식으로 세우고 윤곽선은
            // 균일하게 둔다.
            child: ClipRRect(
              borderRadius: OnCareRadius.xsAll,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // 상담은 사면을 두른다 — 그 윤곽선이 종류를 말한다. 고른
                  // 블록은 어느 종류든 테두리가 굵어진다.
                  border: selected || _isConsultation
                      ? Border.all(
                          color: selected
                              ? statusTone
                              : (session.isFinished
                                    ? OnCareColors.lineStrong
                                    : tokens.brand.border),
                          width: selected
                              ? OnCareSize.focusBorder
                              : OnCareSize.hairline,
                        )
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 왼쪽 띠가 상태를 말한다.
                    SizedBox(
                      width: selected ? OnCareSpacing.s4 : OnCareSpacing.s2,
                      child: ColoredBox(color: statusTone),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OnCareSpacing.s4,
                          vertical: OnCareSpacing.s2,
                        ),
                        // 남는 높이에 맞춰 **들어가는 줄만** 그린다. 잘라 내면 반 토막
                        // 난 글자가 남아 읽을 수도 없고 읽으려 하게 된다 — 아예 빼는
                        // 편이 낫다. 시간이 먼저고 사람이 그 다음이다.
                        child: _BlockLines(
                          lines: <_BlockLine>[
                            _BlockLine(
                              text: range,
                              style: OnCareTypography.numeric(
                                lineStyle,
                              ).copyWith(
                                color: session.isFinished ? finishedTone : tone,
                              ),
                            ),
                            // 둘째 줄에서 먼저 읽혀야 하는 것은 **누구인가** 다. 종류는
                            // 같은 줄에 붙되 줄 높이 안으로 줄여 물린다 — 이름과 같은
                            // 무게로 두면 `1:1 PT` 가 이름만큼 눈에 들어온다.
                            //
                            // 흐린 글씨이던 것을 **상세 카드와 같은 알약**으로 바꾼다.
                            // 같은 값을 두 자리가 다른 모양으로 말하면 읽는 쪽이 두 번
                            // 익혀야 한다.
                            _BlockLine(
                              text: name,
                              style: lineStyle.copyWith(
                                color: session.isFinished
                                    ? OnCareColors.textSecondary
                                    : OnCareColors.textPrimary,
                              ),
                              trailing: SessionTypeChip(
                                label: type,
                                muted: session.isFinished,
                                outlined: _isConsultation,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _hhmm(int minutes) {
    final wrapped = minutes % (24 * 60);
    final h = (wrapped ~/ 60).toString().padLeft(2, '0');
    final m = (wrapped % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 블록 한 줄의 글과 그 글꼴.
class _BlockLine {
  const _BlockLine({required this.text, required this.style, this.trailing});

  final String text;
  final TextStyle style;

  /// [text] 오른쪽 끝에 붙는 것 — 종류 알약. 같은 줄이지만 무게가 다르다.
  ///
  /// 이 줄의 높이는 [text] 로만 잰다. [_BlockLines] 가 그 높이만 주므로, 알약은
  /// 그 안으로 줄어들어야 한다(`FittedBox`).
  final Widget? trailing;

  /// 이 줄이 실제로 차지할 높이. 배율이 커지면 함께 커진다.
  double heightIn(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(
        style.fontSize ?? OnCareTypography.caption.fontSize!,
      ) *
      (style.height ?? OnCareTypography.caption.height!);
}

/// 남는 높이에 들어가는 줄만 위에서부터 그린다. (#988)
///
/// 30분 블록에 세 줄을 밀어 넣으면 마지막 줄이 반 토막 난다. 글자를 줄이는 대신
/// — 시간표에서 읽어야 하는 값들이라 줄일 수 없다 — 들어가지 않는 줄을 뺀다.
/// 첫 줄(시간)은 자리가 모자라도 언제나 그린다: 그것마저 없으면 블록이 무엇을
/// 가리키는지 알 수 없다.
class _BlockLines extends StatelessWidget {
  const _BlockLines({required this.lines});

  /// 위에서부터의 우선순위 순서.
  final List<_BlockLine> lines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        final drawn = <Widget>[];
        var used = 0.0;
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final needed = line.heightIn(context);
          if (drawn.isNotEmpty && used + needed > available) break;
          used += needed;
          // 한 줄에 두 가지 무게를 그릴 때도 위젯을 나눈다. `Text.rich` 로 묶으면
          // `find.text` 가 기본으로 지나쳐, 화면에 있는 글을 테스트가 못 찾는다.
          //
          // **이름이 먼저 자리를 가져간다.** 둘을 반씩 나눠 주던 때에는 이름이
          // 네 글자만 되어도 `윤가온(신…` 으로 잘리는데 옆의 종류는 멀쩡했다 —
          // 블록에서 잘리면 안 되는 값은 이름 쪽이다. 종류는 [FittedBox] 로
          // 통째로 작게 그려져 넘치지 않는다.
          drawn.add(
            Row(
              children: <Widget>[
                Flexible(
                  flex: 3,
                  child: Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: line.style,
                  ),
                ),
                if (line.trailing != null) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s4),
                  Flexible(
                    flex: 2,
                    // 알약(태그 높이)이 이름 줄보다 두꺼우면 줄 계산이 어긋나
                    // 30분 블록이 넘친다. 줄 높이만 주고 그 안으로 줄인다.
                    child: SizedBox(height: needed, child: line.trailing),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: drawn,
        );
      },
    );
  }
}
