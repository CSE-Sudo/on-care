"""채팅 첨부 저장소 — 구현 교체·다른 인스턴스에서 읽기·이전 스크립트. (#2817)

DB 가 필요 없다. S3 는 `tests.fake_s3.FakeS3` 대역으로 흉내 낸다.

여기서 지키는 것:

1. 저장소 구현을 바꿔 끼울 수 있다 — 같은 호출이 로컬·S3 어느 쪽에서도 같은 결과.
2. **다른 인스턴스**(새 저장소 객체·새 클라이언트)가 같은 버킷의 파일을 읽는다 —
   재배포·스케일 아웃 뒤에도 첨부가 열린다.
3. 설정이 저장소를 고른다. 버킷 없이 S3 를 강제하면 조용히 로컬로 떨어지지 않는다.
4. 이름은 서버가 만든 형식만 받는다 — `../` 가 경로·키에 닿지 않는다.
5. 이전 스크립트는 DB 가 가리키는 파일만 옮기고, 여러 번 돌려도 같다.
"""
from __future__ import annotations

import pytest

from app.core.config import Settings, get_settings
from app.services import (
    attachment_cleanup,
    attachment_store,
    chat_image_storage,
    report_pdf_storage,
)
from scripts import migrate_attachments
from tests.fake_s3 import FakeS3

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 24
# 저장소 동작만 보는 가짜 바이트라 디코딩·재인코딩(#2829)은 끄고 저장한다.
PDF = b"%PDF-1.4\n" + b"0" * 64 + b"\n%%EOF"
NAME = "0123456789abcdef0123456789abcdef.png"


def _settings(**kw) -> Settings:
    return Settings(_env_file=None, **kw)


# ---- 1. 설정이 저장소를 고른다 ----


@pytest.mark.parametrize(
    ("choice", "bucket", "expected"),
    [
        ("auto", "", "local"),
        ("auto", "oncare-attachments", "s3"),
        ("local", "oncare-attachments", "local"),
        ("s3", "oncare-attachments", "s3"),
    ],
)
def test_backend_is_chosen_by_settings(choice, bucket, expected):
    settings = _settings(attachment_storage=choice, attachment_s3_bucket=bucket)
    assert attachment_store.resolve_backend(settings) == expected


def test_forcing_s3_without_a_bucket_fails_instead_of_falling_back():
    settings = _settings(attachment_storage="s3", attachment_s3_bucket="  ")
    with pytest.raises(RuntimeError):
        attachment_store.resolve_backend(settings)


def test_local_is_the_default_for_development():
    settings = _settings()
    assert attachment_store.resolve_backend(settings) == "local"
    store = attachment_store.get_store("chat-images", settings)
    assert isinstance(store, attachment_store.LocalDiskStore)


def test_s3_keys_use_the_prefix_and_kind(monkeypatch):
    fake = FakeS3()
    monkeypatch.setattr(attachment_store, "_s3_client", lambda region, endpoint: fake)
    settings = _settings(
        attachment_s3_bucket="bucket", attachment_s3_prefix="/prod-attachments/"
    )
    store = attachment_store.get_store("report-pdfs", settings)
    assert isinstance(store, attachment_store.S3Store)
    store.put("0123456789abcdef0123456789abcdef.pdf", PDF, content_type="application/pdf")
    assert list(fake.objects) == [
        ("bucket", "prod-attachments/report-pdfs/0123456789abcdef0123456789abcdef.pdf")
    ]


def test_empty_prefix_still_separates_kinds(monkeypatch):
    fake = FakeS3()
    monkeypatch.setattr(attachment_store, "_s3_client", lambda region, endpoint: fake)
    settings = _settings(attachment_s3_bucket="bucket", attachment_s3_prefix="")
    attachment_store.get_store("chat-images", settings).put(NAME, PNG, content_type="image/png")
    assert list(fake.objects) == [("bucket", f"chat-images/{NAME}")]


