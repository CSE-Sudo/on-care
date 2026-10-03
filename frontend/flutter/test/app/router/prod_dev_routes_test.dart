/// 운영 빌드에서 개발용 경로·라우터 진단 로그가 꺼져 있는지(#3022).
///
/// 릴리스 기본값 가드가 ENV=dev 릴리스를 막는 이유가 이것이다 — `ENV=prod` 가 빠지면
/// `/dev/ui-catalog` 가 열리고 go_router 진단 로그가 돈다. 운영 설정에서 둘이 꺼짐을
/// 실제 `buildAppRouter` 로 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';

AppConfig _config(Environment environment) => AppConfig(
  environment: environment,
  apiBaseUrl: 'https://api.oncare.kr/v1',
  useMockApi: false,
);

/// 라우터 트리의 모든 GoRoute 경로(하위 경로 포함, 상대 경로는 그대로).
List<String> _paths(List<RouteBase> routes) => <String>[
  for (final RouteBase route in routes) ...<String>[
    if (route is GoRoute) route.path,
    ..._paths(route.routes),
  ],
];

void main() {
  test('운영(prod) 라우터에는 개발용 UI 카탈로그가 없다', () {
    final GoRouter router = buildAppRouter(config: _config(Environment.prod));
    addTearDown(router.dispose);

    expect(
      _paths(router.configuration.routes),
      isNot(contains(AppRoutes.uiCatalog)),
    );
  });

  test('staging·dev 라우터에는 개발용 UI 카탈로그가 있다', () {
    for (final Environment env in <Environment>[
      Environment.staging,
      Environment.dev,
    ]) {
      final GoRouter router = buildAppRouter(config: _config(env));
      addTearDown(router.dispose);

      expect(
        _paths(router.configuration.routes),
        contains(AppRoutes.uiCatalog),
        reason: env.name,
      );
    }
  });

  test('카탈로그 경로는 /dev 아래에 있다 — 운영에서 빠지는 묶음', () {
    expect(AppRoutes.uiCatalog, startsWith('/dev/'));
  });
}
