import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oncare_ui/oncare_ui.dart';

/// 코드 한 자리 상자의 폭·높이 — 회원 앱이 띄우는 상자와 같은 콘텐츠 고유 치수다.
const double _digitBoxWidth = 42;
const double _digitBoxHeight = 54;

/// 회원이 불러 주는 6자리 동기화 코드를 한 자리씩 상자에 받는 입력. (#1634)
///
/// 회원 앱이 같은 모양(자리마다 상자)으로 코드를 띄운다 — 트레이너가 보는 것과
/// 회원이 보는 것이 같은 형태여야 "세 번째 자리가 뭐라고요?" 가 통한다.
///
/// 칸을 여섯 개 두는 대신 **보이지 않는 입력 하나**([AppTextField])를 상자들
/// 위에 겹친다. 칸마다 컨트롤러를 두면 백스페이스·붙여넣기·자동완성이 칸
/// 경계에서 어긋나고, 포커스를 옮기는 코드가 화면 로직에 섞인다.
class PairingCodeInput extends StatefulWidget {
  const PairingCodeInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.enabled = true,
  });

  /// 지금까지 입력된 숫자. 여섯 자리가 차면 [onChanged] 가 그 값으로 불린다.
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// 코드 길이. 서버(`member_pairing_service.CODE_LENGTH`)와 같은 값이다.
  static const int length = 6;

  @override
  State<PairingCodeInput> createState() => _PairingCodeInputState();
}

class _PairingCodeInputState extends State<PairingCodeInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.focusNode.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.focusNode.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // 상자에 그려진 값·다음 자리 표시가 컨트롤러·포커스를 따라가야 한다.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final String value = widget.controller.text;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < PairingCodeInput.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OnCareSpacing.s4,
                ),
                child: _DigitBox(
                  key: ValueKey<String>('pairing-digit-$i'),
                  digit: i < value.length ? value[i] : '',
                  // 다음에 칠 자리를 테두리로 알린다 — 커서가 보이지 않으므로
                  // 이것이 없으면 어디까지 쳤는지 화면이 말하지 않는다.
                  active: widget.focusNode.hasFocus && i == value.length,
                ),
              ),
          ],
        ),
        // 실제 입력. 값은 상자가 그리므로 입력창 자체는 그리지 않고(투명)
        // 탭·키 입력만 받는다 — 보이면 가로로 긴 입력창이 상자들을 덮는다(#1636).
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: AppTextField(
              key: const ValueKey<String>('client-connect-code'),
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              size: AppFieldSize.large,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: PairingCodeInput.length,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// 코드 한 자리. 아직 안 친 자리는 비어 있다.
class _DigitBox extends StatelessWidget {
  const _DigitBox({super.key, required this.digit, required this.active});

  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: _digitBoxWidth,
      height: _digitBoxHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(
          color: active ? tokens.brand.primary : OnCareColors.lineStrong,
          width: active ? OnCareSize.focusBorder : OnCareSize.hairline,
        ),
      ),
      child: Text(
        digit,
        // 자리마다 폭이 달라 보이면 상자 안에서 숫자가 흔들린다.
        style: tokens
            .text(OnCareTypography.numeric(OnCareTypography.titleLarge))
            .copyWith(color: OnCareColors.textPrimary),
      ),
    );
  }
}