# ---- 2. 두 구현이 같은 계약을 지킨다 ----


def _local(tmp_path):
    return attachment_store.LocalDiskStore(tmp_path)


def _s3(_tmp_path):
    return attachment_store.S3Store(FakeS3(), "bucket", "p/chat-images/")


@pytest.fixture(params=[_local, _s3], ids=["local", "s3"])
def store(request, tmp_path):
    return request.param(tmp_path)


def test_put_open_delete_round_trip(store):
    store.put(NAME, PNG, content_type="image/png")
    assert store.exists(NAME)
    blob = store.open(NAME)
    assert blob.size == len(PNG)
    assert blob.read_all() == PNG

    store.delete(NAME)
    assert not store.exists(NAME)
    with pytest.raises(FileNotFoundError):
        store.open(NAME)


def test_put_overwrites_the_same_name(store):
    store.put(NAME, PNG, content_type="image/png")
    store.put(NAME, PNG + b"x", content_type="image/png")
    assert store.open(NAME).read_all() == PNG + b"x"


def test_deleting_a_missing_name_is_quiet(store):
    store.delete(NAME)
    assert not store.exists(NAME)


@pytest.mark.parametrize(
    "bad",
    ["../etc/passwd", "0123456789abcdef0123456789abcdef.exe", "abc.png", "", "a/b.png"],
)
def test_names_outside_the_server_format_are_refused(store, bad):
    with pytest.raises(FileNotFoundError):
        store.open(bad)
    assert not store.exists(bad)
    store.delete(bad)  # 조용히 끝난다 — 아무것도 건드리지 않는다.
    with pytest.raises(OSError):
        store.put(bad, PNG, content_type="image/png")


def test_chunks_are_streamed_and_the_stream_is_closed(store):
    data = bytes(range(256)) * 600  # 청크 여러 개
    store.put("0123456789abcdef0123456789abcdef.pdf", data, content_type="application/pdf")
    blob = store.open("0123456789abcdef0123456789abcdef.pdf")
    chunks = list(blob.iter_chunks(chunk_size=4096))
    assert len(chunks) > 1
    assert b"".join(chunks) == data


def test_local_store_keeps_the_existing_layout(tmp_path):
    """예전 로컬 파일(`<dir>/<id>.<ext>`)이 그대로 열린다 — 이전 없이 개발 계속."""
    (tmp_path / NAME).write_bytes(PNG)
    store = attachment_store.LocalDiskStore(tmp_path)
    assert store.open(NAME).read_all() == PNG
    assert store.names() == [NAME]


def test_local_names_skip_temporary_and_foreign_files(tmp_path):
    (tmp_path / NAME).write_bytes(PNG)
    (tmp_path / f".{NAME}.tmp").write_bytes(b"half")
    (tmp_path / "notes.txt").write_text("x")
    assert attachment_store.LocalDiskStore(tmp_path).names() == [NAME]


# ---- 3. 다른 인스턴스에서 읽기 ----


def test_another_instance_reads_what_one_instance_wrote():
    """재배포·두 번째 인스턴스: 새 클라이언트·새 저장소 객체가 같은 버킷을 읽는다."""
    bucket: dict = {}
    writer = attachment_store.S3Store(FakeS3(bucket), "bucket", "p/chat-images/")
    writer.put(NAME, PNG, content_type="image/png")

    reader = attachment_store.S3Store(FakeS3(bucket), "bucket", "p/chat-images/")
    assert reader.open(NAME).read_all() == PNG


def test_s3_missing_object_is_not_found_and_outage_is_a_store_error():
    fake = FakeS3()
    store = attachment_store.S3Store(fake, "bucket", "p/")
    with pytest.raises(FileNotFoundError):
        store.open(NAME)

    fake.fail_with = "InternalError"
    with pytest.raises(attachment_store.StoreError):
        store.open(NAME)
    with pytest.raises(attachment_store.StoreError):
        store.put(NAME, PNG, content_type="image/png")
    with pytest.raises(attachment_store.StoreError):
        store.delete(NAME)
    with pytest.raises(attachment_store.StoreError):
        store.exists(NAME)


