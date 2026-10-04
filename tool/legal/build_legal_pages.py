#!/usr/bin/env python3
"""공개 URL 로 여는 개인정보 처리방침·이용약관 페이지를 만든다(#3005).

앱 안의 두 문서(회원 앱·트레이너 웹의 ARB)가 원본이다. 스토어 심사와 가입 전
안내는 앱 밖에서 열리는 주소를 요구하므로, 같은 본문을 정적 HTML 로 옮겨
`legal/privacy.html`·`legal/terms.html` 에 둔다. 손으로 따로 고치면 앱과 공개
페이지가 금방 갈라지므로 이 스크립트가 만든 결과만 커밋한다.

읽는 것
  - `frontend/flutter/lib/l10n/app_{ko,en}.arb` — 회원 앱 문서
  - `frontend/flutter_trainer/lib/l10n/app_{ko,en}.arb` — 트레이너 웹 문서
  - `shared/oncare_core/lib/legal_contact.dart` — 보호책임자 연락처(한 곳의 정의)
  - `index.html` — 랜딩의 색 토큰(`:root`)·글꼴·로고. 페이지가 랜딩과 같은 모양을
    하도록 그대로 옮겨 온다. 랜딩을 바꾸면 `--check` 가 다시 만들라고 알린다.

사용법:
  build_legal_pages.py           # legal/*.html 을 다시 만든다
  build_legal_pages.py --check   # 커밋된 파일이 원본과 같은지만 본다(CI)

`--check` 는 다르면 GitHub Actions 주석(`::error file=...::`)을 찍고 1 로 끝난다.
보호책임자 연락처가 아직 데모 도메인이면 실패 대신 `::warning::` 을 찍는다 —
운영 연락처는 팀이 정할 값이라 그때까지 빌드를 막지 않는다.
외부 패키지 없이 표준 라이브러리만 쓴다.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "legal"
CONTACT_FILE = ROOT / "shared" / "oncare_core" / "lib" / "legal_contact.dart"
LANDING = ROOT / "index.html"

#: 데모·예시용 도메인. 운영 연락처가 정해지기 전까지 경고만 한다.
DEMO_EMAIL_DOMAINS = ("oncare.com", "oncare.demo", "example.com")

_CONTACT_RE = re.compile(r"privacyOfficerEmail\s*=\s*'([^']+)'")
_ROOT_TOKENS_RE = re.compile(r":root\s*\{[^}]*\}")
_FONT_RE = re.compile(r'href="(https://fonts\.googleapis\.com/css2[^"]+)"')
_LOGO_RE = re.compile(r'<img src="(data:image/png;base64,[^"]+)" alt="On-Care"')

#: 조·항 제목 줄. 한국어 `제N조 (…)`, 회원 영문 `Article N (…)`, 처리방침과
#: 트레이너 영문 약관의 `N. 제목`, 부칙.
_HEADING_RE = re.compile(
    r"^(제\d+조 .+|Article \d+ .+|\d{1,2}\. .+|부칙|Addendum)$"
)
#: 항·호 줄. 원문자(①…⑳), 영문의 `(1) `, 줄표 목록.
_ITEM_RE = re.compile(r"^([①-⑳]|\(\d+\) )")
_DASH = "- "


@dataclass(frozen=True)
class Source:
    """한 앱·한 언어의 문서 묶음."""

    anchor: str
    app: str
    lang: str
    label: str


SOURCES: tuple[Source, ...] = (
    Source("member-ko", "flutter", "ko", "회원 앱"),
    Source("trainer-ko", "flutter_trainer", "ko", "트레이너 웹"),
    Source("member-en", "flutter", "en", "Member app"),
    Source("trainer-en", "flutter_trainer", "en", "Trainer web"),
)


@dataclass(frozen=True)
class Doc:
    """만들 페이지 하나."""

    slug: str
    title_key: str
    body_key: str
    date_key: str
    heading: str
    lead: str


DOCS: tuple[Doc, ...] = (
    Doc(
        "privacy",
        "myLegalPrivacyTitle",
        "myLegalPrivacyBody",
        "myLegalPrivacyEffectiveDate",
        "개인정보 처리방침",
        "On-Care 회원 앱과 트레이너 웹이 개인정보를 어떻게 모으고 쓰고 지키는지 "
        "안내합니다. 앱 안의 처리방침과 같은 글입니다.",
    ),
    Doc(
        "terms",
        "myLegalTermsTitle",
        "myLegalTermsBody",
        "myLegalTermsEffectiveDate",
        "이용약관",
        "On-Care 회원 앱과 트레이너 웹을 쓰는 조건을 안내합니다. "
        "앱 안의 약관과 같은 글입니다.",
    ),
)


# --------------------------------------------------------------------------
# 읽기
# --------------------------------------------------------------------------


def read_contact(path: Path = CONTACT_FILE) -> str:
    """`LegalContact.privacyOfficerEmail` 의 값."""
    match = _CONTACT_RE.search(path.read_text(encoding="utf-8"))
    if match is None:
        raise ValueError(f"{path}: privacyOfficerEmail 상수를 찾지 못했다")
    return match.group(1)


def read_arb(app: str, lang: str, root: Path = ROOT) -> dict[str, object]:
    path = root / "frontend" / app / "lib" / "l10n" / f"app_{lang}.arb"
    return json.loads(path.read_text(encoding="utf-8"))


@dataclass(frozen=True)
class Landing:
    """랜딩에서 옮겨 오는 모양."""

    root_tokens: str
    font_href: str
    logo_src: str


def read_landing(path: Path = LANDING) -> Landing:
    text = path.read_text(encoding="utf-8")
    tokens = _ROOT_TOKENS_RE.search(text)
    font = _FONT_RE.search(text)
    logo = _LOGO_RE.search(text)
    if tokens is None or font is None or logo is None:
        raise ValueError(f"{path}: :root 토큰·글꼴·로고 중 하나를 찾지 못했다")
    return Landing(
        root_tokens=_dedent_block(tokens.group(0)),
        font_href=font.group(1),
        logo_src=logo.group(1),
    )


def _dedent_block(block: str) -> str:
    lines = [line.strip() for line in block.splitlines()]
    out = [lines[0]]
    out.extend(f"  {line}" for line in lines[1:-1] if line)
    out.append(lines[-1])
    return "\n".join(f"    {line}" for line in out)


def is_demo_contact(email: str) -> bool:
    domain = email.rsplit("@", 1)[-1].lower()
    return domain in DEMO_EMAIL_DOMAINS


# --------------------------------------------------------------------------
# 본문 → HTML
# --------------------------------------------------------------------------


def _inline(text: str, contact: str) -> str:
    """한 줄을 HTML 로. 연락처는 메일 링크로 바꾼다."""
    escaped = html.escape(text, quote=False)
    if contact:
        target = html.escape(contact, quote=False)
        link = f'<a href="mailto:{html.escape(contact)}">{target}</a>'
        escaped = escaped.replace(target, link)
    return escaped


def render_body(body: str, contact: str) -> str:
    """ARB 본문 한 편을 제목·문단·목록으로 나눈다.

    빈 줄은 문단 사이다. 조·항 제목은 `h3`, 원문자·`(n)` 항과 줄표 목록은
    `li`, 나머지는 `p` 다. 원문의 글자는 하나도 바꾸지 않는다(줄표만 목록 기호로).
    """
    out: list[str] = []
    list_kind: str | None = None

    def close_list() -> None:
        nonlocal list_kind
        if list_kind is not None:
            out.append("</ul>")
            list_kind = None

    def open_list(kind: str) -> None:
        nonlocal list_kind
        if list_kind != kind:
            close_list()
            out.append(f'<ul class="{kind}">')
            list_kind = kind

    for raw in body.split("\n"):
        line = raw.strip()
        if not line:
            close_list()
            continue
        if _HEADING_RE.match(line):
            close_list()
            out.append(f"<h3>{_inline(line, contact)}</h3>")
        elif line.startswith(_DASH):
            open_list("dash")
            out.append(f"<li>{_inline(line[len(_DASH):], contact)}</li>")
        elif _ITEM_RE.match(line):
            open_list("clause")
            out.append(f"<li>{_inline(line, contact)}</li>")
        else:
            close_list()
            out.append(f"<p>{_inline(line, contact)}</p>")
    close_list()
    return "\n".join(f"          {line}" for line in out)


# --------------------------------------------------------------------------
# 페이지
# --------------------------------------------------------------------------

_STYLE = """
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    html { scroll-behavior: smooth; }
    body {
      font-family: var(--font);
      background: var(--bg);
      color: var(--text);
      line-height: 1.75;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      overflow-wrap: anywhere;
    }
    a { color: var(--brand); }
    .wrap { max-width: 860px; margin: 0 auto; padding: 0 16px; }
    nav { position: sticky; top: 0; z-index: 10; background: rgba(245,249,252,.9); backdrop-filter: saturate(180%) blur(14px); border-bottom: 1px solid var(--line-soft); }
    .nav-inner { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 60px; flex-wrap: wrap; }
    .nav-logo { display: flex; align-items: center; gap: 9px; font-weight: 800; font-size: 1.08rem; color: var(--ink); text-decoration: none; letter-spacing: -.01em; }
    .nav-logo img { width: 28px; height: 28px; display: block; }
    .nav-links { display: flex; gap: 6px; flex-wrap: wrap; }
    .nav-links a { font-size: .88rem; font-weight: 600; color: var(--muted); text-decoration: none; padding: 6px 12px; border-radius: 999px; }
    .nav-links a[aria-current="page"] { background: var(--brand-soft); color: var(--brand); }
    header { padding: 40px 0 20px; }
    .eyebrow { font-size: .78rem; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; color: var(--brand); }
    h1 { font-size: clamp(1.6rem, 5vw, 2.2rem); line-height: 1.3; color: var(--ink); margin: 6px 0 10px; letter-spacing: -.02em; }
    .lead { color: var(--muted); font-size: .98rem; }
    .toc { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 18px; }
    .toc a { font-size: .86rem; font-weight: 600; text-decoration: none; color: var(--ink-soft); background: var(--card); border: 1px solid var(--line); border-radius: 999px; padding: 6px 14px; }
    main { padding-bottom: 48px; }
    .doc { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); padding: 24px 20px; margin-top: 20px; scroll-margin-top: 76px; }
    .doc h2 { font-size: 1.2rem; color: var(--ink); line-height: 1.4; }
    .doc .date { font-size: .85rem; color: var(--faint); margin-top: 2px; }
    .doc .body { margin-top: 16px; border-top: 1px solid var(--line-soft); padding-top: 8px; }
    .doc h3 { font-size: 1rem; color: var(--ink); margin-top: 20px; }
    .doc p { margin-top: 8px; font-size: .95rem; }
    .doc ul { margin-top: 8px; font-size: .95rem; }
    .doc ul.clause { list-style: none; }
    .doc ul.clause li { margin-top: 6px; }
    .doc ul.dash { padding-left: 1.25em; }
    .doc ul.dash li { margin-top: 4px; }
    .doc ul.dash li::marker { color: var(--faint); }
    footer { background: var(--ink); color: #9db4c4; padding: 28px 0; font-size: .84rem; }
    footer .wrap { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 10px; }
    footer a { color: #fff; text-decoration: none; }
    @media (min-width: 720px) {
      .doc { padding: 32px 36px; }
    }
""".strip("\n")


def render_page(doc: Doc, contact: str, landing: Landing, root: Path = ROOT) -> str:
    sections: list[str] = []
    chips: list[str] = []
    for source in SOURCES:
        arb = read_arb(source.app, source.lang, root)
        body = str(arb[doc.body_key]).replace("{contact}", contact)
        title = html.escape(f"{source.label} · {arb[doc.title_key]}", quote=False)
        date = html.escape(str(arb[doc.date_key]), quote=False)
        chips.append(f'        <a href="#{source.anchor}">{title}</a>')
        sections.append(
            "\n".join(
                [
                    f'      <section class="doc" id="{source.anchor}" lang="{source.lang}">',
                    f"        <h2>{title}</h2>",
                    f'        <p class="date">{date}</p>',
                    '        <div class="body">',
                    render_body(body, contact),
                    "        </div>",
                    "      </section>",
                ]
            )
        )

    nav_links = "\n".join(
        f'        <a href="{d.slug}.html"'
        + (' aria-current="page"' if d.slug == doc.slug else "")
        + f">{d.heading}</a>"
        for d in DOCS
    )
    description = html.escape(doc.lead)
    return "\n".join(
        [
            "<!DOCTYPE html>",
            "<!-- tool/legal/build_legal_pages.py 가 만든 파일입니다. 직접 고치지 말고 앱 ARB 를 고친 뒤 다시 만드세요. -->",
            '<html lang="ko">',
            "<head>",
            '  <meta charset="UTF-8" />',
            '  <meta name="viewport" content="width=device-width, initial-scale=1.0" />',
            f"  <title>{doc.heading} · On-Care</title>",
            f'  <meta name="description" content="{description}" />',
            '  <meta name="theme-color" content="#f5f9fc" />',
            f'  <link rel="icon" type="image/png" href="{landing.logo_src}" />',
            '  <link rel="preconnect" href="https://fonts.googleapis.com" />',
            '  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />',
            f'  <link href="{landing.font_href}" rel="stylesheet" />',
            "  <style>",
            landing.root_tokens,
            _STYLE,
            "  </style>",
            "</head>",
            "<body>",
            "  <nav>",
            '    <div class="wrap nav-inner">',
            f'      <a href="../" class="nav-logo"><img src="{landing.logo_src}" alt="On-Care" />On-Care</a>',
            '      <div class="nav-links">',
            nav_links,
            "      </div>",
            "    </div>",
            "  </nav>",
            "  <header>",
            '    <div class="wrap">',
            '      <p class="eyebrow">On-Care Legal</p>',
            f"      <h1>{doc.heading}</h1>",
            f'      <p class="lead">{html.escape(doc.lead, quote=False)}</p>',
            '      <div class="toc">',
            "\n".join(chips),
            "      </div>",
            "    </div>",
            "  </header>",
            "  <main>",
            '    <div class="wrap">',
            "\n".join(sections),
            "    </div>",
            "  </main>",
            "  <footer>",
            '    <div class="wrap">',
            "      <span>© 2026 On-Care Team</span>",
            '      <a href="../">On-Care 소개로 돌아가기</a>',
            "    </div>",
            "  </footer>",
            "</body>",
            "</html>",
            "",
        ]
    )


def build(root: Path = ROOT) -> dict[Path, str]:
    """만들 파일 경로 → 내용."""
    contact = read_contact(root / CONTACT_FILE.relative_to(ROOT))
    landing = read_landing(root / LANDING.relative_to(ROOT))
    out_dir = root / OUT_DIR.relative_to(ROOT)
    return {
        out_dir / f"{doc.slug}.html": render_page(doc, contact, landing, root)
        for doc in DOCS
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="파일을 쓰지 않고 커밋된 결과가 원본과 같은지만 본다",
    )
    args = parser.parse_args(argv)

    contact = read_contact()
    if is_demo_contact(contact):
        print(
            f"::warning file={CONTACT_FILE.relative_to(ROOT)}::"
            f"개인정보 보호책임자 연락처가 아직 데모 도메인({contact})입니다. "
            "운영 연락처를 정하면 이 상수를 바꾸고 페이지를 다시 만드세요."
        )

    pages = build()
    if args.check:
        stale = [
            path
            for path, text in pages.items()
            if not path.exists() or path.read_text(encoding="utf-8") != text
        ]
        for path in stale:
            print(
                f"::error file={path.relative_to(ROOT)}::"
                "공개 정책 페이지가 앱 문서·랜딩과 다릅니다. "
                "python3 tool/legal/build_legal_pages.py 로 다시 만들어 커밋하세요."
            )
        return 1 if stale else 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path, text in pages.items():
        path.write_text(text, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
