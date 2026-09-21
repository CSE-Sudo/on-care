import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 헬스장에 전화를 건다. 상담 폼의 빈 상태와 헬스장 상세가 함께 쓴다. (#1873)
///
/// 앱은 없는 시간을 만들어 내지 않는다 — 트레이너가 자리를 열지 않았으면 회원을
/// 전화로 내보낸다. 그래서 이 경로가 막히면 회원이 갈 곳이 없어지고, 조용히 아무
/// 일도 일어나지 않는 것이 가장 나쁘다. 실패하면 사유를 알린다(`my_flows.dart`
/// 의 외부 링크 열기와 같은 규칙).
Future<void> callGym(BuildContext context, String phone) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final AppToastHost toast = AppToastHost.of(context);
  // 전화 앱은 구분 기호를 가리지 않지만, 공백이 섞인 번호를 그대로 넘기면
  // `tel:` 파싱이 기기마다 갈린다.
  final String digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  bool opened = false;
  if (digits.isNotEmpty) {
    try {
      opened = await launchUrl(
        Uri(scheme: 'tel', path: digits),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
  }
  if (!opened) {
    toast.show(l.exGymCallFailed, type: AppToastType.error);
  }
}

/// 번호를 누르면 전화·복사 동작을 고른다. 취소는 외부 앱을 열지 않는다.
Future<void> showGymPhoneSheet(
  BuildContext context,
  String name,
  String phone,
) async {
  final l = AppLocalizations.of(context);
  final action = await showAppSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheet(
      title: name,
      showClose: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  phone,
                  style: context.oncare
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              IconButton(
                tooltip: l.exGymCopyPhone,
                onPressed: () => Navigator.pop(sheetContext, 'copy'),
                icon: const Icon(AppIcons.copy, size: 20, fill: 0, weight: 400),
                color: OnCareColors.textSecondary,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s20),
          AppButton(
            label: l.exGymCall,
            leadingIcon: AppIcons.phone,
            onPressed: () => Navigator.pop(sheetContext, 'call'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'call') {
    await callGym(context, phone);
  } else if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: phone));
    if (context.mounted) AppToastHost.of(context).show(l.exGymPhoneCopied);
  }
}
