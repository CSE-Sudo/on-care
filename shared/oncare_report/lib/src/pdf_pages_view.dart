import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:oncare_report/src/pdf_pages.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// PDF 한 부를 쪽 그림으로 굽는 방법. 위젯 테스트가 갈아 끼운다.
typedef PdfPagesRasterizer = Future<List<Uint8List>> Function(Uint8List pdf);

/// 기본 굽기 — 화면 폭 두 배 확대에도 글자가 뭉개지지 않을 해상도(144dpi).
Future<List<Uint8List>> _defaultRasterize(Uint8List pdf) => rasterPdfPages(pdf);

/// 채팅에 붙은 PDF·리포트를 쪽마다 위아래로 이어 보여 준다.
///
/// `printing` 의 `PdfPreview` 를 대신한다. 그 위젯은 웹에서 pdf.js 를
/// `window.eval` 로 찾다가 CSP 에 막혀(#2828) 스피너만 돌았다. 여기서는
/// [rasterPdfPages] 가 웹에서 pdf.js 를 직접 부른다. 쪽마다 두 손가락으로
/// 확대할 수 있다.
class PdfPagesView extends StatefulWidget {
  /// Creates a viewer for [pdf].
  const PdfPagesView({
    super.key,
    required this.pdf,
    required this.failedText,
    this.rasterize = _defaultRasterize,
  });

  /// 보여 줄 PDF.
  final Uint8List pdf;

  /// 굽지 못했을 때의 안내. 스피너를 계속 돌리면 느린 것과 안 되는 것을
  /// 구별할 수 없다.
  final String failedText;

  /// 쪽 그림을 굽는 방법.
  final PdfPagesRasterizer rasterize;

  @override
  State<PdfPagesView> createState() => _PdfPagesViewState();
}

class _PdfPagesViewState extends State<PdfPagesView> {
  late Future<List<Uint8List>> _pages = _rasterOf(widget.pdf);

  Future<List<Uint8List>> _rasterOf(Uint8List pdf) async {
    final List<Uint8List> pages = await widget.rasterize(pdf);
    if (pages.isEmpty) throw StateError('empty pdf');
    return pages;
  }

  @override
  void didUpdateWidget(PdfPagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.pdf, oldWidget.pdf)) _pages = _rasterOf(widget.pdf);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: OnCareColors.surfacePage,
    child: FutureBuilder<List<Uint8List>>(
      future: _pages,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            key: ValueKey<String>('pdf-pages-loading'),
            child: AppLoading(placement: AppStatePlacement.card),
          );
        }
        final List<Uint8List>? pages = snapshot.data;
        if (snapshot.hasError || pages == null) return _failed(context);
        return ListView.separated(
          key: const ValueKey<String>('pdf-pages'),
          padding: const EdgeInsets.all(OnCareSpacing.s16),
          itemCount: pages.length,
          separatorBuilder: (_, _) => const SizedBox(height: OnCareSpacing.s12),
          itemBuilder: (context, index) => Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: OnCareColors.lineStrong),
                ),
                child: Image.memory(
                  pages[index],
                  key: ValueKey<String>('pdf-page-$index'),
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  errorBuilder: (context, _, _) => _failed(context),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _failed(BuildContext context) => Center(
    key: const ValueKey<String>('pdf-pages-failed'),
    child: Padding(
      padding: const EdgeInsets.all(OnCareSpacing.s24),
      child: Text(
        widget.failedText,
        textAlign: TextAlign.center,
        style: context.oncare
            .text(OnCareTypography.bodySmall)
            .copyWith(color: OnCareColors.textSecondary),
      ),
    ),
  );
}
