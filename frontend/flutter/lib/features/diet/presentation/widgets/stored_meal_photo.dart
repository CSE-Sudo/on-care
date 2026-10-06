import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// Bytes of a stored meal photo, keyed by its API path (`/diet/photos/<id>`).
///
/// 이름이 [MealPhoto] 와 갈리는 것을 피해 "stored" 를 붙였다 — 그쪽은 **올리기
/// 전** 고른 사진이고, 여기는 **이미 저장된** 사진이다.
///
/// Goes through the app's [dioProvider] rather than `Image.network` on
/// purpose: the photo route is **authenticated** (only the owner and their
/// trainer may read it), and the auth interceptor is what puts the token on
/// the request. A bare image URL would come back 401.
///
/// Riverpod's cache is also the image cache here — the same meal rendered on
/// the diet tab and in the detail sheet fetches once. (#699)
///
/// 받은 사진과 서버가 "없다·볼 수 없다" 고 답한 사진만 붙들어 둔다. 망 끊김·
/// 시간 초과·5xx 같은 잠깐의 오류까지 붙들면 앱을 다시 켜기 전까지 그 끼니의
/// 사진이 대체 썸네일로 남았다 — 그때는 화면을 떠나면 놓아, 다시 열 때 다시
/// 받는다(#3244).
final storedMealPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, path) async {
      final Dio dio = ref.watch(dioProvider);
      try {
        final Response<List<int>> res = await dio.get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes),
        );
        ref.keepAlive();
        final List<int>? data = res.data;
        if (data == null || data.isEmpty) return null;
        return Uint8List.fromList(data);
      } on DioException catch (e) {
        final int? status = e.response?.statusCode;
        if (status == 403 || status == 404) ref.keepAlive();
        // 사진을 못 가져와도 끼니 카드는 그려야 한다 — 호출부가 대체 썸네일로 넘어간다.
        return null;
      }
    });

/// A **stored** meal photo (the one the member already uploaded) drawn at
/// [width] × [height], with [fallback] shown while it
/// loads and whenever it can't be shown (no photo, network failure, corrupt
/// bytes). The fallback is the existing emoji/asset chip, so a photo that
/// isn't there changes nothing about the layout.
///
/// 모서리는 감싸는 틀(`AppImageFrame`)이 자른다 — 여기서는 반경을 모른다.
class StoredMealPhoto extends ConsumerWidget {
  const StoredMealPhoto({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    required this.fallback,
    this.semanticLabel,
  });

  /// API path relative to the API base (`/diet/photos/<id>`).
  final String path;

  /// 크기는 호출부가 정한다 — 목록 썸네일은 정사각, 수정 화면 상단은 가로로
  /// 넓은 사진이다. (#1053)
  final double width;
  final double height;
  final Widget fallback;

  /// 음성 안내가 읽을 대체 텍스트. 주지 않으면 `끼니 사진` 이다(#1942) —
  /// 어떤 끼니인지까지 말할 수 있는 자리에서만 따로 준다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List?> photo = ref.watch(
      storedMealPhotoProvider(path),
    );
    return photo.maybeWhen(
      data: (Uint8List? bytes) => bytes == null
          ? fallback
          : Image.memory(
              bytes,
              width: width,
              height: height,
              // 사진이 무엇인지 말해 준다 — 없으면 노드가 생기지 않아 음성
              // 안내에서는 끼니에 사진이 있다는 것도 알 수 없다(#1942).
              semanticLabel: semanticLabel ?? AppLocalizations.of(context).a11yMealPhoto,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                  fallback,
            ),
      orElse: () => fallback,
    );
  }
}
