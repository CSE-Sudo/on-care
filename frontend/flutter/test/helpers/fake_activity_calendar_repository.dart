import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/repositories/activity_calendar_repository.dart';

/// 기록 그래프의 메모리 대역. (#2075, #2076)
///
/// 데모 저장소(`MockActivityCalendarRepository`)는 식단·색·보호권을 목업 API 에서
/// 받아 오므로 **실제 dio + drift 가 있어야** 답이 온다. DB 를 세우지 않는 화면
/// 테스트(스모크 등)는 그 자리에서 영원히 기다리게 되므로, 그런 테스트는 이 대역을
/// 끼운다 — 식단·운동 저장소를 같은 이유로 바꿔 끼우는 것과 같다.
class FakeActivityCalendarRepository implements ActivityCalendarRepository {
  FakeActivityCalendarRepository({
    Set<DateTime>? diet,
    Set<DateTime>? exercise,
    this.recordStreakDays = 0,
    this.shieldsHeld = 0,
    this.protectableFrom,
    this.protectableTo,
    this.days = 371,
    DateTime Function()? now,
  }) : _diet = <String>{for (final DateTime d in diet ?? <DateTime>{}) _key(d)},
       _exercise = <String>{
         for (final DateTime d in exercise ?? <DateTime>{}) _key(d),
       },
       _now = now ?? todayKst;

  final Set<String> _diet;
  final Set<String> _exercise;
  final DateTime Function() _now;

  /// 돌려줄 날 수 — 서버 기본과 같은 371일(53주)이다.
  final int days;

  final int recordStreakDays;
  final int shieldsHeld;
  final DateTime? protectableFrom;
  final DateTime? protectableTo;

  /// 마지막으로 고른 색. 화면이 색을 바꿨는지 보는 자리다.
  String? selectedColor;

  GraphColorState color = GraphColorState.base;

  @override
  Future<ActivityCalendar> fetch({DateTime? from, DateTime? to}) async {
    final DateTime last = to ?? _dateOnly(_now());
    final DateTime first =
        from ?? DateTime(last.year, last.month, last.day - (days - 1));
    return ActivityCalendar(
      days: <ActivityDay>[
        for (
          DateTime d = first;
          !d.isAfter(last);
          d = DateTime(d.year, d.month, d.day + 1)
        )
          ActivityDay(
            date: d,
            hasDiet: _diet.contains(_key(d)),
            hasExercise: _exercise.contains(_key(d)),
          ),
      ],
      recordStreakDays: recordStreakDays,
      shieldsHeld: shieldsHeld,
      protectableFrom: protectableFrom,
      protectableTo: protectableTo,
      color: color,
    );
  }

  @override
  Future<GraphColorState> selectColor(String color) async {
    selectedColor = color;
    this.color = GraphColorState(
      current: color,
      unlocked: <String>{...this.color.unlocked, color}.toList(),
      palette: this.color.palette,
      cost: this.color.cost,
    );
    return this.color;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
