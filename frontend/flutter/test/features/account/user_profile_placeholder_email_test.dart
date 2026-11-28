/// 프로필 응답의 대체 이메일 표시 읽기 — #3338.
///
/// 서버는 소셜 가입의 대체 이메일(`kakao_…@social.oncare`)을 `email` 에 그대로
/// 싣고 `email_is_placeholder` 로 알린다. 앱은 그 표시를 보고 주소를 가린다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';

void main() {
  test('대체 이메일이면 보이는 이메일이 비어 있다', () {
    final UserProfile profile = UserProfile.fromJson(<String, Object?>{
      'id': 'user-social',
      'name': '김민수',
      'email': 'kakao_4242@social.oncare',
      'email_is_placeholder': true,
      'email_placeholder_provider': 'kakao',
    });

    expect(profile.emailIsPlaceholder, isTrue);
    expect(profile.emailPlaceholderProvider, 'kakao');
    // 서버가 준 값은 들고 있되 화면에는 쓰지 않는다.
    expect(profile.email, 'kakao_4242@social.oncare');
    expect(profile.visibleEmail, isEmpty);
  });

  test('실제 이메일은 그대로 보인다', () {
    final UserProfile profile = UserProfile.fromJson(<String, Object?>{
      'id': 'user-real',
      'name': '김민수',
      'email': 'minsu@oncare.com',
      'email_is_placeholder': false,
      'email_placeholder_provider': null,
    });

    expect(profile.emailIsPlaceholder, isFalse);
    expect(profile.emailPlaceholderProvider, isNull);
    expect(profile.visibleEmail, 'minsu@oncare.com');
  });

  test('표시를 주지 않는 옛 서버의 이메일은 실제 주소로 본다', () {
    final UserProfile profile = UserProfile.fromJson(<String, Object?>{
      'id': 'user-old',
      'name': '김민수',
      'email': 'minsu@oncare.com',
    });

    expect(profile.emailIsPlaceholder, isFalse);
    expect(profile.visibleEmail, 'minsu@oncare.com');
  });

  test('가입 수단이 빈 문자열이면 모르는 것으로 본다', () {
    final UserProfile profile = UserProfile.fromJson(<String, Object?>{
      'id': 'user-social',
      'name': '김민수',
      'email': 'x@social.oncare',
      'email_is_placeholder': true,
      'email_placeholder_provider': '',
    });

    expect(profile.emailIsPlaceholder, isTrue);
    expect(profile.emailPlaceholderProvider, isNull);
  });
}
