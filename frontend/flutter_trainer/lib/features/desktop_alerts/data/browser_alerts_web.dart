import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:oncare_trainer/features/desktop_alerts/data/browser_alerts.dart';
import 'package:web/web.dart' as web;

/// 웹: Notification API 와 탭 아이콘(#3285).
BrowserAlerts createBrowserAlerts() => _WebBrowserAlerts();

class _WebBrowserAlerts implements BrowserAlerts {
  /// 처음 실린 탭 아이콘 주소. 점을 지우면 이리로 돌아간다.
  String? _originalIcon;

  /// 점을 찍은 아이콘. 한 번 그려 두고 다시 쓴다.
  String? _dotIcon;

  /// 지금 점을 찍어야 하는가. 점 아이콘을 그리는 사이 바뀔 수 있다.
  bool _dotWanted = false;

  bool get _supported {
    if (!web.window.has('Notification')) return false;
    // 안드로이드 Chrome 은 `Notification` 이 있어도 생성자가 TypeError 를
    // 던진다 — 서비스 워커로만 띄울 수 있다(#3286).
    return !web.window.navigator.userAgent.contains('Android');
  }

  @override
  BrowserAlertPermission get permission {
    if (!_supported) return BrowserAlertPermission.unsupported;
    return switch (web.Notification.permission) {
      'granted' => BrowserAlertPermission.granted,
      'denied' => BrowserAlertPermission.denied,
      _ => BrowserAlertPermission.notAsked,
    };
  }

  @override
  Future<BrowserAlertPermission> requestPermission() async {
    if (permission != BrowserAlertPermission.notAsked) return permission;
    try {
      await web.Notification.requestPermission().toDart;
    } on Object {
      // 묻지 못했으면 그대로 '아직 묻지 않음' 이다.
    }
    return permission;
  }

  @override
  void show(BrowserAlert alert, {required void Function() onClick}) {
    if (permission != BrowserAlertPermission.granted) return;
    final web.Notification notification;
    try {
      notification = web.Notification(
        alert.title,
        web.NotificationOptions(
          body: alert.body,
          tag: alert.tag,
          icon: Uri.parse(
            web.document.baseURI,
          ).resolve('icons/Icon-192.png').toString(),
        ),
      );
    } on Object {
      return;
    }
    notification.onclick = (web.Event _) {
      web.window.focus();
      notification.close();
      onClick();
    }.toJS;
  }

  @override
  bool get pageFocused =>
      web.document.visibilityState == 'visible' && web.document.hasFocus();

  @override
  void setIconDot({required bool on}) {
    _dotWanted = on;
    final web.HTMLLinkElement? link =
        web.document.querySelector('link[rel="icon"]') as web.HTMLLinkElement?;
    if (link == null) return;
    final String original = _originalIcon ??= link.href;
    if (!on) {
      link.href = original;
      return;
    }
    final String? ready = _dotIcon;
    if (ready != null) {
      link.href = ready;
      return;
    }
    final web.HTMLImageElement image = web.HTMLImageElement();
    image.onload = (web.Event _) {
      final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
        ..width = 32
        ..height = 32;
      final web.CanvasRenderingContext2D? context =
          canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) return;
      context
        ..drawImage(image, 0, 0, 32, 32)
        ..beginPath()
        ..arc(24, 8, 7, 0, 2 * math.pi)
        ..fillStyle = '#E5484D'.toJS
        ..fill()
        ..lineWidth = 2
        ..strokeStyle = '#FFFFFF'.toJS
        ..stroke();
      final String dot = canvas.toDataURL('image/png');
      _dotIcon = dot;
      // 그리는 사이 점을 지웠으면 원래 아이콘을 그대로 둔다.
      if (_dotWanted) link.href = dot;
    }.toJS;
    image.src = original;
  }
}
