import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너가 보낸 사진의 바이트. 경로로 키를 잡는다.
///
/// 평범한 이미지 URL 이 아니라 [dioProvider] 로 가져오는 이유는 첨부 경로가
/// **인증된 경로**이기 때문이다 — 그 스레드의 두 사람만 볼 수 있어야 하므로
/// 요청에 토큰이 붙어야 한다. (#921)
final coachImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, path) async {
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
    }, name: 'coachImage');

/// 대화 안에 그려지는 사진 첨부. (#921)
///
/// 트레이너가 보낸 자세 사진·시범 이미지는 "열어서 확인하는 파일"이 아니라
/// 대화의 일부라, PDF 처럼 카드로 두지 않고 말풍선 안에 그린다.
class CoachImageAttachment extends ConsumerWidget {
  const CoachImageAttachment({super.key, required this.attachment});

  final CoachAttachment attachment;

  /// 말풍선 안에서의 최대 크기. 원본이 작으면 그 크기로 그린다.
  static const double maxEdge = 220;

  /// 사진을 받는 동안 비워 두는 자리의 높이. 말풍선 안 사진 자리에 맞는
  /// 토큰이 없어 여기서 정한다.
  static const double _loadingHeight = 120;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bytes = ref.watch(coachImageProvider(attachment.downloadPath));

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
          error: (_, _) => _Unavailable(label: l.coachImageUnavailable),
          data: (data) => data == null
              ? _Unavailable(label: l.coachImageUnavailable)
              : Image.memory(
                  data,
                  key: ValueKey<String>('coach-image-${attachment.fileId}'),
                  // 대체 텍스트가 없으면 노드 자체가 생기지 않아, 음성 안내로
                  // 읽는 회원은 사진이 온 사실조차 모른다(#1942).
                  semanticLabel: l.a11yCoachPhoto,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      _Unavailable(label: l.coachImageUnavailable),
                ),
        ),
      ),
    );
  }
}

/// 사진을 못 그렸을 때 남는 자리 — 입력 채움 바탕에 아이콘과 한 줄.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.label});

  final String label;

  /// 대신 남는 자리의 높이. 맞는 토큰이 없어 여기서 정한다.
  static const double _height = 96;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: CoachImageAttachment.maxEdge,
      height: _height,
      color: OnCareColors.surfaceInput,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const AppIcon(
            AppIcons.imageUnavailable,
            size: OnCareSize.iconSmall,
            color: OnCareColors.textTertiary,
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Flexible(
            child: Text(
              label,
              style: context.oncare
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
