"""코드 메일의 HTML 본문(#3490).

가입·이메일 변경 인증 코드와 비밀번호 재설정 코드 메일이 같은 틀을 쓴다. 일반
텍스트 본문은 그대로 두고, 이 HTML 은 `multipart/alternative` 의 두 번째 본문으로
붙는다 — HTML 을 못 그리는 메일 앱은 텍스트를 보여 준다.

메일 앱마다 CSS 지원이 달라 표(`table`) 배치와 인라인 스타일만 쓴다. 외부 이미지·
글꼴·스크립트는 넣지 않는다(차단되거나 추적으로 보인다). 넣는 문장은 모두
이스케이프한다.
"""
from __future__ import annotations

from html import escape

# 회원 앱 브랜드 색(shared/oncare_ui tokens/brand.dart 의 회원 값).
BRAND = "#3EAFDF"
BRAND_STRONG = "#277DA1"
BRAND_SURFACE = "#EDF7FC"
_TEXT = "#1F2933"
_TEXT_SUB = "#5F6B76"
_PAGE = "#F4F6F8"
_LINE = "#E3E8ED"
_FONT = (
    "-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Malgun Gothic',"
    "'Noto Sans KR',sans-serif"
)


def code_mail_html(
    *,
    title: str,
    lead: str,
    code: str,
    minutes: int,
    ignore: str,
    support: str = "",
    link: str = "",
    link_label: str = "",
) -> str:
    """코드 메일 한 통의 HTML.

    `title` 은 머리 아래 큰 제목, `lead` 는 안내 문장, `ignore` 는 요청하지 않았을 때의
    안내다. `support` 는 문의처(비면 줄을 넣지 않는다), `link` 가 있으면 코드 아래에
    `link_label` 버튼으로 둔다.
    """
    e = escape
    # 6자리 인증 코드는 크게 벌려 쓰고, 9자인 재설정 코드(`ABCD-EFGH`)는 좁은 폰에서도
    # 한 줄에 들도록 조금 줄인다.
    size, spacing = (40, 10) if len(code) <= 6 else (30, 4)
    button = ""
    if link:
        button = f"""
              <tr><td align="center" style="padding:8px 32px 8px;">
                <a href="{e(link, quote=True)}" style="display:inline-block;padding:14px 28px;border-radius:12px;background:{BRAND};color:#FFFFFF;font-size:16px;font-weight:700;text-decoration:none;">{e(link_label)}</a>
              </td></tr>"""
    contact = ""
    if support:
        contact = f"""
              <p style="margin:8px 0 0;font-size:13px;line-height:1.6;color:{_TEXT_SUB};">문의: {e(support)}</p>"""
    return f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>{e(title)}</title>
</head>
<body style="margin:0;padding:0;background:{_PAGE};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{_PAGE};font-family:{_FONT};">
    <tr><td align="center" style="padding:32px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid {_LINE};">
        <tr><td style="background:{BRAND};padding:24px 32px;">
          <span style="font-size:24px;font-weight:800;letter-spacing:-0.5px;color:#FFFFFF;">On-Care</span>
        </td></tr>
        <tr><td style="padding:32px 32px 8px;">
          <h1 style="margin:0 0 12px;font-size:22px;line-height:1.4;font-weight:700;color:{_TEXT};">{e(title)}</h1>
          <p style="margin:0;font-size:16px;line-height:1.7;color:{_TEXT};">{e(lead)}</p>
        </td></tr>
        <tr><td style="padding:24px 32px 8px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{BRAND_SURFACE};border-radius:12px;">
            <tr><td align="center" style="padding:24px 16px;">
              <div style="font-size:{size}px;line-height:1.2;font-weight:800;letter-spacing:{spacing}px;white-space:nowrap;color:{BRAND_STRONG};font-family:'SF Mono',Menlo,Consolas,monospace;">{e(code)}</div>
              <div style="margin-top:12px;font-size:14px;color:{_TEXT_SUB};">이 코드는 <strong style="color:{_TEXT};">{minutes}분</strong> 동안 한 번만 쓸 수 있습니다.</div>
            </td></tr>
          </table>
        </td></tr>{button}
        <tr><td style="padding:24px 32px 32px;">
          <div style="border-top:1px solid {_LINE};padding-top:20px;">
            <p style="margin:0;font-size:13px;line-height:1.6;color:{_TEXT_SUB};">{e(ignore)}</p>{contact}
          </div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
"""
