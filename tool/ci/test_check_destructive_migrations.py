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
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
SCRIPT = HERE / "check_destructive_migrations.py"

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
