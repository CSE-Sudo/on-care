import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:printing/printing.dart';

/// PDF 한 부를 쪽마다 PNG 로 굽는다.
typedef ReportPdfRasterizer = Future<List<Uint8List>> Function(Uint8List pdf);

/// ③ 전송 미리보기가 PDF 를 쪽 그림으로 바꾸는 방법.
///
/// 굽는 일은 `printing` 플러그인(웹에서는 pdf.js)이 한다. 위젯 테스트에는 그
/// 플러그인이 없어 이 자리를 갈아 끼운다 — 미리보기에 무엇을 넘기는지는 그대로
/// 검증된다.
final Provider<ReportPdfRasterizer> reportPdfRasterizerProvider =
    Provider<ReportPdfRasterizer>((_) => rasterReportPdf);

/// 미리보기용 해상도. 한 쪽이 화면 폭을 넘지 않는 크기라 두 배 확대에도 글자가
/// 뭉개지지 않을 만큼만 굽는다.
const double _previewDpi = 144;

/// [pdf] 의 모든 쪽을 PNG 로 굽는다.
Future<List<Uint8List>> rasterReportPdf(Uint8List pdf) async {
  final List<Uint8List> pages = <Uint8List>[];
  await for (final PdfRaster page in Printing.raster(pdf, dpi: _previewDpi)) {
    pages.add(await page.toPng());
  }
  return pages;
}

/// 편집기 ③ 전송 — 회원이 채팅으로 받을 리포트를 그대로 보여 준다(#2402).
///
/// 화면에서 따로 그린 요약이 아니라 **전송과 같은 생성기로 만든 PDF** 를 쪽마다
/// 보여 준다. 미리보기와 실제로 나가는 파일이 서로 다를 수 없게 하는 것이 이
/// 단계의 일이다. 글을 고치는 일은 ② 작성의 몫이라 여기에는 입력창이 없다.
class ReportSendPreview extends ConsumerStatefulWidget {
  /// Creates the send-stage preview of [report].
  const ReportSendPreview({
    super.key,
    required this.report,
    required this.pdf,
    required this.onRetry,
  });

  /// 보낼 리포트 — 받는 사람과 대상 주를 적는다.
  final WeeklyReport report;

  /// 보낼 PDF. 페이지가 전송과 함께 쓰는 한 부다.
  final Future<Uint8List> pdf;

  /// 만들다 실패했을 때 다시 만든다.
  final VoidCallback onRetry;

  @override
  ConsumerState<ReportSendPreview> createState() => _ReportSendPreviewState();
}

class _ReportSendPreviewState extends ConsumerState<ReportSendPreview> {
  /// 확대 단계. 첫 단계가 카드 폭에 맞춘 크기다.
  static const List<double> _zoomSteps = <double>[1, 1.5, 2];

  /// 쪽을 그리는 가장 넓은 폭. 넓은 창에서 A4 한 쪽이 화면을 다 덮지 않게 한다.
  static const double _pageMaxWidth = 560;

  late Future<List<Uint8List>> _pages = _rasterOf(widget.pdf);
  int _page = 0;
  int _zoom = 0;

  Future<List<Uint8List>> _rasterOf(Future<Uint8List> pdf) async {
    final List<Uint8List> pages = await ref.read(reportPdfRasterizerProvider)(
      await pdf,
    );
    if (pages.isEmpty) throw StateError('empty report pdf');
    return pages;
  }

