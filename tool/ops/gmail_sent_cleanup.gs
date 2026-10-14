/**
 * On-Care 운영 메일 사본 정리 — 발송 30일이 지난 사본을 영구 삭제한다(#3443).
 *
 * 운영 서버는 가입 인증 코드·비밀번호 재설정·이메일 변경 안내를 Gmail SMTP
 * (sudo.capstone@gmail.com)로 보낸다. Gmail 은 SMTP 로 보낸 메일도 발신 계정의
 * 보낸편지함에 사본을 남기고 서버는 이를 막을 수 없다. 처리방침 7항 ⑤는 이 사본을
 * "발송일로부터 30일" 이 지나면 지운다고 알린다. 이 스크립트가 그 약속을 지킨다.
 * 원본 표: docs/privacy_processing.md 1절 Gmail 행·"운영 메모".
 *
 * 지우는 것 (둘 다 30일이 지난 것만)
 *   1. SENT 라벨이 붙은 메시지 중 제목이 "[On-Care] " 로 시작하는 것 — 서버가 보낸
 *      메일의 제목은 모두 이 머리로 시작한다(backend/tests/test_privacy_policy_version.py
 *      가 이를 지킨다). 팀원이 손으로 보낸 답장(문의 응대 기록)은 지우지 않는다.
 *   2. mailer-daemon 이 돌려보낸 발송 실패 알림 — 원래 메일(받는 사람 주소·코드)을
 *      본문에 담고 받은편지함에 들어오므로 같은 기간으로 지운다.
 * 받은 메일·답장은 건드리지 않는다. 스레드 단위(GmailApp.moveThreadsToTrash)로 지우면
 * 같은 스레드의 받은 답장까지 지워지므로 메시지 단위로 고른다.
 *
 * 영구 삭제를 고른 이유: 휴지통으로 옮기면 Gmail 이 30일을 더 보관해 최대 60일이
 * 된다. 고급 서비스의 batchDelete 는 휴지통을 거치지 않고 바로 지운다. 대신 권한이
 * 가장 넓은 https://mail.google.com/ 범위가 필요하다(Gmail API 에서 영구 삭제를
 * 허용하는 유일한 범위). 이 계정 주인만 실행하는 스크립트라 받아들인다.
 *
 * 설치 (발신 계정 sudo.capstone@gmail.com 으로 로그인한 상태에서)
 *   1. https://script.google.com → 새 프로젝트. 이름은 "On-Care 메일 사본 정리".
 *   2. 이 파일 내용을 Code.gs 에 붙여 넣는다.
 *   3. 왼쪽 "서비스" + → "Gmail API" 추가(식별자 Gmail).
 *   4. 함수 previewOnCareMailCleanup 을 한 번 실행해 권한을 승인한다("확인되지 않은
 *      앱" 경고는 본인 스크립트라 고급 → 이동). 실행 로그에서 지울 개수를 확인한다.
 *   5. 왼쪽 "트리거"(시계) → 트리거 추가 → 함수 cleanupOnCareMail, 시간 기반,
 *      일 단위 타이머, 원하는 시간대. 실패 알림은 "매일" 로 받는다.
 * 트리거가 빠지면 처리방침의 30일 약속이 깨진다. 계정 비밀번호를 바꾸거나 권한을
 * 철회한 뒤에는 script.google.com → 이 프로젝트 → 트리거에서 살아 있는지 본다.
 */

var RETENTION_DAYS = 30;
var SUBJECT_PREFIX = '[On-Care] ';
// 한 번에 다 못 지우면(실행 시간 6분 한도) 다음 날 실행이 이어서 지운다.
var MAX_PER_RUN = 2000;

/** 트리거가 매일 부르는 함수. 고른 메시지를 영구 삭제한다. */
function cleanupOnCareMail() {
  var ids = collectTargets_();
  for (var i = 0; i < ids.length; i += 1000) {
    Gmail.Users.Messages.batchDelete({ ids: ids.slice(i, i + 1000) }, 'me');
  }
  console.log('On-Care 메일 사본 ' + ids.length + '건 영구 삭제');
}

/** 지우지 않고 대상 개수만 로그에 남긴다. 처음 권한 승인과 점검에 쓴다. */
function previewOnCareMailCleanup() {
  console.log('지울 대상 ' + collectTargets_().length + '건(삭제하지 않음)');
}

function collectTargets_() {
  var older = 'older_than:' + RETENTION_DAYS + 'd';
  var sent = collect_({ labelIds: ['SENT'], q: older }, function (h) {
    return (h.Subject || '').indexOf(SUBJECT_PREFIX) === 0;
  });
  var bounces = collect_(
    { q: 'from:mailer-daemon ' + older, includeSpamTrash: true },
    function (h) {
      return /mailer-daemon@/i.test(h.From || '');
    }
  );
  return sent.concat(bounces).slice(0, MAX_PER_RUN);
}

/** 검색에 걸린 메시지 중 머리글이 keep 을 통과한 것의 id. */
function collect_(query, keep) {
  var ids = [];
  var pageToken = null;
  do {
    var params = { maxResults: 500 };
    for (var key in query) params[key] = query[key];
    if (pageToken) params.pageToken = pageToken;
    var page = Gmail.Users.Messages.list('me', params);
    var messages = page.messages || [];
    for (var i = 0; i < messages.length && ids.length < MAX_PER_RUN; i++) {
      var msg = Gmail.Users.Messages.get('me', messages[i].id, {
        format: 'metadata',
        metadataHeaders: ['Subject', 'From'],
      });
      var headers = {};
      (msg.payload.headers || []).forEach(function (h) {
        headers[h.name] = h.value;
      });
      if (keep(headers)) ids.push(messages[i].id);
    }
    pageToken = ids.length < MAX_PER_RUN ? page.nextPageToken : null;
  } while (pageToken);
  return ids;
}
