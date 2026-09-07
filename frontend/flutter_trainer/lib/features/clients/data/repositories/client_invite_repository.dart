import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_member_directory.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_invite.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart'
    show readDemoUnregisteredClientIds, writeDemoUnregisteredClientIds;

/// 트레이너가 회원 ID로 회원을 찾아 담당으로 연결하는 흐름. (#919)
///
/// 지금까지 고객이 생기는 경로는 회원이 보낸 상담 요청을 트레이너가 수락하는
/// 하나뿐이라, 센터에서 먼저 등록·결제를 마친 회원을 콘솔에서 잡을 수 없었다.
/// 트레이너가 성별·나이 같은 인적 사항을 직접 입력해 새 고객을 만드는 대신,
/// 회원이 이미 자기 앱에 등록해 둔 프로필을 회원 ID로 찾아 연결한다 — 신체
/// 정보의 source of truth는 언제나 회원 본인이다.
///
/// **실 API 에서 [invite] 가 만드는 것은 요청이지 등록이 아니다.** 담당 관계는
/// 상대의 식단·건강 기록을 여는 권한이라, 회원이 회원 앱에서 수락해야 명단에
/// 나타난다 — [connectsImmediately] 가 `false`. 데모는 답할 회원 백엔드가
/// 없으므로 회원 ID가 확인되면 그 자리에서 연결한다 — [connectsImmediately]
/// 가 `true`.
///
/// 두 구현이 [clientInviteRepositoryProvider] 뒤에 있고 [AppConfig.useMockApi]
/// 로 갈린다.
abstract interface class ClientInviteRepository {
  /// 이 빌드에서 동기화 코드로 회원을 등록할 수 있는가.
  bool get supportsInvites;

  /// [invite] 가 호출 즉시 담당 링크를 만드는가(데모), 아니면 회원의 수락을
  /// 기다리는 요청만 보내는가(실 API). 화면 문구·성공 처리가 이 값으로
  /// 갈린다.
  bool get connectsImmediately;

  /// 회원을 담당으로 연결한다. 이미 담당이 있거나 이미 보냈으면
  /// [ValidationError](서버 문구를 그대로 싣는다 — 어느 쪽인지는 서버만 안다).
  Future<ClientInvite> invite(String memberId, {String? message});

  /// 코드가 가리키는 회원을 **연결하지 않고** 보여 준다. (#1634)
  ///
  /// 여섯 자리를 잘못 누르면 남의 식단·건강 기록이 열린다 — 되돌릴 수 없는
  /// 사고라, 잇기 전에 "이 고객이 맞나요?" 를 눈으로 확인시킨다. 확인만으로
  /// 코드가 사라지지는 않는다.
  ///
  /// 코드가 틀렸거나 만료됐거나 이미 쓰였으면 [NotFoundError]. 이미 담당이
  /// 있는 회원이면 [ValidationError] — 확인 화면까지 갔다가 마지막에 거절하면
  /// 무엇이 잘못됐는지 알 수 없다.
  Future<PairedMember> previewPairingCode(String code);

  /// 확인한 회원과 잇는다. 코드는 여기서 쓰인다. (#1634)
  ///
  /// [invite] 와 달리 회원의 수락을 기다리지 않는다 — 코드를 발급해 불러 준
  /// 것이 회원 본인이고 그 화면이 공유 범위를 말한다. 이미 받은 동의를 한 번
  /// 더 받을 이유가 없다.
  ///
  /// 코드가 틀렸거나 만료됐거나 이미 쓰였으면 [NotFoundError] — 셋을 갈라
  /// 알려 주지 않는다. 이미 담당이 있는 회원이면 [ValidationError].
  Future<PairedMember> redeemPairingCode(String code);

  /// 내가 보낸 요청. `status` 는 `pending` 또는 `all`. [connectsImmediately] 가
  /// `true` 인 소스는 대기할 요청이 없으므로 항상 빈 목록이다.
  Future<List<ClientInvite>> listSent({String status = 'pending'});

