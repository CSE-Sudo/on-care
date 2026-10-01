/// 리포트 결과지 한 장에 싣는 수치. (#2485)
///
/// 계산은 회원 앱과 함께 쓰는 `oncare_report` 에 있다(#2652) — 같은 주를 두
/// 앱이 다른 점수로 말하지 않게 한 곳에 둔다. 이 파일은 그 이름들을 이 앱의
/// 예전 자리에서도 쓸 수 있게 다시 내보낸다.
library;

export 'package:oncare_report/oncare_report.dart'
    show
        ReportSheet,
        SheetAverage,
        SheetAverageItem,
        SheetBand,
        SheetDietItem,
        SheetExerciseItem,
        SheetMeasure,
        SheetScore,
        SheetScorePart,
        kSheetNormalSpan,
        kSheetUnderSpan,
        sheetBarPosition;
