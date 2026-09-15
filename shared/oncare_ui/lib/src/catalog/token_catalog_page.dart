import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 토큰 미리보기 — 색·글자·모서리·간격·그림자·밀도별 크기(#1691).
///
/// 두 앱의 개발용 경로에서 연다. 같은 페이지가 앱 테마의 브랜드·밀도로 그려지므로
/// 두 앱을 나란히 열면 무엇이 같고 무엇이 다른지 바로 보인다.
class OnCareTokenCatalog extends StatelessWidget {
  const OnCareTokenCatalog({super.key});

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Tokens · ${tokens.brand.name} · ${tokens.density.name}'),
      ),
      body: ListView(
        padding: EdgeInsets.all(tokens.density.pagePadding),
        children: <Widget>[
          _Section(
            title: 'Brand',
            child: Wrap(
              spacing: OnCareSpacing.s12,
              runSpacing: OnCareSpacing.s12,
              children: <Widget>[
                _Swatch('primary', tokens.brand.primary),
                _Swatch('strong', tokens.brand.strong),
                _Swatch('surface', tokens.brand.surface),
                _Swatch('surfaceSoft', tokens.brand.surfaceSoft),
                _Swatch('border', tokens.brand.border),
                _Swatch('macroProtein', tokens.brand.macroProtein),
                _Swatch('macroFat', tokens.brand.macroFat),
                _Swatch('exerciseCardio', tokens.brand.exerciseCardio),
                _Swatch('exerciseStrength', tokens.brand.exerciseStrength),
                _Swatch('exerciseStretching', tokens.brand.exerciseStretching),
                _Swatch('segmentTrack', tokens.brand.segmentTrack),
                _Swatch('segmentLabel', tokens.brand.segmentLabel),
              ],
            ),
          ),
          const _Section(
            title: 'Neutral · Status',
            child: Wrap(
              spacing: OnCareSpacing.s12,
              runSpacing: OnCareSpacing.s12,
              children: <Widget>[
                _Swatch('textPrimary', OnCareColors.textPrimary),
                _Swatch('textSecondary', OnCareColors.textSecondary),
                _Swatch('textTertiary', OnCareColors.textTertiary),
                _Swatch('textDisabled', OnCareColors.textDisabled),
                _Swatch('surfacePage', OnCareColors.surfacePage),
                _Swatch('surfaceCard', OnCareColors.surfaceCard),
                _Swatch('surfaceInput', OnCareColors.surfaceInput),
                _Swatch('lineSubtle', OnCareColors.lineSubtle),
                _Swatch('lineStrong', OnCareColors.lineStrong),
                _Swatch('success', OnCareColors.success),
                _Swatch('caution', OnCareColors.caution),
                _Swatch('cautionFill', OnCareColors.cautionFill),
                _Swatch('danger', OnCareColors.danger),
                _Swatch('overlayInk', OnCareColors.overlayInk),
                _Swatch('chartGoalLine', OnCareColors.chartGoalLine),
              ],
            ),
          ),
          _Section(
            title: 'Typography',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final MapEntry<String, TextStyle?> role
                    in <String, TextStyle?>{
                      'display': text.displaySmall,
                      'titleLarge': text.titleLarge,
                      'titleMedium': text.titleMedium,
                      'titleSmall': text.titleSmall,
                      'bodyLarge': text.bodyLarge,
                      'body': text.bodyMedium,
                      'bodySmall': text.bodySmall,
                      'label': text.labelLarge,
                      'caption': text.labelSmall,
                    }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                    child: Text(
                      '${role.key} · '
                      '${OnCareTypography.roles[role.key]!.fontSize!.toStringAsFixed(0)}'
                      ' · 회원과 트레이너를 잇는 On-Care',
                      style: role.value,
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Radius · Shadow',
            child: Wrap(
              spacing: OnCareSpacing.s16,
              runSpacing: OnCareSpacing.s16,
              children: <Widget>[
                for (final MapEntry<String, BorderRadius> r
                    in const <String, BorderRadius>{
                      'xs 4': OnCareRadius.xsAll,
                      'sm 8': OnCareRadius.smAll,
                      'md 12': OnCareRadius.mdAll,
                      'lg 16': OnCareRadius.lgAll,
                      'xl 20': OnCareRadius.xlAll,
                    }.entries)
                  _Box(label: r.key, radius: r.value),
                const _Box(
                  label: 'card shadow',
                  radius: OnCareRadius.xlAll,
                  shadow: OnCareShadows.card,
                ),
                const _Box(
                  label: 'overlay shadow',
                  radius: OnCareRadius.mdAll,
                  shadow: OnCareShadows.overlay,
                ),
              ],
            ),
          ),
          _Section(
            title: 'Spacing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final double s in OnCareSpacing.scale)
                  Padding(
                    padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: 40, child: Text(s.toStringAsFixed(0))),
                        Container(
                          width: s,
                          height: OnCareSpacing.s8,
                          color: tokens.brand.primary,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Density · ${tokens.density.name}',
            child: Wrap(
              spacing: OnCareSpacing.s12,
              runSpacing: OnCareSpacing.s12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton(onPressed: () {}, child: const Text('Primary')),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Secondary'),
                ),
                TextButton(onPressed: () {}, child: const Text('Text')),
                const FilledButton(onPressed: null, child: Text('Disabled')),
                IconButton(
                  onPressed: () {},
                  tooltip: 'close',
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(
                  width: 240,
                  child: TextField(
                    decoration: InputDecoration(hintText: 'Input'),
                  ),
                ),
                Text(
                  'button ${tokens.density.buttonLarge.toStringAsFixed(0)}/'
                  '${tokens.density.buttonMedium.toStringAsFixed(0)}/'
                  '${tokens.density.buttonSmall.toStringAsFixed(0)} · '
                  'chip ${tokens.density.chip.toStringAsFixed(0)} · '
                  'row ${tokens.density.listRowMin.toStringAsFixed(0)} · '
                  'icon ${OnCareSize.iconScale.map((e) => e.toStringAsFixed(0)).join('/')}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: OnCareSpacing.s12),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String hex = color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: OnCareSpacing.s40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: OnCareRadius.smAll,
              border: Border.all(color: OnCareColors.lineSubtle),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(name, style: Theme.of(context).textTheme.labelSmall),
          Text('#$hex', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.radius, this.shadow});

  final String label;
  final BorderRadius radius;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: radius,
        border: Border.all(color: OnCareColors.lineStrong),
        boxShadow: shadow,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
