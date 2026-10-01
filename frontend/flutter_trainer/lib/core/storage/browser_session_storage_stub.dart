import 'package:oncare_trainer/core/storage/token_session_storage.dart';

/// 웹이 아닌 플랫폼: 탭 단위 저장소가 없다(#2828).
TokenSessionStorage? createBrowserSessionStorage() => null;
