import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 사진을 받아 오는 동안 차지하는 자리의 높이. 받은 뒤 크기가 크게 튀지 않을
/// 만큼만 잡는다.
const double _loadingHeight = 120;

/// 사진을 못 그렸을 때 남는 자리의 높이.
const double _unavailableHeight = 96;

/// 첨부 사진의 바이트. 경로로 키를 잡는다.
///
/// 평범한 이미지 URL 이 아니라 [dioProvider] 로 가져오는 이유는 첨부 경로가
/// **인증된 경로**이기 때문이다 — 그 스레드의 두 사람만 볼 수 있어야 하므로
/// 요청에 토큰이 붙어야 한다(고객 식단 사진과 같은 이유, #699).
final chatImageProvider = FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, path) async {
    final Dio dio = ref.watch(dioProvider);
    try {
      final Response<List<int>> res = await dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final List<int>? data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException {
      // 사진을 못 가져와도 대화는 그대로 읽혀야 한다.
      return null;
    }
  },
  name: 'chatImage',
);

/// 대화 안에 그려지는 사진 첨부. (#921)
///
/// 자세 사진·시범 이미지는 "열어서 확인하는 파일"이 아니라 대화의 일부다.
/// 그래서 PDF 처럼 카드로 두지 않고 말풍선 안에 그린다 — 카드로 두면 자세를
/// 확인할 때마다 파일을 열어야 하고, 그건 채팅에 사진을 붙이는 이유 자체를
/// 없앤다.
class ChatImageAttachment extends ConsumerWidget {
  const ChatImageAttachment({super.key, required this.attachment});

  final ChatAttachment attachment;

  /// 말풍선 안에서의 최대 크기. 원본이 작으면 그 크기로 그린다 — 작은 사진을
  /// 늘려 놓으면 뭉개진 그림만 커진다.
  static const double maxEdge = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bytes = ref.watch(chatImageProvider(attachment.downloadPath));

    return AppImageFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxEdge,
          maxHeight: maxEdge,
        ),
        child: bytes.when(
          loading: () => const SizedBox(
            width: maxEdge,
            height: _loadingHeight,
            child: Center(child: AppLoading.inline()),
          ),
          error: (_, _) => _Unavailable(label: l.chatImageUnavailable),
          data: (data) => data == null
              ? _Unavailable(label: l.chatImageUnavailable)
              : Image.memory(
                  data,
                  key: ValueKey<String>('chat-image-${attachment.fileId}'),
                  fit: BoxFit.contain,
                  // 바이트는 받았지만 그릴 수 없는 경우(잘린 파일 등)도 대화가
                  // 깨지지 않아야 한다.
                  errorBuilder: (_, _, _) =>
                      _Unavailable(label: l.chatImageUnavailable),
                ),
        ),
      ),
    );
  }
}

/// 사진을 못 그렸을 때 남는 자리. 무엇이 있었는지는 말해 준다.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ChatImageAttachment.maxEdge,
      height: _unavailableHeight,
      color: OnCareColors.surfaceInput,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.image_not_supported_rounded,
            size: OnCareSize.iconSmall,
            color: OnCareColors.textTertiary,
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Flexible(
            child: Text(
              label,
              style: context.oncare
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
