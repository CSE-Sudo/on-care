import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';

/// 트레이너에게 불러 주는 6자리 동기화 코드. (#1634)
///
/// 예전에는 MY 탭이 `User.id`(`user-<12자리 hex>`)를 "내 회원 ID"로 보여 주고
/// 트레이너가 그것을 완전 일치로 입력했다. 마주 앉아 불러 주기에는 옮겨 적을
/// 수 있는 형태가 아니었다.
class PairingCode {
  const PairingCode({required this.code, required this.expiresInSeconds});

  /// 6자리 숫자. 앞자리 0 이 있을 수 있어 문자열로 다룬다.
  final String code;

  /// 발급 응답 시점 기준 남은 초. **서버가 센 값이다** — 만료 시각만 받아 기기
  /// 시계로 빼면 시계가 어긋난 기기에서 카운트다운이 엉뚱해진다.
  final int expiresInSeconds;

  factory PairingCode.fromJson(Map<String, Object?> json) => PairingCode(
    code: (json['code'] as String?) ?? '',
    expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 0,
  );
}

/// 동기화 코드 발급·취소.
///
/// 목업 모드에서도 같은 구현을 쓴다 — [LocalApiInterceptor] 가 같은 경로를
/// 받아 준다. 저장소를 둘로 나누면 데모와 실서비스의 흐름이 갈린다.
class TrainerSyncRepository {
  const TrainerSyncRepository(this._dio);

  final Dio _dio;

  /// 코드를 발급한다. **이 호출이 데이터 공유 동의다** — 코드를 쓴 트레이너는
  /// 그 자리에서 담당이 되어 식단·운동·건강 기록을 읽는다. 화면이 그 범위를
  /// 말한 뒤에 부른다.
  ///
  /// 유효한 코드가 남아 있으면 서버가 그것을 그대로 돌려준다.
  Future<PairingCode> issue() async {
    final res = await _dio.post<Map<String, Object?>>('/users/me/pairing-code');
    final data = res.data;
    if (data == null) throw StateError('연결 코드 응답이 비어 있습니다.');
    return PairingCode.fromJson(data);
  }

  /// 띄워 둔 코드를 버린다. 화면을 닫으면 부른다 — 발급이 동의였으니 취소도
  /// 즉시 반영돼야 한다.
  Future<void> revoke() async {
    await _dio.delete<void>('/users/me/pairing-code');
  }
}

final trainerSyncRepositoryProvider = Provider<TrainerSyncRepository>(
  (ref) => TrainerSyncRepository(ref.watch(dioProvider)),
  name: 'trainerSyncRepository',
);
