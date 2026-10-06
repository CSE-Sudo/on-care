import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 화면에 붙이지 않은 위젯 하나를 구운 그림.
///
/// 픽셀은 `RGBA` 순서의 날 바이트다. PNG 로 구우면 PDF 에 담을 때 다시 풀어야
/// 한다 — 카드마다 인코딩·디코딩을 한 번씩 더 하는 왕복을 건너뛴다.
class CapturedWidget {
  /// Creates a captured raster.
  const CapturedWidget({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;

  /// 픽셀 폭·높이.
  final int width;
  final int height;
}

/// 위젯을 그림으로 굽는 방법. PDF 생성기가 받아 쓰고, 테스트는 갈아 끼운다.
typedef ReportWidgetCapture =
    Future<CapturedWidget> Function(
      Widget child, {
      required double width,
      required double pixelRatio,
    });

/// 화면에 보이는 것과 **같은 위젯**을 화면 밖에서 그려 그림으로 만든다(#2424).
///
/// 회원에게 가는 PDF 는 트레이너가 편집기에서 본 카드와 같아야 한다. 모양을
/// 흉내 내 PDF 용으로 다시 그리면 한쪽만 고쳐지는 날이 온다. 그래서 편집기의
/// 카드 위젯을 그대로 짓고(build) 배치하고(layout) 칠해(paint) 굽는다.
///
/// 앱의 화면 트리와 섞이지 않도록 자기만의 [BuildOwner]·[PipelineOwner] 를
/// 둔다. 폭은 [width] 로 고정하고 높이는 내용이 정한다 — 카드 하나가 몇 줄이
/// 될지는 그려 봐야 안다. [child] 는 테마·로케일·provider 를 이미 감싼
/// 채로 온다.
Future<CapturedWidget> captureReportWidget(
  Widget child, {
  required double width,
  required double pixelRatio,
}) async {
  final ui.FlutterView view =
      WidgetsBinding.instance.platformDispatcher.implicitView ??
      WidgetsBinding.instance.platformDispatcher.views.first;
  final RenderRepaintBoundary boundary = RenderRepaintBoundary();
  // 높이는 느슨하게 둔다 — RenderView 는 제약이 빡빡하지 않으면 자식 크기를
  // 따른다. 끝없는 높이는 배치 단계에서 막히므로 넉넉한 한도만 둔다.
  final BoxConstraints constraints = BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: width * _maxAspect,
  );
  final RenderView renderView = RenderView(
    view: view,
    child: boundary,
    configuration: ViewConfiguration(
      logicalConstraints: constraints,
      physicalConstraints: constraints,
    ),
  );
  final PipelineOwner pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final FocusManager focusManager = FocusManager();
  final BuildOwner buildOwner = BuildOwner(focusManager: focusManager);
  final RenderObjectToWidgetElement<RenderBox> root =
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        child: child,
      ).attachToRenderTree(buildOwner);
  try {
    buildOwner.buildScope(root);
    buildOwner.finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      // 화면에 뜨지 않는 내부 오류다 — 생성기가 잡아 글자만 담은 PDF 로
      // 물러선다.
      if (data == null) throw StateError('failed to capture a report card');
      return CapturedWidget(
        rgba: data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  } finally {
    // 트리를 내려 provider 구독과 컨트롤러를 놓는다 — 남겨 두면 PDF 를 만들
    // 때마다 보이지 않는 화면이 하나씩 쌓인다.
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
    ).attachToRenderTree(buildOwner, root);
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner.rootNode = null;
    pipelineOwner.dispose();
    // 렌더 객체가 쥔 레이어(그림 한 장 크기)도 놓는다(#3246, #3250) — 자식이
    // 먼저다.
    boundary.dispose();
    renderView.dispose();
    focusManager.dispose();
  }
}

/// 카드 한 장이 가질 수 있는 가장 긴 세로 비율. 이보다 길면 배치가 넘친다.
const double _maxAspect = 8;
