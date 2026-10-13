/// 교환·식판·챌린지 참가의 실패 까닭 가르기 — 서버 사유 문장을 원인으로 옮긴다. (#3363)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/benefit_rejection.dart';

BenefitRejection _conflict(String detail) => BenefitRejection.of(
  ServerError(statusCode: 409, message: detail, detail: detail),
);

void main() {
  test('잔액 부족은 모자란 포인트를 함께 읽는다', () {
    final BenefitRejection r = _conflict('포인트가 200P 부족해요.');
    expect(r.kind, BenefitRejectionKind.insufficientPoints);
    expect(r.shortfall, 200);
    expect(r.retryable, isFalse);
  });

  test('수가 없는 잔액 부족 문장도 잔액 부족이다', () {
    final BenefitRejection r = _conflict('포인트가 부족해요.');
    expect(r.kind, BenefitRejectionKind.insufficientPoints);
    expect(r.shortfall, 0);
  });

  test('이미 가진 것은 이미 보유다', () {
    for (final String detail in <String>[
      '사용하지 않은 쿠폰이 이미 있어요.',
      '이미 가지고 있는 색이에요.',
      '이미 달고 있는 펫이 있어요.',
      '이 주의 리포트는 이미 받았어요.',
      '식판은 이미 받았어요.',
      '받지 않은 식판 쿠폰이 이미 있어요.',
      '이번 주 챌린지에 이미 참가했어요.',
    ]) {
      expect(
        _conflict(detail).kind,
        BenefitRejectionKind.alreadyOwned,
        reason: detail,
      );
    }
  });

  test('보호권 최대 보유와 이번 달 교환은 한도다', () {
    expect(
      _conflict('보호권은 최대 4개까지 가질 수 있어요.').kind,
      BenefitRejectionKind.shieldLimit,
    );
    expect(
      _conflict('이번 달에는 이미 교환했어요.').kind,
      BenefitRejectionKind.monthlyLimit,
    );
  });

  test('그 밖의 409 는 막힘이고 서버 사유를 들고 간다', () {
    for (final String detail in <String>[
      '담당 트레이너가 있어야 교환할 수 있어요.',
      '헬스장을 연결해야 교환할 수 있어요.',
      '주간 챌린지는 월·화요일에만 참가할 수 있어요.',
      '식단 사진 기록이 3일 더 필요해요.',
      '담당 트레이너가 주간 리포트를 보내 줘요.',
    ]) {
      final BenefitRejection r = _conflict(detail);
      expect(r.kind, BenefitRejectionKind.blocked, reason: detail);
      expect(r.detail, detail);
      expect(r.retryable, isFalse);
    }
    expect(
      BenefitRejection.of(const ServerError(statusCode: 409)).kind,
      BenefitRejectionKind.blocked,
    );
  });

  test('없는 항목·거절된 값·권한 없음은 다시 해도 같은 답이라 막힘이다', () {
    expect(
      BenefitRejection.of(const NotFoundError(detail: '없는 교환 항목이에요.')).kind,
      BenefitRejectionKind.blocked,
    );
    expect(
      BenefitRejection.of(const ValidationError(statusCode: 422)).kind,
      BenefitRejectionKind.blocked,
    );
    expect(
      BenefitRejection.of(const ForbiddenError()).kind,
      BenefitRejectionKind.blocked,
    );
  });

  test('답을 받지 못한 실패는 같은 요청으로 다시 보낼 수 있다', () {
    for (final Object error in <Object>[
      const NetworkError(),
      const ServerError(statusCode: 500),
      const ServerError(statusCode: 503, detail: '포인트가 200P 부족해요.'),
      const ServerError(),
      const UnknownError(),
      const RateLimitedError(),
      StateError('네트워크 없음'),
    ]) {
      final BenefitRejection r = BenefitRejection.of(error);
      expect(r.kind, BenefitRejectionKind.retryable, reason: '$error');
      expect(r.retryable, isTrue);
    }
  });
}
