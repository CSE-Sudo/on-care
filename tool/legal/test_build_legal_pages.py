"""공개 정책 페이지 생성기의 경계 검사(#3005).

생성기가 틀리면 스토어에 적은 처리방침 주소가 앱과 다른 글을 보여 준다. 본문 변환
규칙(제목·항·목록·이스케이프·연락처 링크), 랜딩 모양 옮기기, `--check` 의 통과·실패를
임시 저장소로 확인한다. 표준 라이브러리만 쓴다.
"""

from __future__ import annotations

import io
import json
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_legal_pages as blp  # noqa: E402


class RenderBodyTest(unittest.TestCase):
    def test_articles_become_headings(self) -> None:
        html = blp.render_body("제1조 (목적)\n이 약관은 목적을 정합니다.", "")
        self.assertIn("<h3>제1조 (목적)</h3>", html)
        self.assertIn("<p>이 약관은 목적을 정합니다.</p>", html)

    def test_english_and_numbered_headings(self) -> None:
        html = blp.render_body(
            "Article 12 (Changes)\n\n3. Retention\n\nAddendum\n부칙", ""
        )
        for heading in ("Article 12 (Changes)", "3. Retention", "Addendum", "부칙"):
            self.assertIn(f"<h3>{heading}</h3>", html)

    def test_clauses_keep_their_marker(self) -> None:
        html = blp.render_body("① 첫째 항\n② 둘째 항\n(3) third", "")
        self.assertEqual(html.count('<ul class="clause">'), 1)
        self.assertIn("<li>① 첫째 항</li>", html)
        self.assertIn("<li>(3) third</li>", html)

    def test_dash_items_drop_only_the_dash(self) -> None:
        html = blp.render_body("- 접속 기록: 1년\n- 탈퇴 기록: 2년", "")
        self.assertEqual(html.count('<ul class="dash">'), 1)
        self.assertIn("<li>접속 기록: 1년</li>", html)

    def test_blank_line_closes_a_list(self) -> None:
        html = blp.render_body("- a\n\n- b", "")
        self.assertEqual(html.count('<ul class="dash">'), 2)

    def test_text_is_escaped(self) -> None:
        html = blp.render_body('A <b>bold</b> & "quoted"', "")
        self.assertIn("&lt;b&gt;bold&lt;/b&gt; &amp;", html)
        self.assertNotIn("<b>", html)

    def test_contact_becomes_a_mail_link(self) -> None:
        html = blp.render_body("연락처: privacy@team.example", "privacy@team.example")
        self.assertIn(
            '<a href="mailto:privacy@team.example">privacy@team.example</a>', html
        )

    def test_a_sentence_that_mentions_a_number_is_not_a_heading(self) -> None:
        html = blp.render_body("회사는 2. 항에 따라 처리합니다.", "")
        self.assertNotIn("<h3>", html)


