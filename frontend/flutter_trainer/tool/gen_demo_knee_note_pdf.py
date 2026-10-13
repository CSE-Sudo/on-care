#!/usr/bin/env python3
"""데모 대화의 재진 소견서 PDF 를 만든다(#3416).

트레이너 웹 데모에서 서유나 회원이 채팅으로 보낸 정형외과 재진 소견서
(`assets/demo/knee-follow-up-note.pdf`)를 만드는 스크립트다. 앱이 쓰는 pdf
패키지는 TrueType(glyf) 글꼴만 실을 수 있는데 앱이 번들하는 Pretendard 는
CFF(OTF)라서, 실행 중에 한글 문서를 그리지 못한다. 그래서 문서를 미리 만들어
데모 자산으로 싣는다 — 트레이너가 보낸 운동 안내 PDF(#2663)와 같은 방식이다.

글꼴은 앱이 이미 싣고 있는 Pretendard(SIL OFL 1.1, `assets/fonts/`)를 쓰고,
문서에 나오는 글자만 남긴 부분 집합으로 넣는다. 본문을 고치면 이 파일의
`TITLE`·`LINES` 를 고친 뒤 다시 돌리고, 시드 키(`trainer_seeded_v<N>`)를 올린다.

본문은 `test/core/storage/demo_chat_thread_test.dart` 의 `kKneeNoteLines` 와
같아야 한다 — 한쪽만 고치면 그 테스트가 깨진다.

준비: python3 -m pip install pymupdf fonttools
실행: python3 frontend/flutter_trainer/tool/gen_demo_knee_note_pdf.py

같은 도구 버전이면 다시 만들어도 같은 바이트가 나온다(저장소의 파일은
pymupdf 1.28.2 · fonttools 4.63.0). 버전이 다르면 파일 머리의 도구 표기와 압축
결과가 달라질 수 있으니, 다시 만든 뒤에는 `pdftotext` 로 글을, `pdftoppm` 등으로
그림을 한 번 확인한다.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

import pymupdf
from fontTools import subset
from fontTools.ttLib import TTFont

APP_DIR = Path(__file__).resolve().parent.parent
FONT_DIR = APP_DIR / "assets" / "fonts"
OUTPUT = APP_DIR / "assets" / "demo" / "knee-follow-up-note.pdf"

TITLE = "정형외과 재진 소견서"
LINES = (
    "부위: 오른쪽 무릎",
    "소견: 부기가 가라앉았고 가동범위는 정상 범위입니다.",
    "권고: 저강도 걷기를 다시 시작해도 됩니다.",
    "깊은 스쿼트는 2주 더 피하세요.",
)

# A4(pt). 여백·글자 크기는 서류 한 쪽의 모양일 뿐 앱 화면 규격과 무관하다.
PAGE_WIDTH, PAGE_HEIGHT = 595, 842
MARGIN = 72
TITLE_SIZE, BODY_SIZE = 20, 12
RULE_GAP, LINE_GAP = 14, 26


def subset_font(weight: str, text: str) -> bytes:
    """[text] 의 글자만 남긴 Pretendard 한 굵기.

    글꼴 전체를 넣으면 파일이 수백 KB 가 된다. PyMuPDF 의 `subset_fonts()` 는
    이 글꼴에서 다른 글자를 그리므로, 넣기 전에 fontTools 로 줄인다.
    """
    font = TTFont(FONT_DIR / f"Pretendard-{weight}.otf")
    options = subset.Options()
    options.layout_features = []
    options.drop_tables += ["GSUB", "GPOS", "GDEF"]
    options.name_IDs = [1, 2, 4, 6]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    _renumber_cids(font)
    # 수정 시각을 고정해 다시 만들어도 같은 바이트가 나오게 한다.
    font.recalcTimestamp = False
    font["head"].modified = font["head"].created
    out = io.BytesIO()
    font.save(out)
    return out.getvalue()


def _renumber_cids(font: TTFont) -> None:
    """글리프 이름(CID)을 글리프 순서와 같은 번호로 바꾼다.

    Pretendard 는 CID 글꼴이라 글리프마다 순서(GID)와 별개인 번호(CID)가 있다.
    PDF 본문에는 순서가 적히는데, 뷰어에 따라 그 값을 순서로 읽기도 하고 CID 로
    읽어 글꼴 안의 표로 다시 찾기도 한다. 둘이 다르면 한쪽 뷰어에서 글자가
    비거나 다른 글자가 나온다 — 두 번호를 같게 해 어느 쪽으로 읽어도 맞게 한다.
    """
    old = font.getGlyphOrder()
    for tag in font.keys():
        font[tag]  # 옛 이름으로 모두 읽어 둔 뒤에 바꾼다.
    new = [".notdef"] + [f"cid{gid:05d}" for gid in range(1, len(old))]
    rename = dict(zip(old, new))
    top = font["CFF "].cff[0]
    strings = top.CharStrings
    strings.charStrings = {rename[k]: v for k, v in strings.charStrings.items()}
    top.charset = new
    for table in font["cmap"].tables:
        table.cmap = {code: rename[name] for code, name in table.cmap.items()}
    font["hmtx"].metrics = {rename[k]: v for k, v in font["hmtx"].metrics.items()}
    font.setGlyphOrder(new)


def build() -> bytes:
    doc = pymupdf.open()
    page = doc.new_page(width=PAGE_WIDTH, height=PAGE_HEIGHT)
    page.insert_font(fontname="bold", fontbuffer=subset_font("Bold", TITLE))
    page.insert_font(
        fontname="regular", fontbuffer=subset_font("Regular", "".join(LINES))
    )

    y = MARGIN + TITLE_SIZE
    page.insert_text((MARGIN, y), TITLE, fontname="bold", fontsize=TITLE_SIZE)
    y += RULE_GAP
    page.draw_line((MARGIN, y), (PAGE_WIDTH - MARGIN, y), width=0.8)
    y += LINE_GAP + 4
    for line in LINES:
        page.insert_text((MARGIN, y), line, fontname="regular", fontsize=BODY_SIZE)
        y += LINE_GAP

    # 만든 시각·도구 이름을 지워 다시 만들어도 같은 바이트가 나오게 한다.
    doc.set_metadata({})
    return doc.tobytes(garbage=4, deflate=True, clean=True, no_new_id=True)


def main() -> int:
    data = build()
    OUTPUT.write_bytes(data)
    print(f"{OUTPUT.relative_to(APP_DIR)} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
