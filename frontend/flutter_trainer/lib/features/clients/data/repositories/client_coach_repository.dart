import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';

/// AI 코칭 상담의 답변 한 건. (#497)
class ClientCoachAnswer {
  /// Creates an answer.
  const ClientCoachAnswer({
    required this.reply,
    this.sources = const <String>[],
  });

  /// AI 가 만든 답변.
  final String reply;

  /// 답의 근거로 쓰인 문서 제목.
  ///
  /// 근거 없이 답만 보여 주면 트레이너가 그 말을 믿어도 되는지 판단할 수 없다.
  /// 이 목록이 비어 있을 수도 있다 — 회원 기록만으로 답한 경우다.
  final List<String> sources;
}

/// 담당 회원에 대해 AI 에게 묻는다 — `POST /trainer/clients/{id}/ai-coach`.
///
/// 회원 앱의 `/ai-coach/chat` 과 같은 RAG 파이프라인이지만 **검색 스코프가
/// 담당 회원**이다. 트레이너가 자기 자신의(비어 있는) 기록으로 코칭받는 일이
/// 없도록 서버가 그렇게 짜여 있다.
///
/// 두 구현이 [clientCoachRepositoryProvider] 뒤에 있고 `useMockApi` 로 갈린다.
///
///  * [DemoClientCoachRepository] — 데모. 근거로 삼을 회원 데이터가 없다.
///  * [DioClientCoachRepository] — 실 백엔드.
abstract interface class ClientCoachRepository {
  /// 이 빌드가 실제로 물어볼 수 있는가.
  ///
  /// 데모에는 근거가 될 회원 기록이 없어, 무엇을 물어도 의미 있는 답이 나오지
  /// 않는다. 진입점 노출 여부를 이 값으로 정한다 — 눌러도 소용없는 버튼을
  /// 두느니 보이지 않는 편이 낫고, 데모 화면도 지금 그대로 남는다.
  bool get supportsAsk;

  /// [memberId] 회원에 대해 [message] 를 묻고 답을 받는다.
  Future<ClientCoachAnswer> ask({
    required String memberId,
    required String message,
  });

  /// 이 트레이너가 [memberId] 회원에 대해 나눈 문답을 오래된 순으로 복원한다. (#588)
  ///
  /// 시트를 닫았다 열면 대화가 사라지던 문제를 없앤다. 서버가 스레드를
  /// (회원, 트레이너) 로 가르므로 다른 트레이너의 문답은 오지 않는다.
  Future<List<ClientCoachTurn>> history({required String memberId});
}

/// 복원된 문답 한 줄. (#588)
class ClientCoachTurn {
  /// Creates a turn.
  const ClientCoachTurn({
    required this.isTrainer,
    required this.content,
    this.sources = const <String>[],
  });

  /// 트레이너가 물은 줄인가(아니면 AI 답변).
  final bool isTrainer;

  /// 질문 또는 답변 본문.
  final String content;

  /// 답변의 근거 문서 제목. 질문 줄에서는 비어 있다.
  final List<String> sources;
}

/// 데모 빌드: 물어볼 근거가 없다.
class DemoClientCoachRepository implements ClientCoachRepository {
  /// Creates the demo source.
  const DemoClientCoachRepository();

  @override
  bool get supportsAsk => false;

  @override
  Future<ClientCoachAnswer> ask({
    required String memberId,
    required String message,
  }) async =>
      // 문구는 화면이 붙인다 — 리포지토리는 로케일을 모른다. (#501)
      throw const ValidationError();

  @override
  Future<List<ClientCoachTurn>> history({required String memberId}) async =>
      // 물어볼 수 없는 빌드라 남은 문답도 없다. 빈 목록이 정확한 답이고, 여기서
      // throw 하면 시트가 열리자마자 오류를 띄운다.
      const <ClientCoachTurn>[];
}

/// 실 백엔드 구현.
class DioClientCoachRepository implements ClientCoachRepository {
  /// Creates the API-backed repository.
  const DioClientCoachRepository(this._dio);

  final Dio _dio;

  @override
  bool get supportsAsk => true;

  @override
  Future<ClientCoachAnswer> ask({
    required String memberId,
    required String message,
  }) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(memberId)}/ai-coach',
        data: <String, Object?>{'message': message},
      );
      final body = res.data ?? const <String, Object?>{};
      return ClientCoachAnswer(
        reply: body['reply'] is String ? body['reply']! as String : '',
        sources: <String>[
          for (final Object? item
              in body['sources'] as List<Object?>? ?? const <Object?>[])
            if (item is String && item.trim().isNotEmpty) item.trim(),
        ],
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 404 는 '남의 고객'이다 — 서버가 존재조차 드러내지 않는다. 트레이너에게는
      // 담당이 아니라는 사실이 필요한 정보다.
      if (status == 404) {
        // 문구는 화면이 붙인다 — 리포지토리는 로케일을 모른다. (#501)
        throw const NotFoundError();
      }
      if (status == 400 || status == 422) {
        throw ValidationError(message: _detail(e));
      }
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<ClientCoachTurn>> history({required String memberId}) async {
    try {
      final res = await _dio.get<List<Object?>>(
        '/trainer/clients/${Uri.encodeComponent(memberId)}/ai-coach',
      );
      return <ClientCoachTurn>[
        for (final Object? row in res.data ?? const <Object?>[])
          if (row is Map<String, Object?>)
            ClientCoachTurn(
              // 서버 저장값은 user|coach 다. 트레이너가 물은 줄이 'user'.
              isTrainer: row['role'] == 'user',
              content: row['content'] is String
                  ? row['content']! as String
                  : '',
              sources: _stringList(row['sources']),
            ),
      ];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const NotFoundError();
      throw AppError.fromDio(e);
    }
  }

  List<String> _stringList(Object? value) => <String>[
    if (value is List<Object?>)
      for (final Object? item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
  ];

  String? _detail(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final detail = data['detail'];
    return detail is String ? detail : null;
  }
}

/// 현재 모드에 맞는 저장소.
final clientCoachRepositoryProvider = Provider<ClientCoachRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return const DemoClientCoachRepository();
  }
  return DioClientCoachRepository(ref.watch(dioProvider));
}, name: 'clientCoachRepository');

/// 고객 상세에 'AI 에게 묻기' 를 노출할지.
final clientCoachEnabledProvider = Provider<bool>(
  (ref) => ref.watch(clientCoachRepositoryProvider).supportsAsk,
  name: 'clientCoachEnabled',
);
