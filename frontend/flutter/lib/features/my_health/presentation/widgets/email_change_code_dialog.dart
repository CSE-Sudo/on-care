import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';
import 'package:oncare/features/my_health/presentation/controllers/email_change_code_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인 이메일을 바꾸기 전에 새 주소의 주인인지 확인하는 창(#3230).
///
/// 열리면 바로 새 주소([email])로 6자리 코드를 요청하고, 회원이 메일에서 받은
/// 코드를 적으면 그 코드를 돌려준다. 취소하면 null 이다. 코드가 맞는지는 저장할 때
/// 서버가 본다 — 이 창은 받는 것까지만 한다.
///
/// 본인 확인(현재 비밀번호)만으로는 자기 계정의 이메일을 **남의** 주소로 바꿀 수
/// 있었다. 그 주소의 주인은 가입하려다 막히고, 그 주소의 소셜 로그인이 바꾼 사람의
/// 계정으로 들어갔다. 코드는 그 주소의 메일함을 연 사람만 안다.
Future<String?> showEmailChangeCodeDialog({
  required BuildContext context,
  required String email,
}) => showAppDialog<String>(
  context: context,
  // 창 안에서 코드를 요청하고 받은 코드를 적는다 — 바깥을 잘못 눌러 닫히면 적던
  // 코드와 요청 결과가 사라진다. 앞의 본인 확인 창처럼 `취소` 로만 닫는다(#3245).
  dismissible: false,
  builder: (_) => EmailChangeCodeDialog(email: email),
);

/// [showEmailChangeCodeDialog] 가 띄우는 창. 테스트가 직접 찾을 수 있게 공개한다.
class EmailChangeCodeDialog extends ConsumerStatefulWidget {
  const EmailChangeCodeDialog({super.key, required this.email});

  /// 바꿀 새 이메일. 코드는 이 주소로 간다.
  final String email;

  @override
  ConsumerState<EmailChangeCodeDialog> createState() =>
      _EmailChangeCodeDialogState();
}

class _EmailChangeCodeDialogState extends ConsumerState<EmailChangeCodeDialog> {
  final TextEditingController _code = TextEditingController();

  /// 마지막 요청의 응답 — 유효 시간과 다시 받기 대기 시간. 받기 전에는 null.
  SignupEmailCodeSent? _sent;

  /// 마지막 요청 뒤 지난 초. 남은 시간·다시 받기 카운트다운이 이 값으로 준다.
  int _elapsed = 0;
  Timer? _timer;
  bool _requesting = false;

  /// 코드 요청이 막힌 이유(창 안 배너). 다시 받으면 지운다.
  String? _requestError;

  @override
  void initState() {
    super.initState();
    // 창이 그려진 뒤 요청한다 — 문구를 고르려면 로케일이 필요하다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _request();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  int get _secondsLeft {
    final SignupEmailCodeSent? sent = _sent;
    if (sent == null) return 0;
    return math.max(0, sent.expiresInMinutes * 60 - _elapsed);
  }

  int get _resendLeft {
    final SignupEmailCodeSent? sent = _sent;
    if (sent == null) return 0;
    return math.max(0, sent.resendAfterSeconds - _elapsed);
  }

  bool get _ready =>
      _sent != null &&
      _secondsLeft > 0 &&
      SignupEmailCode.isComplete(_code.text);

  /// 남은 초를 `9:59` 모양으로 — 가입 화면과 같은 표기다.
  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _request() async {
    if (_requesting) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    try {
      final SignupEmailCodeSent sent = await ref
          .read(accountRepositoryProvider)
          .requestEmailChangeCode(email: widget.email);
      if (!mounted) return;
      _timer?.cancel();
      _code.clear();
      setState(() {
        _requesting = false;
        _sent = sent;
        _elapsed = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _elapsed++);
        if (_secondsLeft == 0 && _resendLeft == 0) t.cancel();
      });
    } on SignupEmailCodeError catch (e) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _requestError = switch (e.kind) {
          SignupEmailCodeFailure.invalidEmail => l.authEmailInvalid,
          SignupEmailCodeFailure.tooMany => l.passwordTooManyAttempts,
          SignupEmailCodeFailure.unavailable => l.signUpEmailCodeUnavailable,
          SignupEmailCodeFailure.temporary => l.passwordTemporaryFailure,
        };
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _requestError = l.passwordTemporaryFailure;
      });
    }
  }

  void _confirm() {
    if (!_ready) return;
    Navigator.pop(context, _code.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int left = _secondsLeft;
    final int resendLeft = _resendLeft;
    return AppDialog(
      key: const ValueKey<String>('email-change-code-dialog'),
      title: l.emailChangeCodeTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('email-change-code-cancel'),
        confirmKey: const ValueKey<String>('email-change-code-confirm'),
        cancelLabel: l.myCancel,
        onCancel: () => Navigator.pop(context),
        confirmLabel: l.emailChangeCodeNext,
        onConfirm: _ready ? _confirm : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.emailChangeCodeMessage(widget.email)),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('email-change-code'),
            controller: _code,
            hint: l.signUpEmailCodeHint,
            enabled: _sent != null,
            helper: _sent == null
                ? null
                : left > 0
                ? l.signUpEmailCodeRemaining(_clock(left))
                : l.signUpEmailCodeExpired,
            prefixIcon: AppIcons.lock,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.oneTimeCode],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(SignupEmailCode.length),
            ],
            // 버튼이 여섯 자리에 맞춰 켜지고 꺼지므로 입력마다 다시 그린다.
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const ValueKey<String>('email-change-code-resend'),
              label: resendLeft > 0
                  ? l.signUpEmailCodeResendIn(resendLeft)
                  : l.signUpEmailCodeResend,
              onPressed: resendLeft > 0 || _requesting ? null : _request,
              loading: _requesting,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
            ),
          ),
          if (_requestError case final String error) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            AppBanner(
              key: const ValueKey<String>('email-change-code-error'),
              title: error,
              tone: AppBannerTone.danger,
              density: AppBannerDensity.compact,
            ),
          ],
          if (ref.watch(emailChangeDemoCodeHintProvider)) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            AppBanner(
              key: const ValueKey<String>('email-change-code-demo'),
              title: l.signUpEmailCodeDemoNote(SignupEmailCode.demoCode),
              density: AppBannerDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
