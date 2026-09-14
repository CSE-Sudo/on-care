# oncare_ui

On-Care 두 앱(회원앱 `frontend/flutter`, 트레이너웹 `frontend/flutter_trainer`)이 함께 쓰는 **UI 규격의 단일 원본**입니다. 전체 규격과 진행 계획은 이슈 #1690 을 기준으로 합니다.

## 원칙

- 화면 코드는 크기·색·모서리·간격·그림자 숫자를 직접 적지 않고, 이 패키지의 토큰·테마·컴포넌트만 씁니다.
- 앱마다 다른 것은 두 가지뿐입니다.
  - `OnCareBrand` — 브랜드 색(회원 파랑 `#3EAFDF` / 트레이너 남색 `#2E7DAB`)
  - `OnCareDensity` — 플랫폼 밀도(모바일 / 웹): 버튼·입력·칩 높이, 페이지 여백 등
- 상태색(완료 초록·주의 주황·위험 빨강)은 두 앱이 같은 값을 씁니다.
- 라이트 테마만 제공합니다.

## 사용

```dart
MaterialApp(
  theme: OnCareTheme.light(
    brand: OnCareBrand.member,
    density: OnCareDensity.mobile,
  ),
);

// 위젯 안에서
final tokens = context.oncare; // brand, density
Text('제목', style: Theme.of(context).textTheme.titleMedium);
```

## 토큰 요약

| 구분 | 값 |
|---|---|
| 글자 역할 | display 28 · titleLarge 22 · titleMedium 18 · titleSmall 16 · bodyLarge 16 · body 15 · bodySmall 14 · label 14(600) · caption 12, 굵기 500/600/700 |
| 버튼 라벨 | 16 / 15 / 13, 굵기 600 |
| 버튼 높이 | 모바일 52/44/32 · 웹 44/36/28 |
| 모서리 | 4 · 8 · 12(조작 요소) · 16 · 20(카드·창) · 알약 |
| 간격 | 4의 배수(2는 선·점 사이만) |
| 아이콘 | `_rounded` 계열, 16 / 20 / 24 (빈 화면 40) |
| 창 폭 | 웹 400 / 560 / 800, 모바일 확인창 400 · 시트 최대 높이 90% |
| 텍스트 색 | `#1A1A1A` · `#465568` · `#667585` · `#768596` |
| 표면 | 페이지 `#F5F7FA` · 카드 `#FFFFFF` · 입력 `#F2F4F7` |
| 상태 | 완료 `#34C759` · 주의 `#E8760A`/`#FF953C` · 위험 `#F04438` |

`OnCareTokenCatalog` 위젯으로 현재 앱의 토큰을 한 화면에서 볼 수 있습니다.

## 글자 배율

앱 전역 글자 배율은 없습니다(#1707). 기기 접근성 배율만 `OnCareTypography.scaler` 로 1.0 ~ 1.3 사이에서 따릅니다. 두 앱 모두 `lib/design_system` 없이 이 패키지만 쓰며, 화면 코드의 새 하드코딩은 `tool/ui_guard` 가 막습니다(앱별 기준선 `ui_guard_baseline.json` 은 비어 있습니다).

## 테스트

```bash
flutter test
```