  /// 보낸 요청을 거둬들인다. [connectsImmediately] 가 `true` 인 소스에는
  /// 거둘 대기 요청이 없다.
  Future<void> cancel(String inviteId);
}

/// 데모: 답할 회원 백엔드가 없는 대신, 회원 ID가 확인되면 그 자리에서
/// 로컬 로스터에 연결한다 — [demoProspectiveMembers] 가 "아직 연결되지 않은
/// 회원", [demoAlreadyLinkedMemberId] 가 "이미 연결된 회원" 시나리오다.
class DemoClientInviteRepository implements ClientInviteRepository {
  DemoClientInviteRepository(this._db);

  final AppDatabase _db;

  @override
  bool get supportsInvites => true;

  @override
  bool get connectsImmediately => true;

  /// 데모 명부에서 회원 ID 로 후보를 찾는다. 화면은 회원 ID 를 묻지 않으므로
  /// 인터페이스에 두지 않는다 — 데모가 [_resolveCode] 안에서만 쓰는 규칙이다.
  Future<MemberLookup> lookup(String memberId) async {
    final String normalized = memberId.trim().toLowerCase();
    if (normalized.isEmpty) throw const NotFoundError();
    final DateTime now = nowKst();

    // demoAlreadyLinkedMemberId 는 seed-client-1(김민수)의 실 계정 id를
    // 흉내낸 값이라 그 행의 기본 키(demoAlreadyLinkedClientId)와 다르다 —
    // 여기서만 매핑한다. 다른 고객은 행의 id 자체가 곧 찾는 회원 ID다.
    final String rowId = normalized == demoAlreadyLinkedMemberId
        ? demoAlreadyLinkedClientId
        : normalized;

    final existing = await (_db.select(
      _db.trainerClients,
    )..where((t) => t.id.equals(rowId))).getSingleOrNull();
    if (existing != null) {
      final unregistered = await readDemoUnregisteredClientIds(_db);
      if (!unregistered.contains(existing.id)) {
        return _linkedLookup(normalized, existing.name);
      }
      // 담당이 해제된 기존 고객이다 — 트레이너가 신상 정보를 새로 입력하는
      // 것이 아니라, 그때 등록됐던 값 그대로 다시 등록 후보로 보여준다.
      return MemberLookup(
        memberId: normalized,
        name: existing.name,
        hasTrainer: false,
        coachedByMe: false,
        invitePending: false,
        gender: existing.gender ?? '',
        age: existing.age,
        goal: existing.goal,
      );
    }

    final prospect = findDemoProspectiveMemberById(normalized);
    if (prospect == null) throw const NotFoundError();

    return MemberLookup(
      memberId: prospect.id,
      name: prospect.name,
      hasTrainer: false,
      coachedByMe: false,
      invitePending: false,
      // 회원이 이미 자기 앱에 등록해 둔 값 — 트레이너가 등록 전에 "이 사람이
      // 맞는지" 확인할 수 있게 데모에서만 함께 실어 준다.
      gender: prospect.gender,
      age: prospect.ageOn(now),
      goal: prospect.goal,
    );
  }

  MemberLookup _linkedLookup(String memberId, String name) => MemberLookup(
    memberId: memberId,
    name: name,
    hasTrainer: true,
    coachedByMe: true,
    invitePending: false,
  );

