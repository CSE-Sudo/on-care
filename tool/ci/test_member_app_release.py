"""회원 앱 서명 빌드 워크플로 정적 검사(#3148).

`.github/workflows/member-app-release.yml` 은 실제 비밀이 있어야 끝까지 돈다. 비밀 없이도
병합 전에 다음을 본다.

* 실행 조건: 수동 실행·`member-app-v*` 태그, 비밀 게이트 출력으로만 빌드 잡이 돈다.
* 비밀이 없으면 실패가 아니라 안내(notice)와 함께 건너뛴다.
* 빌드 전에 define 파일 검사가 돌고, 빌드는 define 파일 하나로만 한다.
* 키스토어·key.properties·인증서·키체인·define 파일이 지워지고 아티팩트에 실리지 않으며,
  비밀 값이 셸 본문에 직접 보간되지 않는다.
* 액션이 SHA 로 고정되고 Flutter 버전이 회원 앱 CI 와 같다.
* 문서(docs/mobile_release.md)가 워크플로가 읽는 비밀·변수를 모두 적는다.
* 보조 스크립트(define 파일 쓰기, iOS 수동 서명) 단위 동작.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import json
import os
import plistlib
import re
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_action_pins  # noqa: E402
import ios_release_signing as signing  # noqa: E402
import write_release_defines as defines  # noqa: E402

REPO_ROOT = HERE.parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "member-app-release.yml"
USER_APP_CI = REPO_ROOT / ".github" / "workflows" / "user-app-ci.yml"
INFRA_CI = REPO_ROOT / ".github" / "workflows" / "infra-ci.yml"
DOC = REPO_ROOT / "docs" / "mobile_release.md"
PBXPROJ = REPO_ROOT / "frontend" / "flutter" / "ios" / "Runner.xcodeproj" / "project.pbxproj"
BUNDLE_ID = "com.csesudo.oncare"
FROM_FILE = "--dart-define-from-file=config/release.json"
CHECKER = "bash tool/check_release_defines.sh config/release.json"
ANDROID_SECRETS = {
    "ANDROID_UPLOAD_KEYSTORE_BASE64",
    "ANDROID_UPLOAD_STORE_PASSWORD",
    "ANDROID_UPLOAD_KEY_ALIAS",
    "ANDROID_UPLOAD_KEY_PASSWORD",
}
IOS_SECRETS = {
    "IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64",
    "IOS_DISTRIBUTION_CERTIFICATE_PASSWORD",
    "IOS_PROVISIONING_PROFILE_BASE64",
}
SECRET_FILES = re.compile(r"key\.properties|\.jks|\.keystore|\.p12|\.mobileprovision|keychain|release\.json")


def workflow_text() -> str:
    return WORKFLOW.read_text(encoding="utf-8")


def jobs() -> dict[str, str]:
    """`jobs:` 아래 최상위 잡 이름 → 그 잡의 본문."""
    text = workflow_text().split("\njobs:\n", 1)[1]
    parts = re.split(r"(?m)^  ([A-Za-z0-9_-]+):\n", text)
    return {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}


def steps(job: str) -> list[str]:
    parts = re.split(r"(?m)^(?=      - (?:name|uses):)", job)
    return [part for part in parts if part.startswith("      - ")]


def step_named(job: str, name: str) -> str:
    found = [s for s in steps(job) if s.startswith(f"      - name: {name}\n")]
    if len(found) != 1:
        raise AssertionError(f"step '{name}' 를 정확히 하나 찾지 못했습니다({len(found)})")
    return found[0]


def run_body(step: str) -> str:
    """step 의 `run:` 본문(env 블록 제외)."""
    return step.split("        run:", 1)[1] if "        run:" in step else ""


def step_index(job: str, needle: str) -> int:
    for index, step in enumerate(steps(job)):
        if needle in step:
            return index
    raise AssertionError(f"'{needle}' 가 든 step 이 없습니다")


class TriggerAndGateTest(unittest.TestCase):
    def test_runs_on_dispatch_and_release_tags_only(self) -> None:
        head = workflow_text().split("\npermissions:", 1)[0]
        self.assertIn("  workflow_dispatch:\n", head)
        self.assertRegex(head, r'  push:\n    tags:\n      - "member-app-v\*"\n')
        self.assertNotIn("pull_request", head)
        self.assertNotIn("branches:", head)

    def test_read_only_token(self) -> None:
        self.assertIn("\npermissions:\n  contents: read\n", workflow_text())
        self.assertNotRegex(workflow_text(), r"(?m)^\s+\w+: write\s*$")

    def test_three_jobs_in_the_mobile_release_environment(self) -> None:
        all_jobs = jobs()
        self.assertEqual(set(all_jobs), {"gate", "android", "ios"})
        for name, body in all_jobs.items():
            with self.subTest(job=name):
                self.assertIn("    environment: mobile-release\n", body)
                # 운영 배포 Environment(AWS 역할)와 섞지 않는다.
                self.assertNotIn("environment: production", body)

    def test_build_jobs_run_only_when_the_gate_says_so(self) -> None:
        all_jobs = jobs()
        self.assertIn("    needs: gate\n    if: needs.gate.outputs.android == 'true'\n", all_jobs["android"])
        self.assertIn("    needs: gate\n    if: needs.gate.outputs.ios == 'true'\n", all_jobs["ios"])
        self.assertIn("runs-on: macos-", all_jobs["ios"])

    def test_gate_only_learns_whether_each_secret_exists(self) -> None:
        step = step_named(jobs()["gate"], "Check which signing secrets exist")
        referenced = set(re.findall(r"secrets\.([A-Z0-9_]+) != ''", step))
        self.assertEqual(referenced, ANDROID_SECRETS | IOS_SECRETS)
        # 값 자체(`${{ secrets.X }}`)는 게이트에 들어오지 않는다.
        self.assertNotRegex(step, r"\$\{\{ secrets\.[A-Z0-9_]+ \}\}")

    def test_missing_secrets_skip_with_a_notice_not_a_failure(self) -> None:
        body = run_body(step_named(jobs()["gate"], "Check which signing secrets exist"))
        self.assertIn('echo false', body)
        self.assertIn("::notice title=Android 서명 빌드 건너뜀::", body)
        self.assertIn("::notice title=iOS 서명 빌드 건너뜀::", body)
        self.assertIn("GITHUB_STEP_SUMMARY", body)
        # 일부만 있을 때만 실패한다.
        self.assertIn("::error::$label 서명 비밀이 일부만 있습니다", body)

    def test_gate_requires_main_or_a_matching_tag(self) -> None:
        body = run_body(step_named(jobs()["gate"], "Check the build source"))
        self.assertIn('"member-app-v$version"', body)
        self.assertIn('git merge-base --is-ancestor "$GITHUB_SHA" origin/main', body)
        self.assertIn('"$REF" = "refs/heads/main"', body)
        self.assertIn("fetch-depth: 0", jobs()["gate"])


class BuildStepsTest(unittest.TestCase):
    def test_define_file_is_checked_before_each_build(self) -> None:
        for name, build in (("android", "flutter build appbundle"), ("ios", "flutter build ipa")):
            job = jobs()[name]
            with self.subTest(job=name):
                write = step_index(job, "tool/ci/write_release_defines.py config/release.json")
                check = step_index(job, CHECKER)
                built = step_index(job, build)
                self.assertLess(write, check)
                self.assertLess(check, built)

    def test_demo_assets_are_stripped_before_each_build(self) -> None:
        # 데모 전용 자산(데모 시드 사진·데모 대화 첨부)은 스토어 빌드에 싣지 않는다(#3157).
        for name, build in (("android", "flutter build appbundle"), ("ios", "flutter build ipa")):
            job = jobs()[name]
            with self.subTest(job=name):
                strip = step_named(job, "Strip demo-only assets")
                self.assertIn("python3 ../tool/strip_demo_assets.py .", run_body(strip))
                self.assertLess(
                    step_index(job, "tool/strip_demo_assets.py"), step_index(job, build)
                )

    def test_builds_use_the_define_file_only(self) -> None:
        for name, build in (("android", "flutter build appbundle"), ("ios", "flutter build ipa")):
            job = jobs()[name]
            commands = [s for s in steps(job) if build in s]
            with self.subTest(job=name):
                self.assertEqual(len(commands), 1)
                joined = re.sub(r"\s*\\\n\s*", " ", commands[0])
                self.assertIn(f"{build} --release {FROM_FILE}", joined)
                self.assertNotIn("--dart-define=", joined)
                self.assertNotIn("--build-number", joined)
                self.assertNotIn("--build-name", joined)

    def test_release_defines_read_member_values(self) -> None:
        for name in ("android", "ios"):
            step = step_named(jobs()[name], "Write the release define file")
            with self.subTest(job=name):
                self.assertIn("APP_ENV: ${{ needs.gate.outputs.app_env }}", step)
                self.assertIn("API_BASE_URL: ${{ vars.MEMBER_APP_API_BASE_URL }}", step)
                # 운영 웹과 같은 회원 앱 DSN 비밀을 쓴다.
                self.assertIn("SENTRY_DSN: ${{ secrets.SENTRY_DSN_MEMBER }}", step)

    def test_flutter_version_matches_the_user_app_ci(self) -> None:
        pinned = re.search(r'FLUTTER_VERSION: "([0-9.]+)"', workflow_text())
        self.assertIsNotNone(pinned)
        ci_versions = set(re.findall(r"flutter-version: '([0-9.]+)'", USER_APP_CI.read_text(encoding="utf-8")))
        self.assertEqual(ci_versions, {pinned.group(1)})
        self.assertEqual(workflow_text().count("flutter-version: ${{ env.FLUTTER_VERSION }}"), 2)

    def test_android_bundle_signature_is_verified(self) -> None:
        body = run_body(step_named(jobs()["android"], "Verify the bundle signature"))
        self.assertIn("jarsigner\" -verify", body)
        self.assertIn("^jar verified", body)
        self.assertIn("CN=Android Debug", body)


class SecretHandlingTest(unittest.TestCase):
    def test_secrets_are_passed_through_env_not_interpolated_in_scripts(self) -> None:
        for name, job in jobs().items():
            for step in steps(job):
                with self.subTest(job=name, step=step.splitlines()[0]):
                    self.assertNotIn("secrets.", run_body(step))

    def test_no_shell_tracing(self) -> None:
        self.assertNotRegex(workflow_text(), r"set -[a-z]*x|set -o xtrace|bash -x")

    def test_checkouts_do_not_keep_the_token(self) -> None:
        text = workflow_text()
        self.assertEqual(text.count("uses: actions/checkout@"), 3)
        self.assertEqual(text.count("persist-credentials: false"), 3)

    def test_android_key_material_is_removed_on_exit(self) -> None:
        step = step_named(jobs()["android"], "Build the signed app bundle")
        body = run_body(step)
        self.assertIn('keystore="$RUNNER_TEMP/', body)
        self.assertIn("""trap 'rm -f "$keystore" android/key.properties' EXIT""", body)
        # trap 이 키를 쓰기 전에 걸려야 중간 실패에도 지워진다.
        self.assertLess(body.index("trap "), body.index("base64 --decode"))
        self.assertLess(body.index("trap "), body.index("> android/key.properties"))
        self.assertIn("umask 077", body)

    def test_ios_signing_material_is_removed_always(self) -> None:
        job = jobs()["ios"]
        install = run_body(step_named(job, "Install the signing certificate and profile"))
        self.assertIn('keychain_password="$(openssl rand -hex 24)"', install)
        self.assertLess(install.index("trap "), install.index("base64 --decode"))
        cleanup = step_named(job, "Remove signing material")
        self.assertIn("        if: always()\n", cleanup)
        removed = [
            "security delete-keychain",
            "distribution.p12",
            "member-app.mobileprovision",
            "$PROFILE_UUID.mobileprovision",
            "config/release.json",
        ]
        for needle in removed:
            self.assertIn(needle, cleanup)
        # 마지막 step 이어야 업로드까지 끝난 뒤 지운다.
        self.assertEqual(steps(job)[-1], cleanup)

    def test_android_define_file_is_removed_always(self) -> None:
        cleanup = steps(jobs()["android"])[-1]
        self.assertIn("        if: always()\n", cleanup)
        self.assertIn("rm -f config/release.json", cleanup)

    def test_artifacts_carry_only_the_build_and_its_info(self) -> None:
        uploads = [s for job in jobs().values() for s in steps(job) if "actions/upload-artifact@" in s]
        self.assertEqual(len(uploads), 2)
        for upload in uploads:
            paths = upload.split("path: |", 1)[1].split("if-no-files-found", 1)[0]
            entries = [line.strip() for line in paths.splitlines() if line.strip()]
            with self.subTest(upload=upload.splitlines()[0]):
                self.assertEqual(len(entries), 2)
                self.assertTrue(entries[0].endswith((".aab", ".ipa")), entries[0])
                self.assertTrue(entries[1].endswith("/build-info.txt"), entries[1])
                self.assertNotRegex(paths, SECRET_FILES)
                self.assertNotIn("*", paths)
                self.assertIn("if-no-files-found: error", upload)

    def test_build_info_never_prints_secret_values(self) -> None:
        for name in ("android", "ios"):
            step = step_named(jobs()[name], "Write build info")
            with self.subTest(job=name):
                self.assertNotIn("secrets.", step)
                self.assertNotIn("SENTRY_DSN", step)
                self.assertNotIn("key.properties", step)


class PinsAndLintTest(unittest.TestCase):
    def test_actions_are_pinned(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            code = check_action_pins.main([str(WORKFLOW)])
        self.assertEqual(code, 0, out.getvalue())

    def test_actionlint_covers_the_workflow(self) -> None:
        infra = INFRA_CI.read_text(encoding="utf-8")
        self.assertIn(".github/workflows/member-app-release.yml", infra.split("rhysd/actionlint", 1)[1])
        self.assertGreaterEqual(infra.count('- ".github/workflows/member-app-release.yml"'), 2)


class DocsTest(unittest.TestCase):
    def test_docs_list_every_secret_and_variable(self) -> None:
        doc = DOC.read_text(encoding="utf-8")
        names = set(re.findall(r"(?:secrets|vars)\.([A-Z0-9_]+)", workflow_text()))
        self.assertTrue(names >= ANDROID_SECRETS | IOS_SECRETS)
        for name in sorted(names):
            with self.subTest(name=name):
                self.assertIn(f"`{name}`", doc)

    def test_docs_explain_how_to_run(self) -> None:
        doc = DOC.read_text(encoding="utf-8")
        for needle in ("member-app-release.yml", "mobile-release", "member-app-v", "workflow_dispatch"):
            with self.subTest(needle=needle):
                self.assertIn(needle, doc)


class WriteReleaseDefinesTest(unittest.TestCase):
    def test_required_keys_are_always_written(self) -> None:
        self.assertEqual(
            defines.release_defines({"APP_ENV": "prod", "API_BASE_URL": "https://api.on-care.kr/v1",
                                     "SENTRY_DSN": "https://k@o.ingest.sentry.io/1"}),
            {"ENV": "prod", "USE_MOCK_API": "false", "API_BASE_URL": "https://api.on-care.kr/v1",
             "SENTRY_DSN": "https://k@o.ingest.sentry.io/1"},
        )

    def test_missing_required_values_stay_empty_for_the_checker(self) -> None:
        self.assertEqual(
            defines.release_defines({}),
            {"ENV": "", "USE_MOCK_API": "false", "API_BASE_URL": "", "SENTRY_DSN": ""},
        )

    def test_optional_keys_only_when_set(self) -> None:
        got = defines.release_defines({"KAKAO_JS_KEY": " abc ", "KAKAO_MAP_ORIGIN": "", "IOS_APP_STORE_ID": "123"})
        self.assertEqual(got["KAKAO_JS_KEY"], "abc")
        self.assertEqual(got["IOS_APP_STORE_ID"], "123")
        self.assertNotIn("KAKAO_MAP_ORIGIN", got)

    def test_mock_api_cannot_be_overridden(self) -> None:
        self.assertEqual(defines.release_defines({"USE_MOCK_API": "true"})["USE_MOCK_API"], "false")

    def test_writes_json_readable_only_by_owner(self) -> None:
        tricky = 'https://k"\\@o.ingest.sentry.io/1'
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "config" / "release.json"
            env = {"APP_ENV": "staging", "SENTRY_DSN": tricky}
            old = dict(os.environ)
            try:
                os.environ.clear()
                os.environ.update(env)
                with redirect_stdout(io.StringIO()) as printed:
                    self.assertEqual(defines.main([str(out)]), 0)
            finally:
                os.environ.clear()
                os.environ.update(old)
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data["SENTRY_DSN"], tricky)
            self.assertEqual(data["ENV"], "staging")
            self.assertEqual(stat.S_IMODE(out.stat().st_mode), 0o600)
            # 값은 출력하지 않는다.
            self.assertNotIn("sentry", printed.getvalue())

    def test_usage(self) -> None:
        with redirect_stderr(io.StringIO()):
            self.assertEqual(defines.main([]), 2)


def profile_plist(**overrides) -> bytes:
    data = {
        "UUID": "12345678-ABCD-ABCD-ABCD-123456789ABC",
        "Name": "On-Care App Store",
        "TeamIdentifier": ["UFM3HBFN93"],
        "Entitlements": {"application-identifier": f"UFM3HBFN93.{BUNDLE_ID}", "get-task-allow": False},
    }
    data.update(overrides)
    return plistlib.dumps(data)


class IosReleaseSigningTest(unittest.TestCase):
    def setUp(self) -> None:
        self.original = PBXPROJ.read_text(encoding="utf-8")
        self.profile = signing.read_profile(profile_plist(), BUNDLE_ID)

    def test_reads_an_app_store_profile(self) -> None:
        self.assertEqual(self.profile.uuid, "12345678-ABCD-ABCD-ABCD-123456789ABC")
        self.assertEqual(self.profile.team_id, "UFM3HBFN93")

    def test_rejects_profiles_for_other_apps_or_development(self) -> None:
        cases = {
            "다른 앱": {"Entitlements": {"application-identifier": "UFM3HBFN93.com.other.app"}},
            "와일드카드": {"Entitlements": {"application-identifier": "UFM3HBFN93.*"}},
            "개발용": {"Entitlements": {"application-identifier": f"UFM3HBFN93.{BUNDLE_ID}",
                                       "get-task-allow": True}},
            "Ad Hoc": {"ProvisionedDevices": ["00008030-000000000000000E"]},
            "UUID 형식": {"UUID": "not-a-uuid"},
            "팀 없음": {"TeamIdentifier": []},
            "이름 따옴표": {"Name": 'a"b'},
        }
        for label, override in cases.items():
            with self.subTest(case=label), self.assertRaises(signing.SigningError):
                signing.read_profile(profile_plist(**override), BUNDLE_ID)
        with self.assertRaises(signing.SigningError):
            signing.read_profile(b"not a plist", BUNDLE_ID)

    def test_only_the_runner_release_configuration_changes(self) -> None:
        patched = signing.apply_manual_signing(self.original, BUNDLE_ID, self.profile)
        release = [m for m in signing.CONFIG_BLOCK.finditer(patched)
                   if m.group("name") == "Release" and f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};" in m.group("body")]
        self.assertEqual(len(release), 1)
        body = release[0].group("body")
        self.assertIn("\t\t\t\tCODE_SIGN_STYLE = Manual;\n", body)
        self.assertIn('\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";\n', body)
        self.assertIn('\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";\n', body)
        self.assertIn('\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "12345678-ABCD-ABCD-ABCD-123456789ABC";\n', body)
        self.assertIn("\t\t\t\tDEVELOPMENT_TEAM = UFM3HBFN93;\n", body)
        # 다른 블록(Debug·Profile·RunnerTests·프로젝트 설정)은 그대로다.
        self.assertEqual(patched.count("PROVISIONING_PROFILE_SPECIFIER"), 1)
        self.assertEqual(patched.count("CODE_SIGN_STYLE = Manual"), 1)
        outside_new = patched.replace(body, "")
        outside_old = self.original.replace(
            [m for m in signing.CONFIG_BLOCK.finditer(self.original)
             if m.group("name") == "Release" and f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};" in m.group("body")][0]
            .group("body"), "")
        self.assertEqual(outside_new, outside_old)

    def test_patch_is_idempotent_and_keeps_multiline_settings(self) -> None:
        once = signing.apply_manual_signing(self.original, BUNDLE_ID, self.profile)
        twice = signing.apply_manual_signing(once, BUNDLE_ID, self.profile)
        self.assertEqual(once, twice)
        self.assertIn('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",', once)

    def test_team_comes_from_the_profile(self) -> None:
        other = signing.read_profile(
            profile_plist(TeamIdentifier=["ABCDE12345"],
                          Entitlements={"application-identifier": f"ABCDE12345.{BUNDLE_ID}"}),
            BUNDLE_ID,
        )
        patched = signing.apply_manual_signing(self.original, BUNDLE_ID, other)
        self.assertEqual(patched.count("DEVELOPMENT_TEAM = ABCDE12345;"), 1)

    def test_fails_when_the_release_block_is_not_unique(self) -> None:
        with self.assertRaises(signing.SigningError):
            signing.apply_manual_signing(self.original, "com.example.missing", self.profile)

    def test_export_options(self) -> None:
        options = plistlib.loads(signing.export_options(BUNDLE_ID, self.profile))
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["teamID"], "UFM3HBFN93")
        self.assertEqual(options["provisioningProfiles"], {BUNDLE_ID: self.profile.uuid})
        self.assertFalse(options["manageAppVersionAndBuildNumber"])

    def test_main_writes_both_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pbxproj = Path(tmp) / "project.pbxproj"
            pbxproj.write_text(self.original, encoding="utf-8")
            profile = Path(tmp) / "profile.plist"
            profile.write_bytes(profile_plist())
            export = Path(tmp) / "ExportOptions.plist"
            with redirect_stdout(io.StringIO()) as printed:
                code = signing.main(["--pbxproj", str(pbxproj), "--profile-plist", str(profile),
                                     "--bundle-id", BUNDLE_ID, "--export-options", str(export)])
            self.assertEqual(code, 0)
            self.assertIn("profile_uuid=12345678-ABCD-ABCD-ABCD-123456789ABC", printed.getvalue())
            self.assertIn("CODE_SIGN_STYLE = Manual", pbxproj.read_text(encoding="utf-8"))
            self.assertTrue(export.exists())

    def test_main_leaves_files_alone_on_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pbxproj = Path(tmp) / "project.pbxproj"
            pbxproj.write_text(self.original, encoding="utf-8")
            profile = Path(tmp) / "profile.plist"
            profile.write_bytes(profile_plist(ProvisionedDevices=["x"]))
            export = Path(tmp) / "ExportOptions.plist"
            with redirect_stderr(io.StringIO()):
                code = signing.main(["--pbxproj", str(pbxproj), "--profile-plist", str(profile),
                                     "--bundle-id", BUNDLE_ID, "--export-options", str(export)])
            self.assertEqual(code, 1)
            self.assertEqual(pbxproj.read_text(encoding="utf-8"), self.original)
            self.assertFalse(export.exists())

    def test_repository_project_is_untouched(self) -> None:
        # 저장소의 프로젝트는 개발자 PC 의 자동 서명 그대로다.
        self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER", self.original)
        self.assertNotIn("CODE_SIGN_STYLE = Manual", self.original)


if __name__ == "__main__":
    unittest.main()
