import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/storage/token_keys.dart';

/// 두 앱 토큰 키 이름공간과 옛 키 이전(#3054).
void main() {
  late Map<String, String> values;
  late TokenKeyValueAccess store;

  setUp(() {
    values = <String, String>{};
    store = TokenKeyValueAccess(
      read: (String key) async => values[key],
      write: (String key, String value) async => values[key] = value,
      delete: (String key) async => values.remove(key),
    );
  });

  group('TokenKeyspace', () {
    test('두 앱 키가 이름공간으로 갈린다', () {
      expect(TokenKeyspace.member.accessKey, 'oncare.member.access_token');
      expect(TokenKeyspace.member.refreshKey, 'oncare.member.refresh_token');
      expect(TokenKeyspace.trainer.accessKey, 'oncare.trainer.access_token');
      expect(TokenKeyspace.trainer.refreshKey, 'oncare.trainer.refresh_token');
    });

    test('어느 키도 옛 키·다른 앱 키와 겹치지 않는다', () {
      final List<String> all = <String>[
        legacyAccessTokenKey,
        legacyRefreshTokenKey,
        for (final TokenKeyspace s in TokenKeyspace.values) ...<String>[
          s.accessKey,
          s.refreshKey,
        ],
      ];
      expect(all.toSet(), hasLength(all.length));
    });
  });

  group('migrateLegacyTokenKeys', () {
    test('새 키가 비고 옛 키가 있으면 복사하고 옛 키는 남긴다', () async {
      values
        ..[legacyAccessTokenKey] = 'old-a'
        ..[legacyRefreshTokenKey] = 'old-r';

      expect(await migrateLegacyTokenKeys(store, TokenKeyspace.member), isTrue);

      // 옛 키는 어느 앱 것인지 모른다 — 역할 확인을 통과한 앱이 지운다(#3260).
      expect(values, <String, String>{
        'oncare.member.access_token': 'old-a',
        'oncare.member.refresh_token': 'old-r',
        legacyAccessTokenKey: 'old-a',
        legacyRefreshTokenKey: 'old-r',
      });
    });

    test('두 번째 실행은 아무것도 옮기지 않는다', () async {
      values
        ..[legacyAccessTokenKey] = 'old-a'
        ..[legacyRefreshTokenKey] = 'old-r';
      await migrateLegacyTokenKeys(store, TokenKeyspace.member);
      final Map<String, String> after = Map<String, String>.of(values);

      expect(
        await migrateLegacyTokenKeys(store, TokenKeyspace.member),
        isFalse,
      );
      expect(values, after);
    });

    test('새 키가 있으면 옛 키를 건드리지 않는다', () async {
      values
        ..[TokenKeyspace.member.accessKey] = 'new-a'
        ..[legacyAccessTokenKey] = 'someone-else'
        ..[legacyRefreshTokenKey] = 'someone-else-r';

      expect(
        await migrateLegacyTokenKeys(store, TokenKeyspace.member),
        isFalse,
      );
      expect(values[legacyAccessTokenKey], 'someone-else');
      expect(values[legacyRefreshTokenKey], 'someone-else-r');
      expect(values[TokenKeyspace.member.accessKey], 'new-a');
    });

    test('옛 갱신 토큰만 남아 있으면 지우기만 한다', () async {
      values[legacyRefreshTokenKey] = 'orphan';

      expect(
        await migrateLegacyTokenKeys(store, TokenKeyspace.trainer),
        isFalse,
      );
      expect(values, isEmpty);
    });

    test('옛 갱신 토큰이 없으면 접근 토큰만 옮긴다', () async {
      values[legacyAccessTokenKey] = 'old-a';

      expect(
        await migrateLegacyTokenKeys(store, TokenKeyspace.trainer),
        isTrue,
      );
      expect(values, <String, String>{
        'oncare.trainer.access_token': 'old-a',
        legacyAccessTokenKey: 'old-a',
      });
    });

    test('먼저 복사한 앱이 옛 키를 가져가지 않는다 — 주인 앱도 복사한다', () async {
      // 회원 앱 옛 토큰이 남은 탭에서 트레이너 웹이 먼저 열린 순서다(#3260).
      values
        ..[legacyAccessTokenKey] = 'member-a'
        ..[legacyRefreshTokenKey] = 'member-r';

      await migrateLegacyTokenKeys(store, TokenKeyspace.trainer);
      expect(await migrateLegacyTokenKeys(store, TokenKeyspace.member), isTrue);

      expect(values[TokenKeyspace.member.accessKey], 'member-a');
      expect(values[TokenKeyspace.member.refreshKey], 'member-r');
    });
  });

  group('deleteLegacyTokenKeys', () {
    test('옛 키 둘만 지우고 두 앱의 키는 남긴다', () async {
      values
        ..[legacyAccessTokenKey] = 'old-a'
        ..[legacyRefreshTokenKey] = 'old-r'
        ..[TokenKeyspace.member.accessKey] = 'member-a'
        ..[TokenKeyspace.trainer.accessKey] = 'trainer-a';

      await deleteLegacyTokenKeys(store);

      expect(values, <String, String>{
        TokenKeyspace.member.accessKey: 'member-a',
        TokenKeyspace.trainer.accessKey: 'trainer-a',
      });
    });

    test('지운 뒤에는 다시 복사할 것이 없다', () async {
      values
        ..[legacyAccessTokenKey] = 'old-a'
        ..[legacyRefreshTokenKey] = 'old-r';
      await migrateLegacyTokenKeys(store, TokenKeyspace.member);

      // 로그아웃: 이 앱 키와 옛 키를 함께 지운다.
      values
        ..remove(TokenKeyspace.member.accessKey)
        ..remove(TokenKeyspace.member.refreshKey);
      await deleteLegacyTokenKeys(store);

      expect(
        await migrateLegacyTokenKeys(store, TokenKeyspace.member),
        isFalse,
      );
      expect(values, isEmpty);
    });
  });
}
