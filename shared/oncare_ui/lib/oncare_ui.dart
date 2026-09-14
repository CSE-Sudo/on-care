/// On-Care 두 앱이 함께 쓰는 UI 규격(#1690).
///
/// 화면 코드는 크기·색·모양 숫자를 직접 적지 않고 이 패키지의 토큰과 테마,
/// 컴포넌트만 쓴다. 앱마다 다른 것은 [OnCareBrand](브랜드 색)와
/// [OnCareDensity](모바일/웹 밀도) 두 가지뿐이다.
library;

export 'src/catalog/token_catalog_page.dart';
export 'src/components/app_button.dart';
export 'src/components/app_icon_button.dart';
export 'src/theme/oncare_theme.dart';
export 'src/theme/oncare_tokens.dart';
export 'src/tokens/brand.dart';
export 'src/tokens/colors.dart';
export 'src/tokens/density.dart';
export 'src/tokens/elevation.dart';
export 'src/tokens/layout.dart';
export 'src/tokens/motion.dart';
export 'src/tokens/radius.dart';
export 'src/tokens/sizes.dart';
export 'src/tokens/spacing.dart';
export 'src/tokens/typography.dart';
