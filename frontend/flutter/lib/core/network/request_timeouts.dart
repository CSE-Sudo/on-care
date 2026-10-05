/// 회원 앱 요청의 시간 한도. (#3141)
///
/// 전역 한도는 `dioProvider` 의 `BaseOptions` 가 쓰고, 그보다 오래 걸리는 것이
/// 정상인 요청만 요청 단위 `Options` 로 늘린다. 값을 한곳에 두어 저장소와
/// 테스트가 같은 값을 읽는다.
library;

/// 서버에 연결하는 데 기다리는 시간.
const Duration apiConnectTimeout = Duration(seconds: 10);

/// 일반 요청의 응답을 기다리는 시간.
const Duration apiReceiveTimeout = Duration(seconds: 15);

/// 일반 요청(JSON 본문)을 보내는 데 쓰는 시간. JSON 본문은 작아 10초면 충분하다.
const Duration apiSendTimeout = Duration(seconds: 10);

/// 사진을 multipart 로 **올리는** 데 쓰는 시간.
///
/// 전역 [apiSendTimeout](10초)을 사진 업로드에도 쓰면, 헬스장 Wi-Fi·지하처럼
/// 느린 회선에서 사진을 다 보내기도 전에 요청이 끊긴다. 회원은 "분석에 실패"
/// 를 보고 다시 찍기를 되풀이하고, 그 끼니 기록은 트레이너에게 가지 않는다.
///
/// 사진 선택기는 긴 변 1600px·품질 85 로 줄여 보통 1MB 안쪽이지만, 플랫폼이
/// 그대로 넘기는 경우를 위해 8MB 까지 받는다. 1Mbps 회선에서 8MB 는 전송에만
/// 1분 남짓이라 60초를 둔다. 응답 대기 한도는 요청마다 따로 정한다(사진 분석은
/// 서버 처리 시간 때문에 더 길다).
const Duration photoUploadSendTimeout = Duration(seconds: 60);
