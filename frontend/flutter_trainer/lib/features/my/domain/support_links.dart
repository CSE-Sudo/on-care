/// 고객 지원 창구 — 카카오톡 채널. (#2227)
///
/// 회원 앱과 같은 채널을 쓴다(회원 앱 `features/my_health/domain/support_links.dart`).
/// 앱 안에 FAQ 화면을 만드는 대신 이미 운영 중인 채널로 보낸다 — 문의는 사람이
/// 답해야 하는 일이고, 그 창구는 이미 있다.
///
/// URL 을 한곳에 모아 두는 이유: 채널이 바뀌면 이 앱에서 고칠 자리가 하나여야
/// 한다.
library;

/// 카카오톡 채널 홈. FAQ·공지가 올라오는 자리.
const String kSupportChannelUrl = 'https://pf.kakao.com/_xgbkBX';

/// 채널 1:1 채팅. 문의가 곧바로 사람에게 닿는다.
const String kSupportChatUrl = 'https://pf.kakao.com/_xgbkBX/chat';
