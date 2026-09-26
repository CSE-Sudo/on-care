part of 'seed_data.dart';

/// The demo roster: fifteen members whose numbers actually move.
///
/// A demo roster is a fixture for the *charts*, not just the list. Three
/// clients with mild, similar weeks left most of the console's states
/// unreachable by clicking around: nothing was ever empty, nothing ever
/// collapsed, no sparkline ever spiked, and the 확인 필요 고객 card never
/// had to say "+N명". So these are built as a spread across the states
/// the UI can render, not as fifteen plausible-looking averages.
///
/// 목록·차트가 읽는 규칙:
///  * 회원 목록의 **주간 이행률 막대**는 `weekCompletion` 중 **0 이 아닌 날**만
///    평균한다(`recordedCompletionMean`) — 0 은 "기록 없음" 이지 실패가 아니다.
///    하루만 잘 기록한 회원이 실패로 보이지 않게 하는 비대칭이라 눈으로 틀리기
///    쉽고, 절반쯤의 회원이 이것을 붙잡아 두려고 있다. 기록이 없으면 `미집계`.
///  * 식단 차트(칼로리·나트륨·당류)는 주간 계열을 그대로 그린다.
///  * 배지(필터·상세·대시보드)는 수치에서 계산하지 않는다 — 서버가 계산하는
///    PT 관리 신호라 데모는 회원마다 `signals` 로 정해 둔다(아래).
///
/// 수치를 고칠 때 지켜야 하는 두 가지:
///
///  * **오늘 값과 주간 계열의 마지막 원소는 같은 하루다.** 한쪽만 고치면 카드의
///    숫자와 그래프의 오른쪽 끝이 갈린다.
///  * **목표(`goal`)와 수치가 같은 이야기를 해야 한다.** 벌크업 회원의 칼로리가
///    높은 것은 문제가 아니라 연료다. 나트륨 ÷ 칼로리는 1.5mg/kcal 을 넘지
///    않는다 — 그 위는 국물만 먹어야 나오는 값이다. 아래로는 제한이 없다
///    (현미·닭가슴살 위주의 3,000kcal 는 0.6 근처가 정상이다).
///  * **답장 대기는 스레드가 정한다** — 마지막 말이 회원 것이면 안읽음이다.
///
/// Coverage this is meant to guarantee, by client (수치의 모양 → PT 관리 신호):
///  1  김민수    톱니형 이행률, 나트륨 높음 → 칼로리 과다
///  2  이지수    주말만 미기록 → 신호 없음(대조군)
///  3  박성호    휴면, 기록 거의 없음 → 신호 없음(휴면은 서버처럼 계산 안 함)
///  4  정하윤    V자 — 무너졌다 회복 → 운동 목표 미달
///  5  최우진    완벽 — 7일 100%, 칼로리 높음(지구력 훈련자의 연료, #768)
///              → 신호 없음(대조군)
///  6  강서연    주말 붕괴 — 평일 완벽, 주말 나트륨 폭등 → 칼로리 과다·단백질 부족
///              (체중 감량 목표)
///  7  임도현    신규 — 식단·기록·추이 전부 비어 있음 → 기록 끊김
///  8  오세라    급성 악화 — 나트륨 우상향, 이행률 우하향, 답장 대기 →
///              통증·불편(대화에 허리 통증)·운동 목표 미달·칼로리 과다
///  9  배준혁    야근형 — 이행률 낮음, 답장 대기 → 노쇼·취소 반복·배정 루틴 미수행
///  10 신유나    회복 중 — 나트륨 우하향, 이행률 우상향 → 신호 없음
///  11 한지호    정체기 — 목표선 위아래로 진동(경계값) → 운동 목표 미달
///  12 문가영    휴면 — 주 3일치만 기록되고 끊김(짧은 스파크라인) → 신호 없음
///  13 류태경    극단 — 0↔100, 1200↔3200 지그재그(최대 진폭), 벌크업 →
///              단백질 부족(근력 향상 목표)
///  14 백서진    운동은 완벽한데 나트륨만 높음 → 신호 없음
///  15 노은채    단 하루만 기록(단일 포인트 스파크라인) → 기록 끊김
///
/// PT 관리 신호(`signals`, #2204)는 회원의 이야기와 맞춘다 — 단백질 부족은
/// 근력 향상·체중 감량 회원에게만, 휴면 회원(박성호·문가영)은 서버처럼 신호가
/// 없다. 여덟 가지 배지가 모두 한 번은 보이게 고른다(답장 대기는 스레드가
/// 정한다).
const List<_Client> _clients = <_Client>[
  _Client(
    id: 1,
    name: '김민수',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.calorieOff, percent: 18, over: true),
    ],
    avatar: '김',
    goal: '체중 감량 · 혈압 관리',
    // 목록 미리보기는 스레드의 마지막 메시지 **그대로**여야 한다. 전에는 대화에
    // 없는 문구('오늘 식단 전송됐어요')가 떴고, 그 다음에는 마지막 메시지의
    // 중간 토막을 잘라 써서 목록과 대화의 첫 마디가 서로 달랐다. 길이는 카드가
    // 알아서 줄임표로 자른다 — 여기서 미리 자르면 안 된다.
    daysAgo: 0,
    active: true,
    // 김민수의 수치는 **여기에 없다.** 그는 사용자 앱의 데모 계정(`user-7d4e9a2c5f18`)과
    // 같은 사람이라 두 앱을 나란히 놓고 시연하는데, 각자 만들면 같은 날짜의 숫자가
    // 어긋난다(#757). 하루 합계·요일별 계열·끼니·운동 이력은 공유 픽스처
    // (`shared/demo_fixture`)가 정하고 `seed_data.dart` 가 그걸 읽어 넣는다.
    //
    // 그래서 아래 필드는 비워 둔다 — 값을 남겨 두면 어느 쪽이 진짜인지 알 수 없고,
    // 한쪽만 고쳤을 때 조용히 갈린다. 나머지 고객은 예전대로 이 파일이 정한다.
    calories: 0,
    sodiumMg: 0,
    sugarG: 0,
    lastRoutine: '오늘',
    weekCompletion: <int>[],
    sodiumWeek: <int>[],
    caloriesWeek: <int>[],
    sugarWeek: <double>[],
    diet: <_Meal>[],
    // 개인 운동도 픽스처가 정한다 (#1170) — 식단·이력과 같은 규칙이라 여기는
    // 비워 두고 `seed_data.dart` 가 채운다. 예전에는 여기에 손으로 적어 두어,
    // 같은 회원의 같은 목록을 회원 앱·고객 탭·프로그램 탭이 서로 다르게 말했다.
    aiRoutine: <_Routine>[],
    // 운동 이력도 픽스처가 정한다. 예전에는 날짜 라벨이 `'7/12 (오늘)'` 로 박혀
    // 있어 데모를 언제 열든 7월 12일이 "오늘"이었다.
    history: <_History>[],
    // 김민수는 회원 앱 데모 사용자(user-7d4e9a2c5f18)와 같은 사람이라, 이 스레드는
    // 두 앱에 같은 대화로 보여야 한다. 같은 목록이
    // `frontend/flutter/lib/features/member_coach/data/repositories/mock_member_coach_repository.dart`
    // (회원 시점)와 `backend/app/db/seed_member_data.py::_CHAT` (실서버 시드)에
    // 도 있다 — 한 곳만 고치면 각 파일의 테스트가 깨진다.
    //
    // **이미 진행 중인** 코칭의 한 토막이다. 김민수는 PT 12회차를 지난 회원이라
    // 첫 인사로 시작하면 앱의 다른 화면(운동 이력·AI 코치 카드)과 어긋난다.
    //
    // 대화의 근거는 픽스처의 숫자다 — 이번 주 이행률이 화·목에 떨어져 있고(화 50·
    // 목 67), 그게 "화·목에 야근"이라는 답과 맞물린다. 픽스처의 주차별 이야기를
    // 손볼 때 이 대화도 함께 읽을 것.
    //
    // 요일별 나트륨 mg 은 여전히 인용하지 않는다(목표 2,000mg 만 인용). 이제는 두
    // 앱이 같은 수치를 보지만, 그 수치는 데모를 여는 요일에 따라 달라진다 —
    // 대화에 숫자를 박으면 어떤 날에는 화면과 어긋난다.
    chat: <_Chat>[
      // 1일차.
      _Chat(
        'trainer',
        '민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?',
        '화 10:02',
      ),
      _Chat('client', '화요일이랑 목요일이 야근이 많아요 😥', '화 10:15'),
      _Chat(
        'trainer',
        '그럼 그 이틀은 15분짜리 짧은 프로그램으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다',
        '화 10:21',
      ),
      _Chat('client', '그 정도면 퇴근하고도 할 수 있을 것 같아요', '화 10:24'),
      _Chat('trainer', '혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요', '화 10:26'),
      _Chat('client', '네, 아침 8시 그대로예요', '화 10:29'),
      _Chat('trainer', '확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂', '화 10:34'),
      // 2일차.
      _Chat(
        'trainer',
        '민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?',
        '수 09:30',
        dayIndex: 1,
      ),
      _Chat('client', '회사 구내식당이라 국물이 늘 나와요 😅', '수 12:40', dayIndex: 1),
      _Chat(
        'trainer',
        '국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠',
        '수 12:52',
        dayIndex: 1,
      ),
      _Chat('client', '오늘은 국물 안 마셨어요! 걷기도 25분 했습니다', '수 19:05', dayIndex: 1),
      _Chat('trainer', '좋아요 👏 그 한 가지만 지켜도 추이가 달라져요', '수 19:20', dayIndex: 1),
      _Chat(
        'trainer',
        '내일 프로그램은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요',
        '수 19:22',
        dayIndex: 1,
      ),
      // 3일차.
      _Chat(
        'trainer',
        '민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?',
        '18:10',
        dayIndex: 2,
      ),
      _Chat('client', '찌개 먹을 때 국물을 많이 마셨나봐요 😅', '18:13', dayIndex: 2),
      _Chat(
        'trainer',
        '그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?',
        '18:14',
        dayIndex: 2,
      ),
      _Chat('client', '무릎이 가볍게 당기긴 했는데 괜찮아요', '18:16', dayIndex: 2),
      // 회원 앱 시드와 같은 자리에 같은 문구로 둔다. 마지막 인사 **앞**이다 —
      // 스레드 맨 끝 메시지는 고객 목록의 미리보기로 쓰인다.
      _Chat(
        'trainer',
        '이번 주 리포트 등록해 뒀어요. 확인해 보세요',
        '18:17',
        dayIndex: 2,
        report: true,
      ),
      _Chat(
        'trainer',
        '확인했어요. AI가 오늘 식단 기반으로 유산소 프로그램을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪',
        '18:18',
        dayIndex: 2,
      ),
    ],
  ),
  _Client(
    id: 2,
    name: '이지수',
    avatar: '이',
    goal: '체중 감량 · 체력 강화',
    daysAgo: 0,
    active: true,
    calories: 1680,
    sodiumMg: 1800,
    sugarG: 38,
    lastRoutine: '어제',
    weekCompletion: <int>[67, 100, 100, 100, 100, 0, 0],
    sodiumWeek: <int>[1700, 1950, 1600, 1800, 2100, 1750, 1800],
    caloriesWeek: <int>[1600, 1760, 1380, 1850, 1560, 1480, 1680],
    sugarWeek: <double>[36.1, 39.9, 31.2, 41.8, 35.3, 33.4, 38.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('그릭요거트', 180, 190, 6), _Food('블루베리', 100, 10, 9)],
        carbsG: 40,
        proteinG: 15,
        fatG: 6,
      ),
      _Meal.of(
        '점심',
        <_Food>[
          _Food('현미밥', 310, 5, 0.5),
          _Food('불고기', 330, 720, 9),
          _Food('시금치나물', 110, 255, 1.5),
        ],
        carbsG: 90,
        proteinG: 35,
        fatG: 20,
        photoAsset: 'assets/images/lunch-bulgogi-brown-rice.jpg',
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('연어 샐러드', 650, 620, 12)],
        carbsG: 25,
        proteinG: 45,
        fatG: 40,
        photoAsset: 'assets/images/diet-salmon-brown-rice.jpeg',
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('인터벌 런닝', 25, '유산소', '체지방 연소 효율↑'),
      _Routine('스쿼트', 15, '근력', '하체 근력 강화'),
      _Routine('플랭크', 10, '근력', '코어 안정화'),
    ],
    history: <_History>[
      _History(
        daysAgo: 1,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          '인터벌 런닝 25분 ✓',
          '스쿼트 3세트 · 12회 · 40kg ✓',
          '플랭크 3세트 · 3회 · 0kg ✓',
        ],
        clientFeedback: '런닝이 힘들었는데 다 했어요! 숨이 많이 찼어요',
        trainerNote: '심폐지구력 향상 중. 다음 주 런닝 강도 소폭 올릴 예정.',
      ),
      _History(
        daysAgo: 3,
        label: 'PT 세션 · 트레이너 지도',
        completionRate: 100,
        exercises: <String>[
          '데드리프트 3세트 · 8회 · 55kg',
          '런지 3세트 · 12회 · 10kg',
          '코어 서킷 2세트 · 12회 · 0kg',
        ],
        clientFeedback: '데드리프트 자세 교정 도움 많이 됐어요!',
        trainerNote: '',
      ),
      _History(
        daysAgo: 5,
        label: 'AI 개인운동',
        completionRate: 67,
        exercises: <String>['런닝 25분 ✓', '스쿼트 ✓', '플랭크 ✗ (피로)'],
        clientFeedback: '마지막 플랭크는 너무 지쳐서 못 했어요',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat(
        'trainer',
        '지수님, AI 운동 데이터 수신했어요 — 오늘 인터벌 런닝 25분 완료! 컨디션은 어때요?',
        '20:05',
      ),
      _Chat('client', '생각보다 괜찮았어요. 숨이 금방 차더라고요 😮‍💨', '20:08'),
      _Chat(
        'trainer',
        '심폐 지구력 올라가는 과정이에요 💪 AI 분석 보니까 당류는 목표 안에 있고, 프로그램 다음 주부터 근력 비중 늘려볼게요. 식단도 AI 추천 참고해서 업데이트해 드릴게요',
        '20:10',
      ),
    ],
  ),
  _Client(
    id: 3,
    name: '박성호',
    avatar: '박',
    goal: '근력 향상',
    daysAgo: 3,
    active: false,
    calories: 2100,
    sodiumMg: 2400,
    sugarG: 55,
    lastRoutine: '5일 전',
    weekCompletion: <int>[0, 33, 100, 0, 0, 0, 0],
    sodiumWeek: <int>[2600, 2500, 2300, 2450, 2200, 2550, 2400],
    caloriesWeek: <int>[2200, 1720, 2310, 1950, 1850, 2000, 2100],
    sugarWeek: <double>[57.8, 45.1, 60.5, 51.2, 48.4, 52.2, 55.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('삶은 계란 3개', 230, 210, 1), _Food('잼 토스트', 250, 310, 12)],
        carbsG: 35,
        proteinG: 28,
        fatG: 24,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('짜장면', 890, 1200, 26)],
        carbsG: 120,
        proteinG: 25,
        fatG: 30,
        photoAsset: 'assets/images/lunch-jjajangmyeon.jpg',
      ),
      _Meal.of(
        '저녁',
        <_Food>[
          _Food('삼겹살', 590, 260, 0.5),
          _Food('쌈채소', 40, 20, 2.5),
          _Food('쌈장', 100, 400, 13),
        ],
        carbsG: 20,
        proteinG: 45,
        fatG: 50,
        photoAsset: 'assets/images/dinner-samgyeopsal-ssam.jpg',
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('벤치프레스', 20, '근력', '상체 근력 목표'),
      _Routine('데드리프트', 15, '근력', '전신 근력 향상'),
      _Routine('유산소 쿨다운', 10, '유산소', '나트륨 배출 지원'),
    ],
    history: <_History>[
      _History(
        daysAgo: 5,
        label: 'PT 세션 · 트레이너 지도',
        completionRate: 100,
        exercises: <String>[
          '벤치프레스 4세트 · 8회 · 65kg',
          '인클라인 덤벨 3세트 · 10회 · 26kg',
          '트라이셉스 딥 3세트 · 12회 · 0kg',
        ],
        clientFeedback: '가슴이 많이 타는 느낌이었어요. 좋았어요!',
        trainerNote: '벤치 중량 62.5kg → 65kg 도전 가능. 다음 PT 때 시도 예정.',
      ),
      _History(
        daysAgo: 7,
        label: 'AI 개인운동',
        completionRate: 33,
        exercises: <String>['벤치프레스 ✓', '데드리프트 ✗', '유산소 ✗'],
        clientFeedback: '회사 일이 생겨서 벤치만 하고 나왔어요',
        trainerNote: '',
      ),
      _History(
        daysAgo: 9,
        label: 'AI 개인운동',
        completionRate: 0,
        exercises: <String>['벤치프레스 ✗', '데드리프트 ✗', '유산소 ✗'],
        clientFeedback: '못 갔어요 😓',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '성호님, 이번 주 운동 기록이 AI 쪽에서 안 잡히는데 몸은 괜찮으세요?', '월 09:00'),
      _Chat('client', '이번 주 일이 너무 많아서 못 갔어요 😓', '월 09:03'),
      _Chat(
        'trainer',
        '이해해요! 대신 AI 식단 분석 보니까 나트륨이 좀 높더라고요. 주말에 30분 걷기라도 하면 도움 돼요. AI가 그에 맞는 프로그램 다시 짜줬으니까 앱에서 확인해보세요 🙂',
        '월 09:07',
      ),
    ],
  ),

  // --- V자 회복: 무너졌다가 되돌아온 주 -------------------------------
  _Client(
    id: 4,
    name: '정하윤',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.exerciseGoalLow, percent: 45),
    ],
    avatar: '정',
    goal: '체력 강화 · 재활',
    daysAgo: 0,
    active: true,
    calories: 1520,
    sodiumMg: 1650,
    sugarG: 32,
    lastRoutine: '오늘',
    // 주 중반에 완전히 끊겼다가 후반에 되돌아온다 — 막대가 V를 그린다.
    weekCompletion: <int>[100, 25, 0, 0, 50, 100, 100],
    // 나트륨도 같이 급락했다 반등: 외식이 끊긴 구간이 그대로 보인다.
    sodiumWeek: <int>[2900, 2600, 1500, 1250, 1400, 1900, 1650],
    caloriesWeek: <int>[1250, 1670, 1410, 1340, 1440, 1600, 1520],
    sugarWeek: <double>[26.2, 35.2, 29.8, 28.2, 30.4, 33.6, 32.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('통밀토스트', 190, 270, 3), _Food('아보카도', 150, 20, 0.5)],
        carbsG: 30,
        proteinG: 8,
        fatG: 20,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('닭가슴살 도시락', 520, 640, 9.5)],
        carbsG: 60,
        proteinG: 42,
        fatG: 12,
      ),
      _Meal.of(
        '저녁',
        <_Food>[
          _Food('채소 스프', 150, 480, 14),
          _Food('두부', 220, 230, 4.5),
          _Food('현미밥', 290, 10, 0.5),
        ],
        carbsG: 90,
        proteinG: 28,
        fatG: 21,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('저강도 걷기', 25, '유산소', '회복기 심박 관리'),
      _Routine('골반 안정화', 15, '스트레칭', '산후 코어 재활'),
      _Routine('밴드 로우', 12, '근력', '상체 자세 교정'),
    ],
    history: <_History>[
      _History(
        daysAgo: 0,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          '걷기 25분 ✓',
          '골반 안정화 15분 ✓',
          '밴드 로우 3세트 · 15회 · 0kg ✓',
        ],
        clientFeedback: '컨디션 돌아온 게 느껴져요. 다 했습니다!',
        trainerNote: '2주 공백 후 복귀 성공. 다음 주부터 강도 10% 상향.',
      ),
      _History(
        daysAgo: 3,
        label: 'AI 개인운동',
        completionRate: 50,
        exercises: <String>['걷기 25분 ✓', '골반 안정화 ✗ (아이 컨디션)'],
        clientFeedback: '아이가 아파서 절반만 했어요',
        trainerNote: '',
      ),
      _History(
        daysAgo: 6,
        label: 'AI 개인운동',
        completionRate: 0,
        exercises: <String>['걷기 ✗', '골반 안정화 ✗', '밴드 로우 ✗'],
        clientFeedback: '한 주 통째로 쉬었어요',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '하윤님, 지난주 공백 뒤에 오늘 세 개 다 채우셨네요 👏', '14:20'),
      _Chat('client', '몸이 다시 붙는 느낌이에요. 나트륨도 신경 썼어요!', '14:26'),
      _Chat('trainer', '추이 보니 확실히 내려왔어요. 이 페이스로 한 주만 더 가보죠 🙂', '14:31'),
    ],
  ),

  // --- 대조군: 알림이 하나도 없는 고객 --------------------------------
  _Client(
    id: 5,
    name: '최우진',
    avatar: '최',
    goal: '체력 강화',
    daysAgo: 1,
    active: true,
    calories: 2600,
    sodiumMg: 1450,
    sugarG: 34.0,
    lastRoutine: '오늘',
    weekCompletion: <int>[100, 100, 100, 100, 100, 100, 100],
    // 거의 평평한 스파크라인 — 목표선 근처에서 흔들리는 다른 고객과 대비된다.
    sodiumWeek: <int>[1520, 1450, 1380, 1410, 1470, 1330, 1450],
    caloriesWeek: <int>[2480, 2610, 2540, 2660, 2720, 2390, 2600],
    sugarWeek: <double>[35.4, 32.5, 30.4, 33.9, 36.1, 29.0, 34.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[
          _Food('오트밀', 260, 160, 1),
          _Food('바나나', 110, 0, 6),
          _Food('견과', 150, 30, 1),
        ],
        carbsG: 72,
        proteinG: 15,
        fatG: 19,
        photoAsset: 'assets/images/diet-oatmeal-banana.jpeg',
      ),
      _Meal.of(
        '점심',
        <_Food>[
          _Food('현미밥', 330, 10, 0.5),
          _Food('흰살생선', 300, 340, 0),
          _Food('나물', 150, 250, 0.5),
        ],
        carbsG: 105,
        proteinG: 47,
        fatG: 19,
      ),
      _Meal.of(
        '저녁',
        <_Food>[
          _Food('닭가슴살', 230, 150, 0),
          _Food('고구마', 170, 30, 4),
          _Food('파스타', 500, 380, 3),
        ],
        carbsG: 122,
        proteinG: 56,
        fatG: 20,
      ),
      _Meal.of(
        '간식',
        <_Food>[_Food('스포츠음료', 180, 90, 12), _Food('바나나 2개', 220, 10, 6)],
        carbsG: 95,
        proteinG: 3,
        fatG: 1,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('LSD 러닝', 45, '유산소', '유산소 기반 다지기'),
      _Routine('힙 힌지 드릴', 12, '근력', '러닝 이코노미 개선'),
      _Routine('종아리 스트레칭', 10, '스트레칭', '부상 예방'),
    ],
    history: <_History>[
      _History(
        daysAgo: 0,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          'LSD 러닝 45분 ✓',
          '힙 힌지 3세트 · 12회 · 0kg ✓',
          '스트레칭 10분 ✓',
        ],
        clientFeedback: '페이스 안정적이었어요',
        trainerNote: '7일 연속 100%. 과훈련 신호 없는지 다음 주 확인.',
      ),
      _History(
        daysAgo: 1,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          '인터벌 러닝 30분 ✓',
          '코어 서킷 3세트 · 12회 · 0kg ✓',
          '스트레칭 ✓',
        ],
        clientFeedback: '인터벌 끝나고 다리가 후들거렸어요 😅',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '우진님, 이번 주 7일 전부 100% 나왔어요. 무리는 없으세요?', '21:00'),
      _Chat('client', '아직은 괜찮아요! 주말 장거리만 잘 넘기면 될 것 같아요', '21:04'),
      _Chat('trainer', '좋아요. 대신 수요일은 회복 프로그램으로 잡아둘게요 🙂', '21:06'),
    ],
  ),

  // --- 주말 붕괴형: 평일과 주말이 완전히 다른 사람 ---------------------
  _Client(
    id: 6,
    name: '강서연',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.calorieOff, percent: 22, over: true),
      ClientSignal(ClientSignalKind.proteinLow, percent: 64),
    ],
    avatar: '강',
    goal: '체중 감량',
    daysAgo: 0,
    active: true,
    calories: 2260,
    sodiumMg: 2750,
    sugarG: 74.0,
    lastRoutine: '금요일',
    // 평일 완벽, 주말 0 — 막대가 절벽처럼 끊긴다.
    weekCompletion: <int>[100, 100, 100, 100, 100, 0, 0],
    // 같은 주말에 나트륨이 두 배로 뛴다.
    sodiumWeek: <int>[1400, 1350, 1500, 1420, 1380, 3100, 2750],
    caloriesWeek: <int>[2100, 1990, 2150, 2370, 1850, 2490, 2260],
    sugarWeek: <double>[63.2, 59.8, 64.6, 71.4, 55.8, 78.8, 74.0],
    diet: <_Meal>[
      // 아침은 걸렀다 — 거른 끼니는 카드를 만들지 않는다(#1381).
      _Meal.of(
        '점심',
        <_Food>[_Food('마라탕', 980, 1850, 18)],
        carbsG: 90,
        proteinG: 35,
        fatG: 52,
        photoAsset: 'assets/images/lunch-malatang.jpg',
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('치킨', 960, 870, 48), _Food('맥주', 320, 30, 8)],
        carbsG: 95,
        proteinG: 60,
        fatG: 72,
        photoAsset: 'assets/images/dinner-fried-chicken-beer.jpg',
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('주말 회복 걷기', 30, '유산소', '주말 나트륨 배출'),
      _Routine('전신 서킷', 20, '근력', '평일 프로그램 유지'),
      _Routine('상체 스트레칭', 10, '스트레칭', '피로 해소'),
    ],
    history: <_History>[
      _History(
        daysAgo: 1,
        label: 'AI 개인운동',
        completionRate: 0,
        exercises: <String>['걷기 ✗', '전신 서킷 ✗', '스트레칭 ✗'],
        clientFeedback: '주말은 약속이 계속 있었어요 😅',
        trainerNote: '평일 100% / 주말 0% 패턴 5주째. 주말용 15분 프로그램으로 분리 검토.',
      ),
      _History(
        daysAgo: 3,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          '전신 서킷 4세트 · 12회 · 0kg ✓',
          '걷기 30분 ✓',
          '스트레칭 10분 ✓',
        ],
        clientFeedback: '평일엔 프로그램대로 잘 되고 있어요',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '서연님, 평일은 완벽한데 주말에 나트륨이 3100까지 올라갔어요', '16:40'),
      _Chat('client', '주말엔 약속이 많아서요 😅 마라탕이 문제였나봐요', '16:45'),
      _Chat(
        'trainer',
        '주말만 따로 15분짜리 가벼운 프로그램으로 잡아드릴게요. 안 하는 것보다 훨씬 나아요 🙂',
        '16:48',
      ),
    ],
  ),

  // --- 신규: 아직 아무 데이터도 없는 고객 (빈 상태 검증) ----------------
  _Client(
    id: 7,
    name: '임도현',
    signals: <ClientSignal>[ClientSignal(ClientSignalKind.recordGap, days: 4)],
    avatar: '임',
    goal: '자세 교정',
    daysAgo: 0,
    active: true,
    calories: 0,
    sodiumMg: 0,
    sugarG: 0,
    lastRoutine: '-',
    // 기록이 하나도 없다. `isLowCompletion` 이 0 만 있는 주를 실패로 세지
    // 않는다는 규칙이 여기서 눈으로 확인된다 — 배지가 뜨면 안 된다.
    weekCompletion: <int>[0, 0, 0, 0, 0, 0, 0],
    sodiumWeek: <int>[],
    caloriesWeek: <int>[],
    sugarWeek: <double>[],
    diet: <_Meal>[],
    aiRoutine: <_Routine>[
      _Routine('체력 측정 걷기', 20, '유산소', '기초 체력 파악'),
      _Routine('맨몸 스쿼트', 10, '근력', '하체 기준선 측정'),
      _Routine('전신 스트레칭', 10, '스트레칭', '가동범위 확인'),
    ],
    history: <_History>[],
    chat: <_Chat>[],
  ),

  // --- 급성 악화: 모든 지표가 같은 방향으로 나빠진다 --------------------
  _Client(
    id: 8,
    name: '오세라',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.discomfort),
      ClientSignal(ClientSignalKind.exerciseGoalLow, percent: 28),
      ClientSignal(ClientSignalKind.calorieOff, percent: 24, over: true),
    ],
    avatar: '오',
    goal: '혈압 관리',
    daysAgo: 1,
    active: true,
    calories: 2480,
    sodiumMg: 3250,
    sugarG: 61.0,
    lastRoutine: '6일 전',
    // 이행률은 계단식으로 떨어지고…
    weekCompletion: <int>[80, 60, 40, 33, 20, 0, 0],
    // …나트륨은 같은 기간 계속 올라간다. 두 그래프가 정확히 반대로 간다.
    sodiumWeek: <int>[1900, 2150, 2400, 2650, 2900, 3050, 3250],
    caloriesWeek: <int>[2360, 2600, 2030, 2730, 2310, 2180, 2480],
    sugarWeek: <double>[58.9, 62.1, 51.2, 64.2, 56.3, 59.2, 61.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('편의점 삼각김밥 2개', 420, 780, 6)],
        carbsG: 80,
        proteinG: 10,
        fatG: 6,
        photoAsset: 'assets/images/breakfast-onigiri.jpg',
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('부대찌개', 620, 1640, 9), _Food('공기밥', 300, 10, 0)],
        carbsG: 110,
        proteinG: 40,
        fatG: 34,
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('족발', 700, 780, 30), _Food('소주', 440, 40, 16)],
        carbsG: 62,
        proteinG: 66,
        fatG: 70,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('저강도 걷기', 20, '유산소', '혈압 우선 안정'),
      _Routine('호흡 이완', 10, '스트레칭', '교감신경 완화'),
      _Routine('의자 스쿼트', 8, '근력', '최소 부하로 재시작'),
    ],
    history: <_History>[
      _History(
        daysAgo: 4,
        label: 'AI 개인운동',
        completionRate: 20,
        exercises: <String>['걷기 ✓ (10분만)', '호흡 이완 ✗', '의자 스쿼트 ✗'],
        clientFeedback: '10분 걷다가 회사에서 전화 와서 끊었어요',
        trainerNote: '나트륨 3000 돌파 + 이행률 20%. 이번 주 안에 전화 상담 필요.',
      ),
      _History(
        daysAgo: 6,
        label: 'AI 개인운동',
        completionRate: 33,
        exercises: <String>['걷기 ✓', '호흡 이완 ✗', '의자 스쿼트 ✗'],
        clientFeedback: '피곤해서 걷기만 했어요',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '세라님, 나트륨이 6일 연속 올라서 3250까지 왔어요. 혈압은 재보셨어요?', '09:10'),
      // `허리도 좀 아프고요` 는 목록의 `통증·불편` 배지가 가리키는 말이다(#2204).
      // 서버는 이런 회원 문장에서 통증을 찾아 신호를 싣고, 데모는 시드가 신호를
      // 정하므로 근거를 대화에 둔다. 새 줄로 넣지 않는 이유: 안읽음 수가 바뀐다.
      _Chat('client', '요즘 너무 바빠서 못 하고 있어요. 허리도 좀 아프고요', '09:34'),
      _Chat('client', '주말엔 꼭 재볼게요...', '09:35'),
    ],
  ),

  // --- 야근형: 이행률이 낮고 나트륨이 널뛴다 ---------------------------
  _Client(
    id: 9,
    name: '배준혁',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.noShow, count: 2),
      ClientSignal(ClientSignalKind.routineMissed, days: 3),
    ],
    avatar: '배',
    goal: '체력 강화 · 운동 습관',
    daysAgo: 0,
    active: true,
    calories: 2050,
    sodiumMg: 2280,
    sugarG: 47,
    lastRoutine: '4일 전',
    // 0 이 아닌 날 평균 36% — 주간 이행률 막대가 낮게 그려지는 쪽.
    weekCompletion: <int>[50, 0, 33, 0, 25, 0, 0],
    // 야근 여부에 따라 위아래로 튄다.
    sodiumWeek: <int>[2100, 2600, 1800, 2900, 2200, 1600, 2280],
    caloriesWeek: <int>[2150, 1680, 2260, 1910, 1800, 1950, 2050],
    sugarWeek: <double>[49.4, 38.5, 51.7, 43.7, 41.4, 44.6, 47.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('아메리카노', 20, 10, 0)],
        carbsG: 3,
        proteinG: 1,
        fatG: 0.5,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('김치찌개', 480, 1410, 7), _Food('공기밥', 300, 10, 0)],
        carbsG: 103,
        proteinG: 31,
        fatG: 27,
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('편의점 도시락', 750, 700, 12), _Food('크림빵 2개', 500, 150, 28)],
        carbsG: 150,
        proteinG: 45,
        fatG: 51,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('퇴근 후 걷기', 15, '유산소', '짧게라도 유지'),
      _Routine('목·어깨 스트레칭', 10, '스트레칭', '장시간 착석 보완'),
      _Routine('플랭크', 5, '근력', '최소 코어 유지'),
    ],
    history: <_History>[
      _History(
        daysAgo: 2,
        label: 'AI 개인운동',
        completionRate: 25,
        exercises: <String>['목·어깨 스트레칭 ✓', '걷기 ✗', '플랭크 ✗'],
        clientFeedback: '자기 전에 스트레칭만 겨우 했어요',
        trainerNote: '15분 프로그램도 못 채우는 주가 반복. 5분 버전으로 낮춰볼 것.',
      ),
      _History(
        daysAgo: 4,
        label: 'AI 개인운동',
        completionRate: 33,
        exercises: <String>['걷기 15분 ✓', '스트레칭 ✗', '플랭크 ✗'],
        clientFeedback: '',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '준혁님, 이번 주도 야근이 이어지네요. 5분짜리로 줄여볼까요?', '19:50'),
      _Chat('client', '오늘도 야근이라 못 갈 것 같아요', '20:12'),
    ],
  ),

  // --- 회복 중: 나쁜 데서 좋은 쪽으로 -----------------------------------
  _Client(
    id: 10,
    name: '신유나',
    avatar: '신',
    goal: '재활',
    daysAgo: 0,
    active: true,
    calories: 1590,
    sodiumMg: 1720,
    sugarG: 35,
    lastRoutine: '오늘',
    // 주 초반 공백 → 후반 완주. 우상향 계단.
    weekCompletion: <int>[0, 0, 33, 67, 100, 100, 100],
    // 나트륨은 반대로 꾸준히 내려온다.
    sodiumWeek: <int>[2800, 2500, 2200, 1950, 1800, 1750, 1720],
    caloriesWeek: <int>[1300, 1750, 1480, 1400, 1510, 1670, 1590],
    sugarWeek: <double>[28.7, 38.5, 32.6, 30.8, 33.2, 36.8, 35.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('두유', 130, 110, 8), _Food('삶은 계란 2개', 130, 130, 0.5)],
        carbsG: 14,
        proteinG: 18,
        fatG: 14,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('비빔밥 (고추장 절반)', 680, 780, 14)],
        carbsG: 100,
        proteinG: 22,
        fatG: 20,
        photoAsset: 'assets/images/diet-vegetable-bibimbap.jpg',
      ),
      _Meal.of(
        '저녁',
        <_Food>[
          _Food('샐러드', 120, 380, 11.5),
          _Food('닭가슴살', 230, 300, 0.5),
          _Food('현미밥', 300, 20, 0.5),
        ],
        carbsG: 70,
        proteinG: 45,
        fatG: 20,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('실내 자전거', 20, '유산소', '무릎 부담 없는 유산소'),
      _Routine('레그 익스텐션', 12, '근력', '대퇴사두 재건'),
      _Routine('무릎 가동범위', 10, '스트레칭', '재활 프로토콜'),
    ],
    history: <_History>[
      _History(
        daysAgo: 0,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          '실내 자전거 20분 ✓',
          '레그 익스텐션 3세트 · 12회 · 20kg ✓',
          '가동범위 10분 ✓',
        ],
        clientFeedback: '무릎 통증 없이 다 했어요!',
        trainerNote: '3주 연속 개선. 다음 주 러닝머신 걷기 추가 검토.',
      ),
      _History(
        daysAgo: 2,
        label: 'AI 개인운동',
        completionRate: 67,
        exercises: <String>['실내 자전거 ✓', '레그 익스텐션 ✓', '가동범위 ✗'],
        clientFeedback: '마지막에 시간이 부족했어요',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '유나님, 나트륨 추이가 2800에서 1700까지 내려왔어요 👏', '13:15'),
      _Chat('client', '이번 주는 다 지켰어요 :)', '13:22'),
      _Chat('trainer', '무릎 상태 괜찮으면 다음 주에 걷기 조금 얹어볼게요', '13:25'),
    ],
  ),

  // --- 정체기: 목표선 위아래로만 진동 (경계값) -------------------------
  _Client(
    id: 11,
    name: '한지호',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.exerciseGoalLow, percent: 48),
    ],
    avatar: '한',
    goal: '식습관 개선 · 운동 습관',
    daysAgo: 1,
    active: true,
    calories: 1880,
    sodiumMg: 2010,
    sugarG: 50.0,
    lastRoutine: '어제',
    // 매일 같은 값 — 완전히 평평한 막대.
    weekCompletion: <int>[67, 67, 67, 67, 67, 67, 67],
    // 목표선(2000) 바로 위아래에서만 흔들린다. 경계 판정 확인용.
    sodiumWeek: <int>[1990, 2010, 1995, 2005, 1998, 2015, 2010],
    caloriesWeek: <int>[2070, 1750, 1650, 1790, 1970, 1540, 1880],
    sugarWeek: <double>[55.0, 46.5, 44.0, 47.5, 52.5, 41.0, 50.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('시리얼', 250, 220, 15), _Food('우유', 130, 100, 10)],
        carbsG: 64,
        proteinG: 12,
        fatG: 8,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('백반 정식', 720, 980, 21)],
        carbsG: 100,
        proteinG: 30,
        fatG: 22,
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('된장찌개', 480, 700, 4), _Food('공기밥', 300, 10, 0)],
        carbsG: 105,
        proteinG: 30,
        fatG: 25,
        photoAsset: 'assets/images/diet-doenjang-rice.jpeg',
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('트레드밀 경사 걷기', 25, '유산소', '정체 구간 자극 변화'),
      _Routine('풀업 어시스트', 12, '근력', '상체 자극 전환'),
      _Routine('전신 스트레칭', 10, '스트레칭', '회복'),
    ],
    history: <_History>[
      _History(
        daysAgo: 1,
        label: 'AI 개인운동',
        completionRate: 67,
        exercises: <String>['경사 걷기 ✓', '풀업 어시스트 ✓', '스트레칭 ✗'],
        clientFeedback: '늘 하던 만큼 했어요',
        trainerNote: '7주째 같은 이행률·같은 나트륨. 자극 변화 필요.',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '지호님, 몇 주째 수치가 거의 안 움직여요. 프로그램을 좀 바꿔볼까요?', '22:00'),
      _Chat('client', '똑같은 것 같아요', '22:11'),
      _Chat('trainer', '다음 주는 경사·중량 쪽으로 자극을 바꿔서 보내드릴게요 🙂', '22:14'),
    ],
  ),

  // --- 휴면: 주 중반에 기록이 끊겼다 (짧은 스파크라인) ------------------
  _Client(
    id: 12,
    name: '문가영',
    avatar: '문',
    goal: '체력 강화',
    daysAgo: 21,
    active: false,
    calories: 770,
    sodiumMg: 1030,
    sugarG: 29,
    lastRoutine: '3주 전',
    // 0 이 아닌 날이 하나(33%)뿐 — 막대는 그 하루의 33% 로 그려진다.
    weekCompletion: <int>[33, 0, 0, 0, 0, 0, 0],
    // 3일치만 남기고 끊긴다. 7개 미만 스파크라인 렌더링 확인용.
    sodiumWeek: <int>[2100, 1950, 1030],
    caloriesWeek: <int>[1350, 1420, 770],
    sugarWeek: <double>[23.8, 31.9, 29.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('토스트', 240, 300, 9), _Food('커피', 50, 10, 5)],
        carbsG: 40,
        proteinG: 8,
        fatG: 10,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('샌드위치', 480, 720, 15)],
        carbsG: 55,
        proteinG: 20,
        fatG: 20,
      ),
      // 저녁은 기록하지 않았다 — 빈 끼니 카드를 만들지 않는다(#1381).
    ],
    aiRoutine: <_Routine>[
      _Routine('가벼운 걷기', 20, '유산소', '복귀 준비'),
      _Routine('전신 스트레칭', 15, '스트레칭', '휴식기 스트레칭 유지'),
      _Routine('맨몸 스쿼트', 8, '근력', '최소 근력 유지'),
    ],
    history: <_History>[
      _History(
        daysAgo: 21,
        label: 'AI 개인운동',
        completionRate: 33,
        exercises: <String>['걷기 20분 ✓', '스트레칭 ✗', '스쿼트 ✗'],
        clientFeedback: '당분간 쉬려고요',
        trainerNote: '3주째 기록 없음. 휴면 전환. 복귀 의사 확인 필요.',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '가영님, 3주째 기록이 없어서요. 복귀 계획 있으실까요?', '6/21 10:00'),
      _Chat('client', '당분간 쉬려고요', '6/21 12:40'),
    ],
  ),

  // --- 극단 변동: 최대 진폭 --------------------------------------------
  _Client(
    id: 13,
    name: '류태경',
    signals: <ClientSignal>[
      ClientSignal(ClientSignalKind.proteinLow, percent: 71),
    ],
    avatar: '류',
    goal: '근력 향상 · 식습관 개선',
    daysAgo: 0,
    active: true,
    calories: 3120,
    sodiumMg: 1950,
    sugarG: 42.0,
    lastRoutine: '오늘',
    // 하루 걸러 전부 또는 전무 — 막대가 톱니로 꽂힌다.
    weekCompletion: <int>[100, 0, 100, 0, 100, 0, 0],
    // 1200 ↔ 3200. 스파크라인 최대 진폭 케이스.
    sodiumWeek: <int>[1200, 3100, 1350, 2950, 1100, 1880, 1950],
    caloriesWeek: <int>[2750, 2960, 3280, 2560, 3430, 2900, 3120],
    sugarWeek: <double>[48.1, 44.5, 46.5, 41.6, 49.1, 43.6, 42.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('계란 5개', 390, 340, 1.5), _Food('오트밀', 330, 140, 1.5)],
        carbsG: 60,
        proteinG: 45,
        fatG: 34,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('소고기 덮밥', 780, 700, 14), _Food('현미밥 곱빼기', 400, 20, 1)],
        carbsG: 170,
        proteinG: 55,
        fatG: 32,
      ),
      _Meal.of(
        '저녁',
        <_Food>[
          _Food('닭가슴살', 460, 600, 0),
          _Food('고구마', 400, 60, 20),
          _Food('프로틴', 360, 90, 4),
        ],
        carbsG: 145,
        proteinG: 108,
        fatG: 22,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('스쿼트', 25, '근력', '하체 볼륨 확보'),
      _Routine('벤치프레스', 25, '근력', '상체 볼륨 확보'),
      _Routine('유산소 쿨다운', 10, '유산소', '나트륨 배출'),
    ],
    history: <_History>[
      _History(
        daysAgo: 0,
        label: 'PT 세션 · 트레이너 지도',
        completionRate: 100,
        exercises: <String>[
          '스쿼트 5세트 · 8회 · 80kg',
          '벤치프레스 5세트 · 8회 · 60kg',
          '유산소 쿨다운 10분',
        ],
        clientFeedback: '오늘은 제대로 했습니다',
        trainerNote: '하는 날과 안 하는 날 편차가 큼. 주 4회 고정 스케줄 제안.',
      ),
      _History(
        daysAgo: 1,
        label: 'AI 개인운동',
        completionRate: 0,
        exercises: <String>['스쿼트 ✗', '벤치프레스 ✗', '쿨다운 ✗'],
        clientFeedback: '어제는 아예 못 갔어요',
        trainerNote: '',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '태경님, 하는 날은 100%인데 격일로 완전히 비네요', '11:20'),
      _Chat('client', '오늘은 제대로 했습니다', '11:48'),
      _Chat('client', '근데 식단은 자신이 없네요 😅', '11:49'),
    ],
  ),

  // --- 운동은 완벽, 나트륨만 계속 초과 ---------------------------------
  _Client(
    id: 14,
    name: '백서진',
    avatar: '백',
    goal: '식습관 개선',
    daysAgo: 1,
    active: true,
    calories: 1920,
    sodiumMg: 2680,
    sugarG: 44,
    lastRoutine: '오늘',
    // 운동은 흠잡을 데가 없다.
    weekCompletion: <int>[100, 100, 100, 100, 100, 100, 100],
    // 그런데 나트륨은 7일 내내 목표선 위 — 높은 자리에서 평평하다.
    sodiumWeek: <int>[2400, 2550, 2700, 2600, 2800, 2650, 2680],
    caloriesWeek: <int>[1820, 2020, 1570, 2110, 1790, 1690, 1920],
    sugarWeek: <double>[41.8, 46.2, 36.1, 48.4, 40.9, 38.7, 44.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('북엇국', 220, 1110, 2), _Food('공기밥', 300, 10, 0)],
        carbsG: 82,
        proteinG: 23,
        fatG: 10,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('칼국수', 790, 980, 5), _Food('겉절이', 90, 280, 9)],
        carbsG: 133,
        proteinG: 31,
        fatG: 25,
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('닭가슴살 샐러드', 400, 260, 8), _Food('오렌지주스', 120, 40, 20)],
        carbsG: 30,
        proteinG: 50,
        fatG: 22,
        photoAsset: 'assets/images/diet-chicken-salad.jpg',
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('러닝머신', 30, '유산소', '나트륨 배출 지원'),
      _Routine('전신 근력 서킷', 25, '근력', '현 프로그램 유지'),
      _Routine('스트레칭', 10, '스트레칭', '회복'),
    ],
    history: <_History>[
      _History(
        daysAgo: 0,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>['러닝머신 30분 ✓', '근력 서킷 25분 ✓', '스트레칭 10분 ✓'],
        clientFeedback: '운동은 빠짐없이 하고 있어요',
        trainerNote: '이행률 100%인데 나트륨 7일 연속 초과. 식단 상담으로 전환.',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '서진님, 운동은 7일 다 채우셨어요. 다만 나트륨이 계속 2500 위예요', '20:30'),
      _Chat('client', '국물을 못 끊겠어요', '20:41'),
      _Chat('trainer', '국물만 절반 남기셔도 400~500은 빠져요. 그것부터 해보죠 🙂', '20:44'),
    ],
  ),

  // --- 단 하루만 기록 (단일 포인트 스파크라인) --------------------------
  _Client(
    id: 15,
    name: '노은채',
    signals: <ClientSignal>[ClientSignal(ClientSignalKind.recordGap, days: 6)],
    avatar: '노',
    goal: '운동 습관',
    daysAgo: 1,
    active: true,
    calories: 1280,
    sodiumMg: 1450,
    sugarG: 18,
    lastRoutine: '어제',
    // 하루만 100%. 0 인 날은 세지 않으므로 평균 100 — 배지가 뜨면 안 된다.
    weekCompletion: <int>[100, 0, 0, 0, 0, 0, 0],
    // 측정값이 하나뿐인 스파크라인.
    sodiumWeek: <int>[1450],
    caloriesWeek: <int>[1280],
    sugarWeek: <double>[18.0],
    diet: <_Meal>[
      _Meal.of(
        '아침',
        <_Food>[_Food('바나나', 100, 10, 5), _Food('우유', 120, 120, 4)],
        carbsG: 35,
        proteinG: 8,
        fatG: 5,
      ),
      _Meal.of(
        '점심',
        <_Food>[_Food('샐러드 볼', 430, 610, 5)],
        carbsG: 42,
        proteinG: 16,
        fatG: 22,
      ),
      _Meal.of(
        '저녁',
        <_Food>[_Food('두부 스테이크', 330, 700, 3.5), _Food('잡곡밥', 300, 10, 0.5)],
        carbsG: 80,
        proteinG: 30,
        fatG: 20,
      ),
    ],
    aiRoutine: <_Routine>[
      _Routine('걷기', 20, '유산소', '습관 형성 우선'),
      _Routine('맨몸 스쿼트', 8, '근력', '부담 없는 시작'),
      _Routine('전신 스트레칭', 10, '스트레칭', '운동 후 회복'),
    ],
    history: <_History>[
      _History(
        daysAgo: 1,
        label: 'AI 개인운동',
        completionRate: 100,
        exercises: <String>[
          '걷기 20분 ✓',
          '맨몸 스쿼트 3세트 · 15회 · 0kg ✓',
          '스트레칭 10분 ✓',
        ],
        clientFeedback: '첫 운동 했어요! 생각보다 할 만했어요',
        trainerNote: '첫 기록. 다음 주까지 주 3회 유지가 목표.',
      ),
    ],
    chat: <_Chat>[
      _Chat('trainer', '은채님, 첫 프로그램 완주 축하해요 🎉', '18:00'),
      _Chat('client', '첫 운동 했어요!', '18:05'),
      _Chat('trainer', '이번 주는 3번만 채워보죠. 무리 안 하는 게 더 중요해요 🙂', '18:07'),
    ],
  ),
];
