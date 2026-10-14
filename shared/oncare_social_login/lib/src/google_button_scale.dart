/// 구글이 그리는 아이콘형 로그인 버튼(GIS `type: icon`, `size: large`)의 한 변 길이.
///
/// GIS 는 아이콘 버튼을 이 고정 크기로만 그리고 더 크게 그리는 옵션이 없다(#3445).
const double kGoogleIconButtonExtent = 40;

/// 구글 아이콘 버튼을 [extent] 크기의 자리에 맞추는 확대 배율(#3445).
///
/// 카카오 버튼과 같은 크기로 보이게 비율 그대로 키운다. 자리가 구글 버튼보다
/// 작으면 줄이지 않는다 — 구글 버튼이 잘리거나 눌리는 영역이 작아지지 않게.
double googleIconButtonScale(double extent) {
  if (!extent.isFinite || extent <= kGoogleIconButtonExtent) return 1;
  return extent / kGoogleIconButtonExtent;
}