# ---- 4. 사진·PDF 모듈이 운영 저장소에서 동작한다 ----


@pytest.fixture
def s3_settings(monkeypatch):
    bucket: dict = {}
    monkeypatch.setattr(
        attachment_store, "_s3_client", lambda region, endpoint: FakeS3(bucket)
    )
    settings = get_settings()
    monkeypatch.setattr(settings, "attachment_storage", "auto")
    monkeypatch.setattr(settings, "attachment_s3_bucket", "oncare-test")
    monkeypatch.setattr(settings, "attachment_s3_prefix", "chat-attachments")
    return bucket


def test_chat_image_round_trip_on_s3(s3_settings):
    file_id, extension, media_type, _ = chat_image_storage.save(
        JPEG, sanitize=False
    )
    assert (extension, media_type) == ("jpg", "image/jpeg")
    key = ("oncare-test", f"chat-attachments/chat-images/{file_id}.jpg")
    assert s3_settings[key] == (JPEG, "image/jpeg")

    blob, opened_type = chat_image_storage.open_image(file_id)
    assert opened_type == "image/jpeg"
    assert blob.read_all() == JPEG

    chat_image_storage.delete(file_id)
    assert key not in s3_settings
    with pytest.raises(FileNotFoundError):
        chat_image_storage.open_image(file_id)


def test_chat_image_finds_the_extension_it_was_saved_with(s3_settings):
    file_id = chat_image_storage.save(PNG, sanitize=False).file_id
    _, media_type = chat_image_storage.open_image(file_id)
    assert media_type == "image/png"


def test_report_pdf_round_trip_on_s3(s3_settings):
    file_id = report_pdf_storage.save(PDF)
    assert s3_settings[("oncare-test", f"chat-attachments/report-pdfs/{file_id}.pdf")] == (
        PDF,
        "application/pdf",
    )
    assert report_pdf_storage.open_pdf(file_id).read_all() == PDF
    report_pdf_storage.delete(file_id)
    with pytest.raises(FileNotFoundError):
        report_pdf_storage.open_pdf(file_id)


def test_seed_file_ids_overwrite_on_s3(s3_settings):
    """데모 시드는 기동마다 같은 file_id 로 다시 쓴다(#2788) — S3 에서도 같다."""
    fixed = "f" * 32
    assert report_pdf_storage.save(PDF, file_id=fixed) == fixed
    assert report_pdf_storage.save(PDF, file_id=fixed) == fixed
    assert report_pdf_storage.open_pdf(fixed).read_all() == PDF


def test_storage_outage_is_reported_as_the_module_error(s3_settings, monkeypatch):
    broken = FakeS3()
    broken.fail_with = "SlowDown"
    monkeypatch.setattr(attachment_store, "_s3_client", lambda region, endpoint: broken)
    with pytest.raises(chat_image_storage.ImageStorageError):
        chat_image_storage.save(PNG, sanitize=False)
    with pytest.raises(report_pdf_storage.PdfStorageError):
        report_pdf_storage.save(PDF)


def test_opaque_ids_are_required(s3_settings):
    with pytest.raises(FileNotFoundError):
        chat_image_storage.open_image("../../secret")
    with pytest.raises(FileNotFoundError):
        report_pdf_storage.open_pdf("../../secret")
    with pytest.raises(chat_image_storage.ImageStorageError):
        chat_image_storage.save(PNG, file_id="../x", sanitize=False)


# ---- 5. 탈퇴 정리 ----


def test_purge_deletes_each_kind_from_its_store(s3_settings):
    image_id = chat_image_storage.save(PNG, sanitize=False).file_id
    pdf_id = report_pdf_storage.save(PDF)

    done = attachment_cleanup.purge(
        [
            attachment_cleanup.AttachmentFile(kind="image", file_id=image_id),
            attachment_cleanup.AttachmentFile(kind="pdf", file_id=pdf_id),
        ]
    )

    assert done == 2
    assert s3_settings == {}