  @override
  Future<ClientInvite> invite(String memberId, {String? message}) async {
    final String normalized = memberId.trim().toLowerCase();
    final String rowId = normalized == demoAlreadyLinkedMemberId
        ? demoAlreadyLinkedClientId
        : normalized;
    final existing = await (_db.select(
      _db.trainerClients,
    )..where((t) => t.id.equals(rowId))).getSingleOrNull();
    if (existing != null) {
      // 미등록으로 남아 있던 기존 고객이다 — 새 행을 넣으면 같은 id로
      // 기본 키가 충돌하고, 지난 루틴·채팅 이력도 새 행과 갈라진다. [lookup]
      // 이 먼저 "이미 등록됨"을 걸러내므로 여기 오는 것은 항상 미등록
      // 상태다 — 그 상태만 되돌린다.
      final unregistered = (await readDemoUnregisteredClientIds(_db))
        ..remove(existing.id);
      await writeDemoUnregisteredClientIds(_db, unregistered);
      return ClientInvite(
        id: 'demo-link-${existing.id}',
        memberId: normalized,
        memberName: existing.name,
        memberEmail: '',
        status: ClientInviteStatus.accepted,
        createdAt: nowKst(),
      );
    }

    final prospect = findDemoProspectiveMemberById(normalized);
    if (prospect == null) throw const NotFoundError();

    final DateTime now = nowKst();
    try {
      await _db
          .into(_db.trainerClients)
          .insert(
            TrainerClientsCompanion.insert(
              id: prospect.id,
              name: prospect.name,
              avatar: String.fromCharCode(prospect.name.runes.first),
              goal: prospect.goal,
              lastMessage: '아직 대화가 없어요',
              lastTime: '-',
              active: const Value(true),
              caloriesToday: 0,
              sodiumMg: 0,
              sugarG: 0,
              lastRoutine: '-',
              weekCompletionJson: '[0,0,0,0,0,0,0]',
              // 회원이 이미 등록해 둔 실제 값 — 트레이너가 지금 입력하는
              // 값이 아니다.
              gender: Value(prospect.gender),
              age: Value(prospect.ageOn(now)),
              sortOrder: Value(now.millisecondsSinceEpoch),
            ),
          );
    } catch (_) {
      // 같은 id 로 이미 연결된 행이 있는 경우 — 두 번 연결이 아니라 "이미
      // 연결됨" 으로 읽혀야 한다. lookup 이 먼저 걸러내므로 정상 경로에서는
      // 일어나지 않고, 방어적으로만 남긴다.
      throw const ValidationError();
    }

    return ClientInvite(
      id: 'demo-link-${prospect.id}',
      memberId: prospect.id,
      memberName: prospect.name,
      memberEmail: '',
      status: ClientInviteStatus.accepted,
      createdAt: now,
    );
  }

  /// 데모에는 코드를 발급하는 회원 백엔드가 없다. 명부에 박아 둔 고정 코드로
  /// 같은 흐름을 시연한다 — 화면이 실 API 와 같은 길을 지나야 한다.
  ///
  /// 조회 규칙(`lookup`)을 그대로 태운다. 이미 담당 중인지, 담당이 해제된 기존
  /// 고객인지 판단하는 자리가 둘이 되면 한쪽만 고쳐지는 날이 온다.
  Future<(String, MemberLookup)> _resolveCode(String code) async {
    final String normalized = code.replaceAll(RegExp(r'\D'), '');
    final String? memberId = resolveDemoPairingCode(normalized);
    if (memberId == null) throw const NotFoundError();

    final MemberLookup found = await lookup(memberId);
    if (!found.canInvite) {
      throw const ValidationError(message: '이미 담당하고 있는 회원이에요.');
    }
    return (memberId, found);
  }

  @override
  Future<PairedMember> previewPairingCode(String code) async {
    final (String memberId, MemberLookup found) = await _resolveCode(code);
    return PairedMember(
      memberId: memberId,
      name: found.name,
      gender: found.gender ?? '',
      age: found.age,
      goal: found.goal ?? '',
    );
  }

  @override
  Future<PairedMember> redeemPairingCode(String code) async {
    final (String memberId, MemberLookup found) = await _resolveCode(code);
    final invite = await this.invite(memberId);
    return PairedMember(
      memberId: invite.memberId,
      name: found.name,
      gender: found.gender ?? '',
      age: found.age,
      goal: found.goal ?? '',
    );
  }

