import 'package:demo_fixture/demo_fixture.dart';

/// 데모 회원별 4주 추천 메뉴 리스트(#2667).
///
/// 실서버는 회원마다 최근 4주 기록과 목표로 리스트를 따로 만든다
/// (`diet_menu_plan`). 데모는 모든 회원이 같은 [kDemoMenuPlan] 을 순서만 바꿔
/// 썼다 — 누구를 열어도 AI 식단 추천의 메뉴가 같았다.
///
/// 리스트의 모양(끼니별 칸 수·칸마다의 추천 이유 태그·키워드)은 [kDemoMenuPlan]
/// 과 같고, 칸마다 메뉴만 회원에 따라 바꾼다. 김민수(`seed-client-1`)는 회원
/// 앱 데모와 같은 사람이라 공유 리스트를 그대로 쓴다.
List<DemoPlanMenu> demoMenuPlanFor(String clientId) {
  const List<DemoPlanMenu> base = kDemoMenuPlan;
  final int? n = int.tryParse(clientId.replaceFirst('seed-client-', ''));
  if (n == null || n <= 1) return base;
  return <DemoPlanMenu>[
    for (var i = 0; i < base.length; i++)
      if (i < _alternatives.length)
        _choose(
          base[i],
          _alternatives[i],
          (n * 31 + i * 17) ^ (n * i + n ~/ 2),
        )
      else
        base[i],
  ];
}

/// 칸 [cell] 의 메뉴 중 [seed] 번째(나머지). 0 번은 공유 리스트의 메뉴 그대로다.
///
/// [seed] 는 회원과 칸을 섞은 값이다 — 회원 번호에 칸 번호만 더하면 세 명마다
/// 같은 리스트가 되풀이된다.
DemoPlanMenu _choose(
  DemoPlanMenu cell,
  List<String> alternatives,
  int seed,
) {
  final int pick = seed % (alternatives.length + 1);
  if (pick == 0) return cell;
  return (
    slot: cell.slot,
    name: alternatives[pick - 1],
    tag: cell.tag,
    keyword: cell.keyword,
  );
}

/// [kDemoMenuPlan] 의 칸 순서대로 둔 다른 메뉴 두 가지. 이름 길이는 서버 한도
/// (`NAME_MAX`: 한국어 12자) 안이다. 칸의 추천 이유(고단백·저나트륨
/// …)에 맞는 메뉴만 둔다.
const List<List<String>> _alternatives =
    <List<String>>[
      // 아침
      <String>[
        '달걀 흰자 오믈렛',
        '닭가슴살 샌드위치',
      ],
      <String>[
        '고구마와 우유',
        '삶은 달걀과 사과',
      ],
      <String>[
        '아보카도 통밀빵',
        '귀리 베리 볼',
      ],
      <String>[
        '토마토 달걀볶음',
        '채소 수프',
      ],
      <String>[
        '두부 스크램블',
        '두유와 견과',
      ],
      // 점심
      <String>[
        '연어 포케',
        '소고기 곤약덮밥',
      ],
      <String>[
        '닭가슴살 현미밥',
        '구운 채소 파스타',
      ],
      <String>[
        '보리밥 쌈 정식',
        '렌틸콩 샐러드',
      ],
      <String>[
        '곤약면 샐러드',
        '두부 포케',
      ],
      <String>[
        '현미 닭가슴살 김밥',
        '버섯 두부덮밥',
      ],
      // 저녁
      <String>[
        '닭가슴살 스테이크',
        '연어 구이 정식',
      ],
      <String>[
        '흰살생선 찜',
        '닭안심 채소볶음',
      ],
      <String>[
        '현미밥과 버섯볶음',
        '콩나물 잡곡밥',
      ],
      <String>[
        '채소 샤브샤브',
        '해산물 샐러드',
      ],
      <String>[
        '소고기 채소볶음',
        '고등어 쌈밥',
      ],
      // 간식
      <String>[
        '삶은 달걀',
        '프로틴 쉐이크',
      ],
      <String>[
        '오이 스틱',
        '사과 반쪽',
      ],
      <String>[
        '아몬드 한 줌',
        '치즈 한 장',
      ],
    ];
