import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/benefits/data/repositories/dio_challenge_repository.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/domain/repositories/challenge_repository.dart';

/// 주간 운동 챌린지 저장소. (#1789)
///
/// 모드마다 저장소를 가르지 않는다 — 데모 모드는 Dio 의 `LocalApiInterceptor` 가
/// 같은 경로를 받아 목업 포인트 원장으로 답한다.
final challengeRepositoryProvider = Provider<ChallengeRepository>(
  (ref) => DioChallengeRepository(ref.watch(dioProvider)),
  name: 'challengeRepository',
);

/// 이번 주 챌린지 — 사용처 참가 카드와 운동 현황 진행 줄이 본다. 운동 기록을
/// 저장·삭제하면 다시 읽는다(`refreshPointsBalance`).
final weeklyChallengeProvider = FutureProvider.autoDispose<WeeklyChallenge>(
  (ref) => ref.watch(challengeRepositoryProvider).fetchWeekly(),
  name: 'weeklyChallenge',
);
