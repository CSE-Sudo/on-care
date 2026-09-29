import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 지금 로그인한 계정의 **세대 번호**. 계정 경계를 넘을 때마다 올라간다. (#2285)
///
/// 트레이너 웹은 한 탭에서 로그아웃하고 다른 트레이너로 다시 로그인할 수 있다.
/// 앱이 살아 있는 동안 유지되는(`autoDispose` 가 아닌) provider 는 세션과 상관없이
/// 처음 읽은 값을 들고 있어서, 다음 계정에게 이전 계정의 회원 목록·알림·템플릿·
/// 리포트가 그대로 보였다 — 트레이너 계정은 담당 회원의 건강 정보를 읽는 계정이라
/// 다른 사람에게 보여서는 안 되는 값이다.
///
/// 그래서 계정 범위의 저장소·상태 provider 는 전부 이 값을 `watch` 한다. 값이
/// 바뀌면 그 provider 와 그 위에 쌓인 provider 가 통째로 다시 만들어지고, 저장소가
/// 들고 있던 메모리 캐시도 함께 버려진다. 로그아웃 자리에서 provider 를 하나하나
/// 무효화하는 방식은 새 provider 를 추가할 때 빠뜨리기 쉽고, 토큰 만료처럼
/// 로그아웃 버튼을 거치지 않는 세션 종료를 놓친다.
///
/// 값을 올리는 쪽은 `SessionController` 하나다 — 세션 상태가 로그인·데모·
/// 로그아웃 사이를 오가거나 로그인한 계정이 바뀔 때 올린다. 토큰 갱신이나 프로필
/// 편집처럼 같은 계정 안에서 일어나는 변화에는 올리지 않는다.
///
/// 인증 기능을 import 하지 않는 잎(leaf) provider 로 둔 이유는
/// `authAccessTokenProvider` 와 같다 — 저장소 계층이 인증 화면 계층에 기대지
/// 않고, 저장소만 쓰는 테스트가 세션 복구를 일으키지 않는다.
final accountScopeProvider = StateProvider<int>(
  (ref) => 0,
  name: 'accountScope',
);

/// 지금 로그아웃 상태인가. (#2285)
///
/// [accountScopeProvider] 와 함께 `SessionController` 가 쓴다. 기본값이 거짓인
/// 이유: 세션을 모르는 자리(저장소만 쓰는 테스트 등)에서는 예전처럼 값을 들고
/// 있어야 한다 — 로그아웃했다는 사실을 **알 때만** 값을 놓는다.
final accountSignedOutProvider = StateProvider<bool>(
  (ref) => false,
  name: 'accountSignedOut',
);

/// 지금 로그인한 트레이너의 이메일. 데모·로그아웃이면 `null` 이다. (#2587)
///
/// 브라우저에 계정별로 남기는 화면 설정(AI 추천이 참고할 자료 등)의 키로 쓴다.
/// [accountScopeProvider] 와 함께 `SessionController` 가 채운다 — 화면이 세션
/// 컨트롤러를 직접 읽으면 그 순간 세션 복구가 돌아, 저장소만 쓰는 테스트가
/// 보안 저장소까지 끌고 온다.
final accountEmailProvider = StateProvider<String?>(
  (ref) => null,
  name: 'accountEmail',
);

/// 계정 세션 동안만 값을 들고 있게 한다. (#2285)
///
/// 계정 범위의 비동기 값(회원 목록·알림·템플릿·리포트 등)은 `autoDispose` 로
/// 선언하고 build 첫 줄에서 이 함수를 부른다. 효과는 두 가지다.
///
///  * 계정이 그대로인 동안에는 예전의 `autoDispose` 가 아닌 provider 처럼
///    구독자가 없어도 값을 들고 있다 — 탭을 오갈 때 다시 읽지 않는다.
///  * [accountScopeProvider] 가 바뀌면 붙잡아 둔 끈이 풀린다. 그 순간 구독자가
///    없으면 provider 가 **통째로 버려지고**, 다음 계정은 빈 상태에서 새로 읽는다.
///  * 로그아웃 상태에서는 끈을 다시 잡지 않는다. 로그아웃하는 순간 화면이 아직
///    구독 중이라 한 번 다시 계산되더라도, 로그인 화면으로 넘어가 구독이 끝나면
///    곧바로 버려진다 — 이전 계정의 값이 로그인 화면 뒤에 남아 있지 않다.
///
/// 버려지는 것이 핵심이다. Riverpod 은 provider 를 다시 계산할 때 이전 값을
/// 로딩 상태에 실어 두므로(`AsyncLoading.valueOrNull`), 다시 계산만 하면 새
/// 계정의 응답이 오기 전까지 `valueOrNull` 로 읽는 화면에 이전 계정의 값이
/// 보인다. 버려진 provider 에는 실어 둘 이전 값이 없다.
void keepAliveForAccount(Ref<Object?> ref) {
  ref.watch(accountScopeProvider);
  if (ref.watch(accountSignedOutProvider)) return;
  ref.keepAlive();
}
