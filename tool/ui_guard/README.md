# ui_guard — UI 하드코딩 검사 (#1698)

[#1690](https://github.com/CSE-Sudo/on-care/issues/1690) 규격이 다시 흩어지지 않도록, 두 앱의 화면 코드(`lib/`)에
크기·색·모양·간격을 직접 적거나 Material 원시 위젯을 직접 쓰는 곳이 **늘면** CI 가 실패합니다.

지금 있는 하드코딩은 앱마다 `ui_guard_baseline.json`(파일별·항목별 개수)으로 허용합니다.

- 개수가 기준선보다 **늘면 실패**합니다. 새 코드는 토큰·공용 컴포넌트를 쓰세요.
- 개수가 **줄었는데 기준선을 갱신하지 않아도 실패**합니다. 줄어든 만큼 갱신해 함께 커밋하세요.

## 명령

```bash
cd tool/ui_guard
dart pub get
dart run bin/ui_guard.dart check                     # 두 앱 모두 검사
dart run bin/ui_guard.dart check frontend/flutter    # 한 앱만
dart run bin/ui_guard.dart update frontend/flutter   # 줄어든 개수를 기준선에 반영
dart run bin/ui_guard.dart update --allow-increase frontend/flutter  # 파일 이동·이름 변경
```

`update` 는 늘어난 곳이 있으면 `--allow-increase` 없이는 기준선을 쓰지 않습니다.

## 항목

| id | 잡는 것 |
| --- | --- |
| `fontSize` · `letterSpacing` | 숫자 리터럴이 들어간 값 |
| `fontWeight` | `FontWeight.*` 또는 숫자를 직접 적은 값 |
| `lineHeight` | `TextStyle` · `StrutStyle` · `copyWith` 의 숫자 `height:` |
| `colorLiteral` | `Color(0x…)` · `Color.fromARGB/fromRGBO` |
| `materialColor` | `Colors.*` (`transparent` 제외) |
| `opacity` | `.withValues(alpha:)` · `.withOpacity` · `.withAlpha` |
| `radius` | 숫자 `BorderRadius.circular` · `Radius.circular` |
| `edgeInsets` | 0 이 아닌 숫자가 든 `EdgeInsets.*` (호출 하나당 1) |
| `sizedBox` | 0 이 아닌 숫자 `SizedBox(width/height/dimension:)` · `Gap` |
| `boxShadow` | `BoxShadow(` |
| `animationDuration` | 숫자 `Duration(milliseconds:)` — `Future.delayed`·`Timer`·이름에 delay/debounce/timeout 등이 든 대기 시간은 제외 |
| `nonRoundedIcon` | `_rounded` 가 아닌 `Icons.*` |
| `materialWidget` | `FilledButton` · `ElevatedButton` · `OutlinedButton` · `TextButton` · `IconButton` · `AlertDialog` · `Dialog` · `showDialog` · `showModalBottomSheet` · `TextField` · `TextFormField` · `DropdownButton*` · `ChoiceChip` · `FilterChip` · `SnackBar` · `CircularProgressIndicator` · `LinearProgressIndicator` · `Divider` · `PopupMenuButton` · `MenuAnchor` · `AppBar` |

정규식이 아니라 구문 트리로 읽어 주석·문자열은 잡지 않습니다. 토큰으로 계산한 값에 숫자를 섞은 경우
(`AppSpacing.md * 2`)도 숫자를 적은 것으로 봅니다.

**제외**: `lib/gen/**`, `lib/l10n/**`, `*.g.dart`, PDF 생성기(`member_report_pdf_generator.dart`,
`report_pdf_generator.dart`), `shared/oncare_ui/**`.