def test_purge_keeps_going_when_one_file_fails(monkeypatch, caplog):
    deleted: list[str] = []

    def flaky(file_id: str) -> None:
        if file_id == "a" * 32:
            raise attachment_store.StoreError("down")
        deleted.append(file_id)

    monkeypatch.setattr(chat_image_storage, "delete", flaky)
    monkeypatch.setattr(report_pdf_storage, "delete", lambda file_id: deleted.append(file_id))

    done = attachment_cleanup.purge(
        [
            attachment_cleanup.AttachmentFile(kind="image", file_id="a" * 32),
            attachment_cleanup.AttachmentFile(kind="image", file_id="b" * 32),
            attachment_cleanup.AttachmentFile(kind="pdf", file_id="c" * 32),
        ]
    )

    assert done == 2
    assert deleted == ["b" * 32, "c" * 32]
    # 실패한 파일은 다시 지울 수 있게 식별자와 함께 남는다.
    assert "a" * 32 in caplog.text


# ---- 6. 이전 스크립트 ----


def _migration_fixture(tmp_path):
    images = attachment_store.LocalDiskStore(tmp_path / "images")
    pdfs = attachment_store.LocalDiskStore(tmp_path / "pdfs")
    kept, orphan, pdf = "1" * 32, "2" * 32, "3" * 32
    images.put(f"{kept}.png", PNG, content_type="image/png")
    images.put(f"{orphan}.jpg", JPEG, content_type="image/jpeg")
    pdfs.put(f"{pdf}.pdf", PDF, content_type="application/pdf")
    bucket: dict = {}
    targets = {
        "chat-images": attachment_store.S3Store(FakeS3(bucket), "b", "x/chat-images/"),
        "report-pdfs": attachment_store.S3Store(FakeS3(bucket), "b", "x/report-pdfs/"),
    }
    sources = {"chat-images": images, "report-pdfs": pdfs}
    lost = "4" * 32
    referenced = {
        ("chat-images", kept),
        ("report-pdfs", pdf),
        ("chat-images", lost),
    }
    return sources, targets, referenced, bucket, (kept, orphan, pdf, lost)


def test_migration_copies_only_referenced_files(tmp_path):
    sources, targets, referenced, bucket, (kept, orphan, pdf, lost) = _migration_fixture(
        tmp_path
    )

    report = migrate_attachments.migrate(sources, targets, referenced, dry_run=False)

    assert sorted(report.copied) == [f"chat-images/{kept}.png", f"report-pdfs/{pdf}.pdf"]
    assert report.skipped_orphan == [f"chat-images/{orphan}.jpg"]
    assert report.missing == [f"chat-images/{lost}"]
    assert bucket[("b", f"x/chat-images/{kept}.png")] == (PNG, "image/png")
    assert bucket[("b", f"x/report-pdfs/{pdf}.pdf")] == (PDF, "application/pdf")
    assert ("b", f"x/chat-images/{orphan}.jpg") not in bucket
    # 원본은 남는다 — 확인 뒤 사람이 지운다.
    assert sources["chat-images"].exists(f"{kept}.png")


def test_migration_is_repeatable(tmp_path):
    sources, targets, referenced, _, _ = _migration_fixture(tmp_path)
    migrate_attachments.migrate(sources, targets, referenced, dry_run=False)

    again = migrate_attachments.migrate(sources, targets, referenced, dry_run=False)

    assert again.copied == []
    assert len(again.skipped_existing) == 2


def test_migration_dry_run_writes_nothing(tmp_path):
    sources, targets, referenced, bucket, _ = _migration_fixture(tmp_path)

    report = migrate_attachments.migrate(sources, targets, referenced, dry_run=True)

    assert len(report.copied) == 2
    assert bucket == {}
