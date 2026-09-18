import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';

class MockMyHealthRepository implements MyHealthRepository {
  /// [points] 를 주면 잔액을 목업 포인트 원장에서 읽는다(#1786) — 데모에서 식단·
  /// 운동을 기록하면 MY 잔액이 따라 오른다. 없으면 시작 잔액 그대로다.
  const MockMyHealthRepository({this.points});

  final DemoPointsLedger? points;

  @override
  Future<MyHealthState> fetchState() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return MyHealthState(
      // 트레이너웹 데모의 김민수(`seed-client-1`)와 같은 사람이고, 여기 적힌
      // 값은 이 계정의 **실제 id** 다 — 로그인·채팅·운동 픽스처가 모두 같은
      // 값을 쓴다. 트레이너웹의 "회원 ID로 신규 고객 등록" 데모가 인식하는
      // `demoAlreadyLinkedMemberId` 와도 같은 값이라, 두 데모를 오가며 같은
      // ID 가 그대로 통한다.
      //
      // 예전에는 계정 id 가 `user-demo` 여서 이 화면만 복잡한 형태를 흉내낸
      // 다른 값을 보여 줬다. 실 서비스 회원 ID 는 `user-<12자리 hex>` 라 추측할
      // 수 없는 값인데 `user-demo` 는 그 감이 오지 않았고, 화면이 보여 주는
      // 값과 실제 계정 id 가 다르다는 사실을 아는 사람이 없으면 헷갈렸다.
      // 계정 id 자체를 그 형태로 바꾸면서 둘이 다시 하나가 됐다 (#1279).
      profile: const UserProfile(
        name: '김민수',
        email: 'minsu@oncare.com',
        id: 'user-7d4e9a2c5f18',
      ),
      risk: const RiskAlert(
        title: '이번 주 관리 포인트',
        body: '식단·운동 기록을 꾸준히 이어 가면 트레이너가 더 정확하게 도와줄 수 있어요.',
        level: RiskLevel.medium,
      ),
      activityPoints: points?.balance ?? kDemoOpeningPoints,
      activityRank: 14,
      settings: const <SettingsItem>[
        SettingsItem(
          label: '내 프로필',
          icon: '👤',
          kind: SettingsKind.myProfile,
        ),
        SettingsItem(
          label: '알림 설정',
          icon: '🔔',
          kind: SettingsKind.notification,
        ),
        SettingsItem(
          label: '고객 지원',
          icon: '💬',
          kind: SettingsKind.support,
        ),
      ],
    );
  }
}
