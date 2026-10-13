"""check_destructive_migrations.py 테스트(#1552).

pr-gate 는 모든 PR 의 필수 검사라, 이 스크립트가 오탐하면 마이그레이션이 든 PR 이 전부
막히고, 놓치면 검사가 있으나 마나다. 걸려야 하는 형태·통과해야 하는 형태·승인 주석을
함께 고정해 둔다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
SCRIPT = HERE / "check_destructive_migrations.py"
FIXTURES = HERE / "fixtures" / "migrations"

sys.path.insert(0, str(HERE))
import check_destructive_migrations as dm  # noqa: E402

HEADER = '''"""설명 — 여기 적은 DROP TABLE 이나 DELETE FROM 은 docstring 이라 보지 않는다."""
from alembic import op
import sqlalchemy as sa

revision = "9999_x"
down_revision = "9998_x"
'''


def reasons(body: str) -> list[str]:
    source = HEADER + textwrap.dedent(body)
    return [f.reason for f in dm.scan_source("m.py", source)]


class ScanTest(unittest.TestCase):
    def test_safe_migration_passes(self) -> None:
        self.assertEqual(
            reasons(
                """
                def upgrade():
                    op.create_table("t", sa.Column("id", sa.Integer(), primary_key=True))
                    op.add_column("u", sa.Column("a", sa.Integer(), nullable=True))
                    op.add_column(
                        "u", sa.Column("b", sa.Boolean(), nullable=False, server_default=sa.false())
                    )
                    op.create_index("ix_u_a", "u", ["a"])
                    op.execute("CREATE INDEX IF NOT EXISTS ix_u_b ON u (b)")
                    op.execute("INSERT INTO t (id) VALUES (1)")

                def downgrade():
                    op.drop_index("ix_u_a", table_name="u")
                    op.drop_column("u", "a")
                    op.drop_table("t")
                    op.execute("DELETE FROM t")
                """
            ),
            [],
        )

    def test_alembic_ops_are_caught(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.drop_table("a")
                op.drop_column("b", "c")
                op.alter_column("b", "d", type_=sa.String(10))
                op.drop_constraint("ck", "b")
                op.drop_index("ix", table_name="b")
                op.rename_table("b", "bb")
                with op.batch_alter_table("e") as batch_op:
                    batch_op.drop_column("f")
            """
        )
        self.assertEqual(
            found,
            [
                "`drop_table`",
                "`drop_column`",
                "`alter_column`",
                "`drop_constraint`",
                "`drop_index`",
                "`rename_table`",
                "`drop_column`",
            ],
        )

    def test_not_null_without_default(self) -> None:
        self.assertEqual(
            len(
                reasons(
                    """
                    def upgrade():
                        op.add_column("u", sa.Column("a", sa.Integer(), nullable=False))
                    """
                )
            ),
            1,
        )

    def test_sql_in_execute_and_text(self) -> None:
        found = reasons(
            """
            TABLES = ["a", "b"]

            def purge():
                op.execute("DELETE FROM ai_messages WHERE x IS NOT NULL")

            def upgrade():
                purge()
                op.execute(
                    \"\"\"
                    update trainer_routines
                    set ended_on = now()
                    \"\"\"
                )
                conn = op.get_bind()
                for t in TABLES:
                    conn.execute(sa.text(f'UPDATE "{t}" SET "c" = :new WHERE "c" = :old'))
                op.execute("TRUNCATE notifications")
                op.execute("ALTER TABLE u DROP COLUMN legacy")
                op.execute("ALTER TABLE u ALTER COLUMN a TYPE smallint")
                op.execute("ALTER TABLE u RENAME TO users2")
            """
        )
        self.assertEqual(
            found,
            [
                "SQL `DELETE`",
                "SQL `UPDATE`",
                "SQL `UPDATE`",
                "SQL `TRUNCATE`",
                "SQL `DROP`",
                "SQL `ALTER COLUMN`",
                "SQL `RENAME`",
            ],
        )

    def test_plain_words_are_not_sql(self) -> None:
        self.assertEqual(
            reasons(
                """
                LABEL = "update set of items; drop shadow; delete button"

                def upgrade():
                    op.create_check_constraint("ck", "t", "kind IN ('update', 'delete')")
                """
            ),
            [],
        )

    def test_past_destructive_migration_is_caught(self) -> None:
        path = REPO_ROOT / "backend/migrations/versions/0016_drop_vitals.py"
        found = dm.scan_source(str(path), path.read_text(encoding="utf-8"))
        self.assertIn("`drop_table`", [f.reason for f in found])

    def test_update_with_alias_fixture_is_caught(self) -> None:
        # 0104_backfill_schedule_member_id 의 형태. 이전 패턴은 `OK` 로 통과시켰다(#3236).
        path = FIXTURES / "update_with_alias.py"
        found = dm.scan_source(str(path), path.read_text(encoding="utf-8"))
        self.assertEqual([f.reason for f in found], ["SQL `UPDATE`"])
        real = REPO_ROOT / "backend/migrations/versions/0104_backfill_schedule_member_id.py"
        if real.exists():
            found = dm.scan_source(str(real), real.read_text(encoding="utf-8"))
            self.assertEqual([f.reason for f in found], ["SQL `UPDATE`"])

    def test_update_variants(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.execute("UPDATE t AS s SET a = 1")
                op.execute("UPDATE t s SET a = 1")
                op.execute("UPDATE ONLY t SET a = 1")
                op.execute('update "t" as "s" set a = 1')
            """
        )
        self.assertEqual(found, ["SQL `UPDATE`"] * 4)

    def test_upsert_is_not_a_data_update(self) -> None:
        # INSERT … ON CONFLICT DO UPDATE SET 은 INSERT 다(정책상 파괴적이지 않음).
        self.assertEqual(
            reasons(
                """
                def upgrade():
                    op.execute(
                        "INSERT INTO t (id, a) VALUES (1, 2) "
                        "ON CONFLICT (id) DO UPDATE SET a = EXCLUDED.a"
                    )
                """
            ),
            [],
        )

    def test_alter_without_column_keyword(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.execute("ALTER TABLE t ALTER c TYPE bigint")
                op.execute("ALTER TABLE t ALTER c SET NOT NULL")
                op.execute("ALTER TABLE IF EXISTS t ALTER \\"c\\" SET DATA TYPE text")
                op.execute("ALTER TABLE t ADD COLUMN x int, ALTER y DROP DEFAULT")
            """
        )
        self.assertEqual(found, ["SQL `ALTER COLUMN`"] * 4)

    def test_alter_constraint_and_type_are_not_column_changes(self) -> None:
        self.assertEqual(
            reasons(
                """
                def upgrade():
                    op.execute("ALTER TABLE t ALTER CONSTRAINT fk DEFERRABLE")
                    op.execute("ALTER TYPE mood ADD VALUE 'meh'")
                    op.execute("ALTER TABLE t ADD COLUMN x int")
                """
            ),
            [],
        )

    def test_sql_add_column_not_null(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.execute("ALTER TABLE t ADD COLUMN a int NOT NULL")
                op.execute("ALTER TABLE t ADD b numeric(10, 2) NOT NULL")
                op.execute("ALTER TABLE t ADD COLUMN IF NOT EXISTS c int DEFAULT NULL NOT NULL")
                op.execute("ALTER TABLE t ADD COLUMN d int, ADD COLUMN e text NOT NULL")
            """
        )
        self.assertEqual(found, ["기본값 없는 NOT NULL 칸 추가(SQL `ADD COLUMN … NOT NULL`)"] * 4)

    def test_sql_add_column_not_null_with_fill_passes(self) -> None:
        self.assertEqual(
            reasons(
                """
                def upgrade():
                    op.execute("ALTER TABLE t ADD COLUMN a int NOT NULL DEFAULT 0")
                    op.execute("ALTER TABLE t ADD COLUMN b numeric(10, 2) DEFAULT 0 NOT NULL")
                    op.execute("ALTER TABLE t ADD COLUMN c bigserial NOT NULL")
                    op.execute("ALTER TABLE t ADD COLUMN d int GENERATED ALWAYS AS (a + 1) STORED NOT NULL")
                    op.execute("ALTER TABLE t ADD CONSTRAINT ck CHECK (a IS NOT NULL)")
                """
            ),
            [],
        )

    def test_core_update_and_delete(self) -> None:
        found = reasons(
            """
            from sqlalchemy import delete as sa_delete

            def upgrade():
                t = sa.table("t", sa.column("a"))
                conn = op.get_bind()
                conn.execute(t.update().where(t.c.a == 1).values(a=2))
                conn.execute(t.delete().where(t.c.a == 1))
                conn.execute(sa.update(t).values(a=2))
                conn.execute(sa.delete(t))
                conn.execute(sa_delete(t))
                session = None
                session.query(t).filter(t.c.a == 1).update({"a": 2})
            """
        )
        self.assertEqual(
            found,
            [
                "SQLAlchemy `update()`",
                "SQLAlchemy `delete()`",
                "SQLAlchemy `update()`",
                "SQLAlchemy `delete()`",
                "SQLAlchemy `sa_delete()`",
                "SQLAlchemy `update()`",
            ],
        )

    def test_dict_update_is_not_core_update(self) -> None:
        self.assertEqual(
            reasons(
                """
                def upgrade():
                    values = {"a": 1}
                    values.update({"b": 2})
                    values.update(c=3)
                    op.bulk_insert(sa.table("t", sa.column("a")), [values])
                """
            ),
            [],
        )

    def test_server_default_none_is_no_default(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.add_column("u", sa.Column("a", sa.Integer(), nullable=False, server_default=None))
                op.add_column("u", sa.Column("b", sa.Integer(), nullable=False, server_default="0"))
            """
        )
        self.assertEqual(found, ["기본값 없는 NOT NULL 칸 추가(`add_column` · `nullable=False`)"])

    def test_concatenated_sql(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.execute("DROP " + "TABLE users")
                table = "users"
                op.execute("UPDATE " + table + " SET a = 1")
                op.execute(" ".join(["DELETE", "FROM", table]))
                op.execute("TRUNC" "ATE notifications")
                op.execute(("ALTER TABLE " + table) + " ALTER c TYPE text")
            """
        )
        self.assertEqual(
            found,
            ["SQL `DROP`", "SQL `UPDATE`", "SQL `DELETE`", "SQL `TRUNCATE`", "SQL `ALTER COLUMN`"],
        )

    def test_concatenated_sql_is_counted_once(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.execute("DELETE FROM a WHERE x = " + str(1) + " AND y = 'DELETE FROM b'")
            """
        )
        self.assertEqual(found, ["SQL `DELETE`"])

    def test_call_inside_concatenation_is_still_seen(self) -> None:
        found = reasons(
            """
            def upgrade():
                op.execute("SELECT " + helper("DROP TABLE x"))
            """
        )
        self.assertEqual(found, ["SQL `DROP`"])


