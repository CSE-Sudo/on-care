/// 주간 챌린지 응답 읽기 — 유예 중(집계 중) 표시. (#3362)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';

Map<String, Object?> _challenge({
  String status = 'active',
  Object? settling,
  String weekStart = '2026-09-14',
  String weekEnd = '2026-09-20',
}) => <String, Object?>{
  'id': 'chl-1',
  'week_start': weekStart,
  'week_end': weekEnd,
  'goal': 3,
  'progress': 2,
  'stake': 100,
  'reward': 200,
  'status': status,
  'settling': ?settling,
  'achieved': false,
  'rewarded': 0,
  'joined_at': '2026-09-14T09:00:00+09:00',
  'settled_at': null,
};

Map<String, Object?> _weekly({Object? challenge, Object? settlingChallenge}) =>
    <String, Object?>{
      'week_start': '2026-09-21',
      'week_end': '2026-09-27',
      'join_until': '2026-09-22',
      'stake': 100,
      'reward': 200,
      'goal': 3,
      'progress': 0,
      'balance': 900,
      'joinable': true,
      'blocked_reason': null,
      'shortfall': 0,
      'challenge': challenge,
      'settling_challenge': ?settlingChallenge,
    };

void main() {
  test('settling 이 참이면 진행 중이면서 집계 중이다', () {
    final Challenge c = Challenge.fromJson(_challenge(settling: true));

    expect(c.status, ChallengeStatus.active);
    expect(c.settling, isTrue);
  });

  test('settling 이 없거나 참이 아니면 집계 중이 아니다', () {
    // 이 필드를 싣기 전의 서버 응답도 그대로 읽는다.
    expect(Challenge.fromJson(_challenge()).settling, isFalse);
    expect(Challenge.fromJson(_challenge(settling: false)).settling, isFalse);
    expect(Challenge.fromJson(_challenge(settling: 'yes')).settling, isFalse);
    expect(
      Challenge.fromJson(
        _challenge(status: 'failed', settling: false),
      ).settling,
      isFalse,
    );
  });

  test('지난주 참가 기록이 유예 중이면 settlingChallenge 로 읽는다', () {
    final WeeklyChallenge state = WeeklyChallenge.fromJson(
      _weekly(settlingChallenge: _challenge(settling: true)),
    );

    expect(state.challenge, isNull);
    expect(state.settlingChallenge, isNotNull);
    expect(state.settlingChallenge!.weekStart, DateTime(2026, 9, 14));
    expect(state.settlingChallenge!.weekEnd, DateTime(2026, 9, 20));
    expect(state.settlingChallenge!.settling, isTrue);
    expect(state.settlingChallenge!.progress, 2);
  });

  test('settling_challenge 가 없거나 null 이면 집계 중인 주가 없다', () {
    expect(WeeklyChallenge.fromJson(_weekly()).settlingChallenge, isNull);
    expect(
      WeeklyChallenge.fromJson(<String, Object?>{
        ..._weekly(),
        'settling_challenge': null,
      }).settlingChallenge,
      isNull,
    );
  });

  test('이번 주 참가 기록과 집계 중인 지난주 기록을 따로 읽는다', () {
    final WeeklyChallenge state = WeeklyChallenge.fromJson(
      _weekly(
        challenge: _challenge(
          weekStart: '2026-09-21',
          weekEnd: '2026-09-27',
          settling: false,
        ),
        settlingChallenge: _challenge(settling: true),
      ),
    );

    expect(state.challenge!.weekStart, DateTime(2026, 9, 21));
    expect(state.challenge!.settling, isFalse);
    expect(state.settlingChallenge!.weekStart, DateTime(2026, 9, 14));
  });
}