  @override
  Future<List<ClientInvite>> listSent({String status = 'pending'}) async =>
      const <ClientInvite>[];

  @override
  Future<void> cancel(String inviteId) async {}
}

/// 실 백엔드 구현.
class DioClientInviteRepository implements ClientInviteRepository {
  const DioClientInviteRepository(this._dio);

  final Dio _dio;

  @override
  // Production request/accept/reject remains a follow-up. For now the
  // client-registration entry point is exposed only by the demo source.
  bool get supportsInvites => false;

  @override
  bool get connectsImmediately => false;

  @override
  Future<ClientInvite> invite(String memberId, {String? message}) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/trainer/client-invites',
        data: <String, Object?>{
          'member_id': memberId,
          if (message != null && message.trim().isNotEmpty)
            'message': message.trim(),
        },
      );
      final data = res.data;
      if (data == null) throw const ServerError();
      return ClientInvite.fromJson(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) throw const NotFoundError();
      // 409(이미 담당 중·이미 보냄)와 422(트레이너 계정)는 서버가 이유를 문장으로
      // 돌려준다. 그 문장이 트레이너가 다음에 할 일을 정하는 근거라 그대로 싣는다.
      if (status == 409 || status == 422 || status == 400) {
        throw ValidationError(message: _detail(e));
      }
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<PairedMember> previewPairingCode(String code) =>
      _postCode('/trainer/pairing-code/preview', code);

  @override
  Future<PairedMember> redeemPairingCode(String code) =>
      _postCode('/trainer/pairing-code', code);

  /// 확인과 연결은 응답도 실패 처리도 같다 — 갈라 두면 한쪽만 고쳐진다.
  Future<PairedMember> _postCode(String path, String code) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        path,
        data: <String, Object?>{'code': code.trim()},
      );
      final data = res.data;
      if (data == null) throw const ServerError();
      return PairedMember.fromJson(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 404 는 틀렸거나·만료됐거나·이미 쓰였거나 — 서버가 갈라 주지 않는다.
      if (status == 404) throw const NotFoundError();
      // 409(이미 담당 중)와 422 는 서버 문장이 트레이너가 할 일을 정한다.
      if (status == 409 || status == 422 || status == 400) {
        throw ValidationError(message: _detail(e));
      }
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<ClientInvite>> listSent({String status = 'pending'}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/trainer/client-invites',
        queryParameters: <String, Object?>{'status': status},
      );
      return (res.data ?? const <dynamic>[])
          .whereType<Map<String, Object?>>()
          .map(ClientInvite.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> cancel(String inviteId) async {
    try {
      await _dio.delete<Map<String, Object?>>(
        '/trainer/client-invites/${Uri.encodeComponent(inviteId)}',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) throw const NotFoundError();
      if (status == 409) throw ValidationError(message: _detail(e));
      throw AppError.fromDio(e);
    }
  }

  String? _detail(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final detail = data['detail'];
    return detail is String ? detail : null;
  }
}

/// 현재 모드에 맞는 저장소.
final clientInviteRepositoryProvider = Provider<ClientInviteRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return DemoClientInviteRepository(ref.watch(appDatabaseProvider));
  }
  return DioClientInviteRepository(ref.watch(dioProvider));
}, name: 'clientInviteRepository');

/// 고객 탭에 '회원 추가' 진입점을 노출할지.
final clientInvitesEnabledProvider = Provider<bool>(
  (ref) => ref.watch(clientInviteRepositoryProvider).supportsInvites,
  name: 'clientInvitesEnabled',
);

/// 내가 보낸 대기 중인 요청. 보내기·취소 뒤에는 invalidate 한다.
final pendingClientInvitesProvider =
    FutureProvider.autoDispose<List<ClientInvite>>(
      (ref) => ref.watch(clientInviteRepositoryProvider).listSent(),
      name: 'pendingClientInvites',
    );
