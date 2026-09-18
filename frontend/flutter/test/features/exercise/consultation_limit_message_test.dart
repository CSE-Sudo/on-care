import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/presentation/utils/consultation_limit_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 신청 한도 안내 문구 (#1628). 서버 `Retry-After` 를 회원이 읽는 단위로 올려 적는다.
void main() {
  final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

  test('모르면 "잠시 후" 로 적는다', () {
    expect(consultationRateLimitedMessage(l, null), l.exConsultRateLimited);
    expect(
      consultationRateLimitedMessage(l, Duration.zero),
      l.exConsultRateLimited,
    );
  });

  test('한 시간 안쪽은 분으로, 올림해서 적는다', () {
    // 내림으로 적으면 안내한 시각에 다시 눌러도 아직 막혀 있다.
    expect(
      consultationRateLimitedMessage(l, const Duration(seconds: 30)),
      l.exConsultRateLimitedMinutes(1),
    );
    expect(
      consultationRateLimitedMessage(
        l,
        const Duration(minutes: 58, seconds: 1),
      ),
      l.exConsultRateLimitedMinutes(59),
    );
  });

  test('한 시간부터는 시간으로, 올림해서 적는다', () {
    expect(
      consultationRateLimitedMessage(l, const Duration(minutes: 60)),
      l.exConsultRateLimitedHours(1),
    );
    expect(
      consultationRateLimitedMessage(l, const Duration(minutes: 61)),
      l.exConsultRateLimitedHours(2),
    );
    expect(
      consultationRateLimitedMessage(l, const Duration(hours: 23, minutes: 59)),
      l.exConsultRateLimitedHours(24),
    );
  });

  test('대기 상한은 서버가 준 건수로 적고, 없으면 건수를 빼고 적는다', () {
    expect(
      consultationTooManyPendingMessage(l, 3),
      '답을 기다리는 상담 요청이 이미 3건 있어요. 답을 받거나 요청을 취소한 뒤 다시 신청해 주세요.',
    );
    expect(
      consultationTooManyPendingMessage(l, null),
      l.exConsultTooManyPendingNoCount,
    );
  });
}
