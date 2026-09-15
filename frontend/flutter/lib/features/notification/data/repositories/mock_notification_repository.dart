import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';

/// 데모(둘러보기)·로컬 목 모드에서 노출되는 고정 알림.
///
/// 실서비스(실로그인) 화면은 `/notifications` 백엔드를 읽지만, 데모 둘러보기는
/// 기존과 동일하게 보이도록 이 하드코딩 목록을 유지한다. 컨트롤러가 목 모드에서
/// 이 목록을 즉시 시드로 사용한다.
///
/// 각 알림은 실서버가 내려 주는 것과 같은 모양의 목적지(`action`)를 갖는다 —
/// 없으면 데모에서는 눌러도 읽음 처리만 되어, 구현돼 있는 이동 기능이 없는 것처럼
/// 보인다(#667). 목록의 생김새는 달라지지 않는다: `action` 은 그려지지 않는다.
const List<AlertItem> demoAlerts = <AlertItem>[
  // 문구의 수치는 데모 픽스처의 오늘 식단(아침·점심 짬뽕·간식) 합계와 같다.
  AlertItem(
    id: 'a1',
    title: '나트륨 섭취 주의',
    body: '점심 짬뽕으로 오늘 나트륨이 3,428mg까지 올랐어요. 물을 충분히 드세요.',
    timeAgo: '10분 전',
    category: AlertCategory.reminder,
    action: AlertAction(label: '식단 보기', target: AlertTarget.diet),
  ),
  // 오늘 식단에는 저녁이 없다 — 기록 독려는 오늘 저녁 알림이다.
  AlertItem(
    id: 'a8',
    title: '저녁 식단을 기록해 주세요',
    body: '오늘 저녁 식단이 아직 없어요. 사진 한 장이면 돼요.',
    timeAgo: '20분 전',
    category: AlertCategory.reminder,
    action: AlertAction(label: '식단 기록하기', target: AlertTarget.diet),
  ),
  // 트레이너 채팅의 `런닝 대신 걷기로 조정` 과 같은 루틴이다. 알림에서 바로 운동 탭으로 이어진다(#1812).
  AlertItem(
    id: 'a5',
    title: '새 운동 루틴이 도착했어요',
    body: '김트레이너님이 무릎 상태에 맞춰 걷기 루틴으로 조정해 보냈어요.',
    timeAgo: '30분 전',
    category: AlertCategory.reminder,
    action: AlertAction(label: '운동 보기', target: AlertTarget.exercise),
  ),
  // 주간 리포트는 트레이너 채팅의 리포트 카드로 온다 — 알림도 그 대화로 잇는다.
  // 주차는 날짜에서 계산되므로 문구에 박지 않는다.
  AlertItem(
    id: 'a7',
    title: '이번 주 리포트가 등록됐어요',
    body: '김트레이너님이 이번 주 리포트를 등록했어요.',
    timeAgo: '45분 전',
    category: AlertCategory.achievement,
    action: AlertAction(label: '리포트 보기', target: AlertTarget.coachChat),
  ),
  AlertItem(
    id: 'a2',
    title: 'PT 수업 완료',
    body: '오늘 18:00 김트레이너와 12회차 PT를 마쳤어요!',
    timeAgo: '1시간 전',
    category: AlertCategory.achievement,
    action: AlertAction(label: '운동 기록 보기', target: AlertTarget.exercise),
  ),
  AlertItem(
    id: 'a3',
    title: '트레이너 피드백 도착',
    body: '마무리로 어깨 회전근개 스트레칭을 꼭 해주세요.',
    timeAgo: '2시간 전',
    category: AlertCategory.reminder,
    action: AlertAction(label: '대화 보기', target: AlertTarget.coachChat),
  ),
  // 이번 주 운동 시간은 요일마다 달라지므로 남은 분을 숫자로 박지 않는다.
  AlertItem(
    id: 'a6',
    title: '이번 주 운동 목표까지 조금 남았어요',
    body: '저강도 유산소(걷기) 30분부터 채워 봐요.',
    timeAgo: '3시간 전',
    category: AlertCategory.reminder,
    action: AlertAction(label: '운동 보기', target: AlertTarget.exercise),
  ),
  AlertItem(
    id: 'a9',
    title: '식단 기록을 꾸준히 이어가고 있어요',
    body: '한 달 넘게 하루도 빠짐없이 식단을 기록하고 있어요.',
    timeAgo: '어제',
    category: AlertCategory.achievement,
    read: true,
    action: AlertAction(label: '홈 보기', target: AlertTarget.dashboard),
  ),
  AlertItem(
    id: 'a4',
    title: '서비스 점검 안내',
    body: '내일 02:00~03:00 점검 예정입니다.',
    timeAgo: '어제',
    category: AlertCategory.system,
    read: true,
    // 갈 곳을 일부러 주지 않는다. **목적지 없는 알림이 목록에서 사라지거나
    // 엉뚱한 곳으로 가지 않는지**를 데모에서도 볼 수 있어야 한다.
  ),
];

/// 데모/로컬 모드용 [NotificationRepository].
///
/// 목록은 [demoAlerts] 로 시작하고 읽음 처리를 **세션 동안 기억한다.** 예전에는
/// 읽음이 no-op 이라, 미읽음 수를 물으면 늘 처음 상태를 답했다 — 데모에서 "모두 읽음"
/// 을 눌러도 벨의 점이 남아, 목록과 배지가 서로 다른 말을 했다(리뷰).
class MockNotificationRepository implements NotificationRepository {
  MockNotificationRepository();

  List<AlertItem> _items = List<AlertItem>.of(demoAlerts);

  /// 데모 목록은 한 쪽 크기보다 작아 쪽을 나누지 않는다 — 커서를 무시하고 늘 전부 준다.
  /// 여기서 쪽을 흉내 내면 데모 화면이 실서버 없이 "더 보기" 를 그리게 된다.
  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async => List<AlertItem>.of(_items);

  @override
  Future<void> markRead(String id) async {
    _items = _items
        .map((AlertItem a) => a.id == id ? a.copyWith(read: true) : a)
        .toList();
  }

  @override
  Future<void> markAllRead() async {
    _items = _items.map((AlertItem a) => a.copyWith(read: true)).toList();
  }

  @override
  Future<int> unreadCount() async =>
      _items.where((AlertItem a) => !a.read).length;
}
