import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이용약관 · 개인정보 처리방침 본문. (#968)
///
/// 트레이너 계정은 담당 회원의 식단·운동·건강 기록을 열어 보고 리포트를
/// 만들어 보내는 쪽이다. 그 조건이 회원 앱에만 적혀 있으면, 데이터를 다루는
/// 사람은 자기가 무엇에 동의했는지 앱 안에서 볼 방법이 없다.
///
/// 셸(사이드바) 밖의 최상위 라우트라 배경만 있는 최소 Scaffold 를 둔다 — 가입
/// 화면에서 열릴 때는 세션이 없어 셸이 존재하지 않고, 그러면 버튼 잉크·본문
/// 선택이 기대는 Material 조상도 없다.
class LegalDocumentPage extends StatelessWidget {
  /// Creates the document view. [document] is a segment from
  /// [AppRoutes.legalDocuments]; anything else falls back to 이용약관.
  const LegalDocumentPage({super.key, this.document});

  /// Which document to render, from the `:document` path parameter.
  final String? document;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool isPrivacy = document == AppRoutes.legalPrivacy;
    final String title = isPrivacy
        ? l.myLegalPrivacyTitle
        : l.myLegalTermsTitle;
    final String body = isPrivacy ? l.myLegalPrivacyBody : l.myLegalTermsBody;

    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      body: SafeArea(
        child: AppWebPage(
          title: title,
          subtitle: l.myLegalEffectiveDate,
          width: AppWebPageWidth.narrow,
          leading: AppBackButton(onPressed: () => _leave(context)),
          body: ListView(
            children: <Widget>[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    AppSectionHeader(
                      title: title,
                      icon: isPrivacy
                          ? Icons.privacy_tip_rounded
                          : Icons.description_rounded,
                    ),
                    const SizedBox(height: OnCareSpacing.s12),
                    SelectableText(
                      body,
                      style: tokens
                          .text(OnCareTypography.body)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: OnCareSpacing.s16),
              Center(
                child: Text(
                  l.myLegalEffectiveDate,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 돌아갈 곳. 앱 안에서 열렸으면 그 화면으로 되돌아가고, 주소창으로 바로
  /// 들어왔으면 대시보드로 보낸다 — 세션이 없으면 인증 게이트가 거기서
  /// 로그인 화면으로 돌려보내므로 여기서 로그인 여부를 따로 보지 않는다.
  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.dashboard);
  }
}
