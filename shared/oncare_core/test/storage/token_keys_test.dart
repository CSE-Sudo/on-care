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
    test('새 키가 비고 옛 키가 있으면 옮기고 옛 키를 지운다', () async {
      values
        ..[legacyAccessTokenKey] = 'old-a'
        ..[legacyRefreshTokenKey] = 'old-r';

      expect(await migrateLegacyTokenKeys(store, TokenKeyspace.member), isTrue);

      expect(values, <String, String>{
        'oncare.member.access_token': 'old-a',
        'oncare.member.refresh_token': 'old-r',
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
      expect(values, <String, String>{'oncare.trainer.access_token': 'old-a'});
    });

    test('한 앱이 옮겨 간 옛 토큰을 다른 앱이 다시 옮기지 않는다', () async {
      values
        ..[legacyAccessTokenKey] = 'old-a'
        ..[legacyRefreshTokenKey] = 'old-r';

      await migrateLegacyTokenKeys(store, TokenKeyspace.member);
      expect(
        await migrateLegacyTokenKeys(store, TokenKeyspace.trainer),
        isFalse,
      );
      expect(values.containsKey(TokenKeyspace.trainer.accessKey), isFalse);
    });
  });
}