class ApprovalTest(unittest.TestCase):
    def _run(self, source: str, *flags: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "m.py"
            path.write_text(source, encoding="utf-8")
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                code = dm.main([*flags, str(path)])
            return code, buffer.getvalue()

    def test_unapproved_fails_with_annotation(self) -> None:
        code, out = self._run(HEADER + "def upgrade():\n    op.drop_table('a')\n")
        self.assertEqual(code, 1)
        self.assertIn("::error file=", out)
        self.assertIn(",line=8::", out)

    def test_marker_with_reason_passes(self) -> None:
        code, out = self._run(
            HEADER
            + "# destructive-migration: 옛 칸을 읽지 않는 코드가 먼저 배포됨\n"
            + "def upgrade():\n    op.drop_table('a')\n"
        )
        self.assertEqual(code, 0)
        self.assertIn("옛 칸을 읽지 않는 코드가 먼저 배포됨", out)

    def test_marker_without_reason_does_not_pass(self) -> None:
        code, _ = self._run(
            HEADER + "# destructive-migration:\ndef upgrade():\n    op.drop_table('a')\n"
        )
        self.assertEqual(code, 1)

    def test_label_approval_passes_with_warnings(self) -> None:
        code, out = self._run(
            HEADER + "def upgrade():\n    op.drop_table('a')\n", "--label-approved"
        )
        self.assertEqual(code, 0)
        self.assertIn("::warning file=", out)
        self.assertNotIn("::error", out)

    def test_label_flag_keeps_safe_files_quiet(self) -> None:
        code, out = self._run(
            HEADER + "def upgrade():\n    op.create_index('ix', 't', ['a'])\n", "--label-approved"
        )
        self.assertEqual(code, 0)
        self.assertNotIn("::warning", out)

    def test_marker_inside_docstring_does_not_pass(self) -> None:
        # 정책 문구를 docstring 에 붙여 넣어도 승인이 아니다(#3236).
        code, _ = self._run(
            '"""설명\n# destructive-migration: 문서에 적은 예시\n"""\n'
            "from alembic import op\n"
            "def upgrade():\n    op.drop_table('a')\n"
        )
        self.assertEqual(code, 1)

    def test_marker_inside_string_does_not_pass(self) -> None:
        code, _ = self._run(
            HEADER
            + 'NOTE = """\n# destructive-migration: 문자열 안\n"""\n'
            + "def upgrade():\n    op.drop_table('a')\n"
        )
        self.assertEqual(code, 1)

    def test_indented_and_trailing_marker_pass(self) -> None:
        for marker in (
            "    # destructive-migration: 들여 쓴 주석\n    op.drop_table('a')\n",
            "    op.drop_table('a')  # destructive-migration: 줄 끝 주석\n",
        ):
            with self.subTest(marker=marker):
                code, _ = self._run(HEADER + "def upgrade():\n" + marker)
                self.assertEqual(code, 0)

    def test_stale_label_does_not_approve(self) -> None:
        # 라벨을 붙인 뒤 커밋이 더해져 다시 돈 실행은 승인으로 치지 않는다(#3236).
        code, out = self._run(HEADER + "def upgrade():\n    op.drop_table('a')\n", "--stale-label")
        self.assertEqual(code, 1)
        self.assertIn("::error file=", out)
        self.assertIn("라벨을 뗐다가 다시 붙이거나", out)

    def test_stale_label_keeps_safe_or_commented_files_passing(self) -> None:
        for source in (
            HEADER + "def upgrade():\n    op.create_index('ix', 't', ['a'])\n",
            HEADER + "# destructive-migration: 주석 승인\ndef upgrade():\n    op.drop_table('a')\n",
        ):
            with self.subTest(source=source):
                code, out = self._run(source, "--stale-label")
                self.assertEqual(code, 0)
                self.assertNotIn("::error", out)

    def test_label_flags_are_exclusive(self) -> None:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            dm.main(["--label-approved", "--stale-label", "x.py"])


class WorkflowWiringTest(unittest.TestCase):
    """PR Gate 가 라벨을 붙인 실행에서만 승인으로 넘기는지 본다(#3236)."""

    def test_label_approval_is_tied_to_the_labeling_event(self) -> None:
        text = (REPO_ROOT / ".github/workflows/pr-gate.yml").read_text(encoding="utf-8")
        self.assertIn(
            "LABEL_ADDED_NOW: ${{ github.event.action == 'labeled' && "
            "github.event.label.name == 'destructive-migration' }}",
            text,
        )
        self.assertRegex(
            text,
            r'if \[ "\$LABEL_ADDED_NOW" = true \]; then\n\s+flags\+=\(--label-approved\)\n'
            r'\s+elif \[ "\$LABEL_PRESENT" = true \]; then\n\s+flags\+=\(--stale-label\)',
        )


class ConsoleEncodingTest(unittest.TestCase):
    """cp949 처럼 `—` 를 못 찍는 출력에서도 판정까지 간다(#3236)."""

    def test_cp949_output_does_not_crash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for name, source, expected in (
                ("block.py", HEADER + "def upgrade():\n    op.drop_table('a')\n", 1),
                (
                    "ok.py",
                    HEADER + "# destructive-migration: 승인 사유\ndef upgrade():\n    op.drop_table('a')\n",
                    0,
                ),
            ):
                path = Path(tmp) / name
                path.write_text(source, encoding="utf-8")
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), str(path)],
                    check=False,
                    capture_output=True,
                    env={**os.environ, "PYTHONIOENCODING": "cp949", "PYTHONUTF8": "0"},
                )
                with self.subTest(name=name):
                    self.assertEqual(result.returncode, expected, result.stderr.decode("cp949", "replace"))
                    self.assertNotIn(b"UnicodeEncodeError", result.stderr)


