import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 입력창 크기 — 버튼과 줄이 맞는다(모바일 44/52, 웹 36/44).
enum AppFieldSize { medium, large }

/// 필드 위 라벨 + 필드 + 도움말을 세로로 묶는다. 떠오르는 라벨은 쓰지 않는다.
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (label == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label!,
          style: context.oncare
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        child,
      ],
    );
  }
}

double _fieldHeight(OnCareDensity density, AppFieldSize size) =>
    size == AppFieldSize.large ? density.inputLarge : density.inputMedium;

/// 두 앱의 입력창(#1695) — 채움·1px 테두리·포커스 1.5px 브랜드·반경 12.
///
/// 라벨은 필드 **위**에, 도움말·오류는 아래 `caption` 으로 둔다. 밑줄 입력창은 없다.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.size = AppFieldSize.medium,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final AppFieldSize size;

  /// 입력 글자의 가로 정렬. 숫자 한 칸(−/+ 사이 값)처럼 가운데가 읽기 쉬운
  /// 칸만 바꾼다.
  final TextAlign textAlign;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool multiline = maxLines == null || maxLines! > 1;
    final double height = _fieldHeight(tokens.density, size);
    return _Labeled(
      label: label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscureText,
        minLines: minLines,
        maxLines: obscureText ? 1 : maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlign: textAlign,
        style: tokens
            .text(OnCareTypography.body)
            .copyWith(color: OnCareColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          errorText: errorText,
          counterText: maxLength == null ? null : '',
          constraints: multiline ? null : BoxConstraints(minHeight: height),
          contentPadding: EdgeInsets.symmetric(
            horizontal: OnCareSpacing.s12,
            vertical: multiline ? OnCareSpacing.s12 : OnCareSpacing.s8,
          ),
          prefixIcon: prefixIcon == null
              ? null
              : AppIcon(prefixIcon, size: OnCareSize.iconMedium),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

/// 검색창 — 앞 검색 아이콘 + 입력이 있으면 지우기 버튼.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    required this.hint,
    required this.clearTooltip,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hint;
  final String clearTooltip;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      hint: widget.hint,
      autofocus: widget.autofocus,
      prefixIcon: AppIcon.setOf(context).search,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: _controller.text.isEmpty
          ? null
          : AppIconButton(
              icon: AppIcon.setOf(context).close,
              tooltip: widget.clearTooltip,
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
              },
            ),
    );
  }
}

/// 선택 필드 — 입력창과 같은 모양의 드롭다운. 밑줄 `DropdownButton` 을 대체한다.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
  });

  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return _Labeled(
      label: label,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        icon: AppIcon(
          AppIcon.setOf(context).dropdown,
          size: OnCareSize.iconMedium,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        style: tokens
            .text(OnCareTypography.body)
            .copyWith(color: OnCareColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          errorText: errorText,
          constraints: BoxConstraints(minHeight: tokens.density.inputMedium),
        ),
      ),
    );
  }
}
