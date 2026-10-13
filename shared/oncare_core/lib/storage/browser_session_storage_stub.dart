import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_core/storage/token_session_storage.dart';

/// 웹이 아닌 플랫폼: 탭 단위 저장소가 없다(#2828).
TokenSessionStorage? createBrowserSessionStorage(TokenKeyspace space) => null;