class BaseDiffTest(unittest.TestCase):
    """--base 는 base 이후 추가·변경된 마이그레이션만 본다 — 기존 파일은 걸지 않는다."""

    def git(self, cwd: Path, *args: str) -> None:
        subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)

    def test_only_new_or_changed_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            versions = repo / "backend/migrations/versions"
            versions.mkdir(parents=True)
            self.git(repo, "init", "-q")
            self.git(repo, "config", "user.email", "ci@example.com")
            self.git(repo, "config", "user.name", "ci")
            old = HEADER + "def upgrade():\n    op.drop_table('old')\n"
            (versions / "0001_old.py").write_text(old, encoding="utf-8")
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-q", "-m", "base")
            base = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True, text=True
            ).stdout.strip()

            (versions / "0002_safe.py").write_text(
                HEADER + "def upgrade():\n    op.create_index('ix', 't', ['a'])\n",
                encoding="utf-8",
            )
            (repo / "README.md").write_text("DROP TABLE x\n", encoding="utf-8")
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-q", "-m", "safe")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--base", base],
                cwd=repo,
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                env={**os.environ, "PYTHONIOENCODING": "utf-8"},
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("0001_old.py", result.stdout)

            (versions / "0003_drop.py").write_text(
                HEADER + "def upgrade():\n    op.drop_column('t', 'a')\n", encoding="utf-8"
            )
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-q", "-m", "drop")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--base", base],
                cwd=repo,
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                env={**os.environ, "PYTHONIOENCODING": "utf-8"},
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("0003_drop.py", result.stdout)
            self.assertNotIn("0001_old.py", result.stdout)


if __name__ == "__main__":
    unittest.main()