  @override
  void didUpdateWidget(ReportSendPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 문구가 바뀌어 PDF 를 새로 만들었다 — 첫 쪽부터 다시 본다.
    if (!identical(widget.pdf, oldWidget.pdf)) {
      _pages = _rasterOf(widget.pdf);
      _page = 0;
      _zoom = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey<String>('report-send-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RecipientCard(report: widget.report),
        const SizedBox(height: OnCareSpacing.s16),
        FutureBuilder<List<Uint8List>>(
          future: _pages,
          builder: (context, snapshot) {
            // 다시 만드는 동안에는 지난 결과(실패 포함)를 두지 않는다 —
            // FutureBuilder 는 새 future 를 기다리는 동안에도 지난 오류를 들고
            // 있다.
            if (snapshot.connectionState != ConnectionState.done) {
              return Column(
                key: const ValueKey<String>('report-send-preview-loading'),
                children: <Widget>[
                  const AppLoading(placement: AppStatePlacement.card),
                  Text(
                    l.reportsPreviewGenerating,
                    textAlign: TextAlign.center,
                    style: context.oncare
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ],
              );
            }
            final List<Uint8List>? pages = snapshot.data;
            if (snapshot.hasError || pages == null) {
              // 재시도 버튼은 상태 위젯 안에 있어 키를 줄 수 없다 — 묶음에
              // 키를 둔다.
              return KeyedSubtree(
                key: const ValueKey<String>('report-send-preview-failed'),
                child: AppErrorState(
                  title: l.reportsPreviewFailed,
                  retryLabel: l.actionRetry,
                  placement: AppStatePlacement.card,
                  onRetry: widget.onRetry,
                ),
              );
            }
            return _pager(l, pages);
          },
        ),
      ],
    );
  }

  Widget _pager(AppLocalizations l, List<Uint8List> pages) {
    final int page = math.min(_page, pages.length - 1);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconButton(
                key: const ValueKey<String>('report-send-preview-prev'),
                icon: AppIcons.chevronLeft,
                tooltip: l.reportsPreviewPrevPage,
                size: AppIconButtonSize.small,
                onPressed: page == 0
                    ? null
                    : () => setState(() => _page = page - 1),
              ),
              Text(
                l.reportsPreviewPage(page + 1, pages.length),
                key: const ValueKey<String>('report-send-preview-page-label'),
                style: context.oncare.text(
                  OnCareTypography.numeric(OnCareTypography.bodySmall),
                ),
              ),
              AppIconButton(
                key: const ValueKey<String>('report-send-preview-next'),
                icon: AppIcons.chevronRight,
                tooltip: l.reportsPreviewNextPage,
                size: AppIconButtonSize.small,
                onPressed: page >= pages.length - 1
                    ? null
                    : () => setState(() => _page = page + 1),
              ),
              const Spacer(),
              AppIconButton(
                key: const ValueKey<String>('report-send-preview-zoom-out'),
                icon: AppIcons.zoomOut,
                tooltip: l.reportsPreviewZoomOut,
                size: AppIconButtonSize.small,
                onPressed: _zoom == 0 ? null : () => setState(() => _zoom--),
              ),
              AppIconButton(
                key: const ValueKey<String>('report-send-preview-zoom-in'),
                icon: AppIcons.zoomIn,
                tooltip: l.reportsPreviewZoomIn,
                size: AppIconButtonSize.small,
                onPressed: _zoom >= _zoomSteps.length - 1
                    ? null
                    : () => setState(() => _zoom++),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              final double width =
                  math.min(constraints.maxWidth, _pageMaxWidth) *
                  _zoomSteps[_zoom];
              // 확대하면 카드보다 넓어진다 — 옆으로 밀어 본다.
              return SingleChildScrollView(
                key: const ValueKey<String>('report-send-preview-scroll'),
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: OnCareColors.lineStrong),
                      ),
                      child: Image.memory(
                        pages[page],
                        key: ValueKey<String>('report-send-preview-page-$page'),
                        width: width,
                        fit: BoxFit.fitWidth,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stack) => SizedBox(
                          width: width,
                          child: Padding(
                            padding: const EdgeInsets.all(OnCareSpacing.s16),
                            child: Text(
                              l.reportsPreviewFailed,
                              textAlign: TextAlign.center,
                              style: context.oncare
                                  .text(OnCareTypography.body)
                                  .copyWith(color: OnCareColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 받는 사람·대상 주·전달 방식 — 무엇이 어디로 가는지 보내기 전에 한 번 더
/// 읽게 한다.
class _RecipientCard extends StatelessWidget {
  const _RecipientCard({required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(
            title: l.reportsPreviewTitle,
            icon: AppIcons.file,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _Field(
            fieldKey: 'report-send-preview-recipient',
            label: l.reportsPreviewRecipient,
            value: report.client.name,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _Field(
            fieldKey: 'report-send-preview-week',
            label: l.reportsPreviewWeek,
            value: report.rangeLabel(l),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppBanner(
            key: const ValueKey<String>('report-send-preview-delivery'),
            title: l.reportsPreviewDelivery(report.client.name),
            message: l.reportsPreviewEditHint,
            icon: AppIcons.chat,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final String fieldKey;
  final String label;
  final String value;

  /// 이름 칸 폭 — 두 줄의 값이 같은 세로선에서 시작하게 한다.
  static const double _labelWidth = 72;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            key: ValueKey<String>(fieldKey),
            style: tokens.text(
              OnCareTypography.strong(OnCareTypography.bodySmall),
            ),
          ),
        ),
      ],
    );
  }
}