class ContactTest(unittest.TestCase):
    def test_reads_the_single_definition(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "legal_contact.dart"
            path.write_text(
                "abstract final class LegalContact {\n"
                "  static const String privacyOfficerEmail = 'dpo@team.example';\n"
                "}\n",
                encoding="utf-8",
            )
            self.assertEqual(blp.read_contact(path), "dpo@team.example")

    def test_missing_constant_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "legal_contact.dart"
            path.write_text("// nothing\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                blp.read_contact(path)

    def test_demo_domains_are_flagged(self) -> None:
        self.assertTrue(blp.is_demo_contact("support@oncare.com"))
        self.assertTrue(blp.is_demo_contact("a@ONCARE.DEMO"))
        self.assertFalse(blp.is_demo_contact("privacy@realcompany.co.kr"))

    def test_repository_contact_is_read(self) -> None:
        self.assertIn("@", blp.read_contact())

    def test_repository_contact_is_not_a_demo_domain(self) -> None:
        # 공개 페이지가 싣는 연락처는 팀이 메일을 받는 주소다(#3132).
        contact = blp.read_contact()
        self.assertFalse(blp.is_demo_contact(contact), contact)
        self.assertEqual(contact, "sudo.capstone@gmail.com")


def _fake_repo(root: Path, *, contact: str = "dpo@team.example") -> None:
    """생성기가 읽는 파일만 가진 작은 저장소."""
    for app in ("flutter", "flutter_trainer"):
        for lang in ("ko", "en"):
            path = root / "frontend" / app / "lib" / "l10n" / f"app_{lang}.arb"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                json.dumps(
                    {
                        "myLegalPrivacyTitle": f"Privacy {app} {lang}",
                        "myLegalPrivacyBody": "1. Officer\nContact: {contact}",
                        "myLegalPrivacyEffectiveDate": "2026-10-03",
                        "myLegalTermsTitle": f"Terms {app} {lang}",
                        "myLegalTermsBody": "제1조 (목적)\n① 항",
                        "myLegalTermsEffectiveDate": "2026-10-03",
                        # 위치기반서비스 이용약관은 회원 앱에만 있다(#3136).
                        **(
                            {
                                "myLegalLocationTitle": f"Location {lang}",
                                "myLegalLocationBody": "제1조 (목적)\n- 연락처: {contact}",
                                "myLegalLocationEffectiveDate": "2026-10-05",
                            }
                            if app == "flutter"
                            else {}
                        ),
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
    contact_file = root / "shared" / "oncare_core" / "lib" / "legal_contact.dart"
    contact_file.parent.mkdir(parents=True, exist_ok=True)
    contact_file.write_text(
        f"static const String privacyOfficerEmail = '{contact}';\n", encoding="utf-8"
    )
    (root / "index.html").write_text(
        "<link href=\"https://fonts.googleapis.com/css2?family=X\" rel=\"stylesheet\" />\n"
        "<style>\n  :root {\n    --brand: #1580bd;\n  }\n</style>\n"
        '<img src="data:image/png;base64,AAAA" alt="On-Care" />\n',
        encoding="utf-8",
    )


class BuildTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        _fake_repo(self.tmp)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    def test_builds_both_pages_with_four_sections(self) -> None:
        pages = blp.build(self.tmp)
        self.assertEqual(
            sorted(p.name for p in pages),
            ["location.html", "privacy.html", "terms.html"],
        )
        privacy = pages[self.tmp / "legal" / "privacy.html"]
        for anchor in ("member-ko", "trainer-ko", "member-en", "trainer-en"):
            self.assertIn(f'id="{anchor}"', privacy)
            self.assertIn(f'href="#{anchor}"', privacy)
        self.assertIn('lang="en"', privacy)

    def test_placeholder_is_filled_with_the_contact(self) -> None:
        privacy = blp.build(self.tmp)[self.tmp / "legal" / "privacy.html"]
        self.assertNotIn("{contact}", privacy)
        self.assertIn('href="mailto:dpo@team.example"', privacy)

    def test_landing_look_is_carried_over(self) -> None:
        terms = blp.build(self.tmp)[self.tmp / "legal" / "terms.html"]
        self.assertIn("--brand: #1580bd;", terms)
        self.assertIn("https://fonts.googleapis.com/css2?family=X", terms)
        self.assertIn('src="data:image/png;base64,AAAA"', terms)
        # 랜딩으로 돌아가는 길은 상대 경로다 — 배포마다 자기 도메인으로 간다.
        self.assertIn('href="../"', terms)
        self.assertNotIn("http://", terms)

    def test_pages_need_no_script(self) -> None:
        for text in blp.build(self.tmp).values():
            self.assertNotIn("<script", text)

    def test_current_page_is_marked_in_the_nav(self) -> None:
        pages = blp.build(self.tmp)
        self.assertIn(
            'href="terms.html" aria-current="page"',
            pages[self.tmp / "legal" / "terms.html"],
        )
        self.assertIn(
            'href="privacy.html" aria-current="page"',
            pages[self.tmp / "legal" / "privacy.html"],
        )

    def test_location_terms_carry_only_the_member_app(self) -> None:
        """위치를 쓰는 것은 회원 앱뿐이다 — 트레이너 웹 절은 없다(#3136)."""
        location = blp.build(self.tmp)[self.tmp / "legal" / "location.html"]
        for anchor in ("member-ko", "member-en"):
            self.assertIn(f'id="{anchor}"', location)
        for anchor in ("trainer-ko", "trainer-en"):
            self.assertNotIn(f'id="{anchor}"', location)
        self.assertNotIn("{contact}", location)
        self.assertIn('href="mailto:dpo@team.example"', location)
        self.assertIn('href="location.html" aria-current="page"', location)

    def test_every_page_links_every_document(self) -> None:
        for text in blp.build(self.tmp).values():
            for slug in ("privacy", "terms", "location"):
                self.assertIn(f'href="{slug}.html"', text)

    def test_doc_sources_keep_the_source_order(self) -> None:
        doc = next(d for d in blp.DOCS if d.slug == "location")
        self.assertEqual(
            [s.anchor for s in doc.sources()], ["member-ko", "member-en"]
        )
        privacy = next(d for d in blp.DOCS if d.slug == "privacy")
        self.assertEqual(privacy.sources(), blp.SOURCES)

    def test_build_is_deterministic(self) -> None:
        self.assertEqual(blp.build(self.tmp), blp.build(self.tmp))

    def test_landing_without_tokens_is_an_error(self) -> None:
        (self.tmp / "index.html").write_text("<html></html>", encoding="utf-8")
        with self.assertRaises(ValueError):
            blp.build(self.tmp)


class RepositoryPagesTest(unittest.TestCase):
    """커밋된 `legal/*.html` 이 지금 원본과 같은지 — `--check` 와 같은 판단."""

    def test_committed_pages_are_current(self) -> None:
        for path, text in blp.build().items():
            self.assertTrue(path.exists(), f"{path} 가 없다 — 생성기를 돌려 커밋하세요")
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                text,
                f"{path.name} 가 낡았다 — python3 tool/legal/build_legal_pages.py",
            )

    def test_landing_links_every_public_document(self) -> None:
        landing = (blp.ROOT / "index.html").read_text(encoding="utf-8")
        for doc in blp.DOCS:
            self.assertIn(f'href="legal/{doc.slug}.html"', landing, doc.slug)

    def test_check_passes_on_the_repository(self) -> None:
        with redirect_stdout(io.StringIO()):
            self.assertEqual(blp.main(["--check"]), 0)

    def test_check_leaves_no_demo_contact_warning(self) -> None:
        # 운영 연락처로 바꾼 뒤에는 `--check` 가 데모 도메인 경고를 찍지 않는다(#3132).
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(blp.main(["--check"]), 0)
        self.assertNotIn("::warning", out.getvalue())

    def test_published_privacy_page_carries_the_team_contact(self) -> None:
        privacy = (blp.OUT_DIR / "privacy.html").read_text(encoding="utf-8")
        self.assertEqual(
            privacy.count('href="mailto:sudo.capstone@gmail.com"'), len(blp.SOURCES)
        )
        self.assertNotIn("@oncare.com", privacy)

    def test_every_source_document_is_published(self) -> None:
        pages = blp.build()
        for doc in blp.DOCS:
            text = pages[blp.OUT_DIR / f"{doc.slug}.html"]
            for source in doc.sources():
                arb = blp.read_arb(source.app, source.lang)
                first_line = str(arb[doc.body_key]).split("\n", 1)[0]
                escaped = (
                    first_line.replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                )
                self.assertIn(escaped, text, f"{doc.slug} {source.anchor}")


if __name__ == "__main__":
    unittest.main()
