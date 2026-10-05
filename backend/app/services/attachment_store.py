"""채팅 첨부(코칭 사진·주간 리포트 PDF)의 바이트 저장소. (#2817)

첨부의 **메타데이터는 DB**(`chat_messages`)에, **바이트는 여기**에 둔다. 예전에는
바이트를 백엔드 컨테이너의 로컬 디스크에만 썼다. 컨테이너 플랫폼(ECS Fargate 등)의
디스크는 재배포·재시작·스케일 아웃 때 비거나 태스크마다 달라서, DB 에는 첨부가
남는데 파일은 사라져 대화방의 사진과 리포트가 깨졌다.

그래서 저장소를 세 동작(`put`/`open`/`delete`)의 인터페이스로 묶고 구현을 둘 둔다.

- `LocalDiskStore` — 개발·테스트용. 지금까지와 **같은 디렉터리·같은 파일 이름**이라
  이미 쌓인 로컬 파일이 그대로 열린다.
- `S3Store` — 운영용. 모든 인스턴스가 같은 버킷을 읽으므로 재배포·다중 인스턴스에도
  첨부가 열린다. 자격 증명은 코드·설정에 두지 않고 실행 환경의 IAM 역할(기본
  자격 증명 체인)을 쓴다.

어느 쪽을 쓸지는 설정이 정한다(`ATTACHMENT_STORAGE`, 기본 `auto` — 버킷 이름이 있으면
S3, 없으면 로컬). 이름(`name`)은 언제나 서버가 만든 `<32자 hex>.<확장자>` 다 — 사용자
문자열이 경로·키에 닿지 않게 하는 것은 호출하는 모듈(`chat_image_storage`·
`report_pdf_storage`)의 몫이고, 여기서도 한 번 더 막는다.
"""
from __future__ import annotations

import logging
import os
import re
from collections.abc import Iterator
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal, Protocol

from app.core.config import Settings, get_settings

logger = logging.getLogger(__name__)

#: 저장소 안에서 쓰는 이름. 호출자가 `<file_id>.<ext>` 만 넘기지만, 인터페이스
#: 경계에서도 한 번 더 막는다 — 구현이 늘어도 `../` 가 키에 닿지 않게.
_NAME = re.compile(r"^[0-9a-f]{32}\.(?:jpg|png|webp|pdf)$")

#: 첨부 종류. 로컬에서는 디렉터리, S3 에서는 키 접두사의 마지막 칸이 된다.
Kind = Literal["chat-images", "report-pdfs"]

#: 내려보낼 때 한 번에 읽는 크기. 사진·PDF 상한(6MB·8MB)을 통째로 메모리에 올리지
#: 않고 흘려보낸다.
CHUNK_SIZE = 64 * 1024


class StoreError(OSError):
    """저장소가 바이트를 쓰거나 지우지 못했다(디스크·네트워크·권한)."""


class _Readable(Protocol):
    def read(self, size: int = -1) -> bytes: ...

    def close(self) -> None: ...


@dataclass
class OpenedBlob:
    """열린 첨부. 응답으로 흘려보내거나(`iter_chunks`) 통째로 읽는다(`read_all`)."""

    stream: _Readable
    size: int | None

    def iter_chunks(self, chunk_size: int = CHUNK_SIZE) -> Iterator[bytes]:
        try:
            while True:
                chunk = self.stream.read(chunk_size)
                if not chunk:
                    return
                yield chunk
        finally:
            self.stream.close()

    def read_all(self) -> bytes:
        return b"".join(self.iter_chunks())


class BlobStore(Protocol):
    """첨부 바이트 저장소의 계약. 구현은 바꿔 끼울 수 있어야 한다."""

    backend: str

    def put(self, name: str, data: bytes, *, content_type: str) -> None:
        """[name] 으로 저장한다. 같은 이름이 있으면 덮어쓴다. 실패하면 `StoreError`."""

    def open(self, name: str) -> OpenedBlob:
        """[name] 을 연다. 없으면 `FileNotFoundError`."""

    def delete(self, name: str) -> None:
        """[name] 을 지운다. 없어도 조용히 끝난다. 실패하면 `StoreError`."""

    def exists(self, name: str) -> bool:
        """[name] 이 있는가."""


def _checked(name: str) -> str:
    if not _NAME.fullmatch(name):
        raise FileNotFoundError(name)
    return name


class LocalDiskStore:
    """로컬 디렉터리 저장소 — 개발·테스트용.

    쓰기는 임시 파일에 쓰고 `fsync` 뒤 이름을 바꾼다. 쓰다 만 파일이 진짜 이름으로
    보이는 순간이 없게 하기 위해서다.
    """

    backend = "local"

    def __init__(self, root: Path) -> None:
        self._root_path = root

    def _root(self) -> Path:
        root = self._root_path.resolve()
        root.mkdir(parents=True, exist_ok=True)
        return root

    def put(self, name: str, data: bytes, *, content_type: str) -> None:
        del content_type  # 로컬은 확장자로 형식을 다시 안다.
        _checked(name)
        root = self._root()
        final_path = root / name
        temporary_path = root / f".{name}.tmp"
        try:
            with temporary_path.open("xb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            temporary_path.replace(final_path)
        except OSError as exc:
            temporary_path.unlink(missing_ok=True)
            raise StoreError(f"로컬 저장 실패: {name}") from exc

    def open(self, name: str) -> OpenedBlob:
        path = self._root() / _checked(name)
        if not path.is_file():
            raise FileNotFoundError(name)
        stream = path.open("rb")
        return OpenedBlob(stream=stream, size=path.stat().st_size)

    def delete(self, name: str) -> None:
        try:
            (self._root() / _checked(name)).unlink(missing_ok=True)
        except FileNotFoundError:
            return
        except OSError as exc:
            raise StoreError(f"로컬 삭제 실패: {name}") from exc

    def exists(self, name: str) -> bool:
        try:
            return (self._root() / _checked(name)).is_file()
        except FileNotFoundError:
            return False

    def names(self) -> list[str]:
        """저장된 이름 목록 — 운영 저장소로 옮기는 스크립트용."""
        root = self._root()
        return sorted(p.name for p in root.iterdir() if p.is_file() and _NAME.fullmatch(p.name))


#: S3 가 "없다" 를 알리는 오류 코드. get 은 `NoSuchKey`, head 는 `404` 를 준다.
_S3_MISSING = frozenset({"NoSuchKey", "404", "NotFound"})


def _s3_error_code(exc: Exception) -> str:
    response: Any = getattr(exc, "response", None) or {}
    return str(response.get("Error", {}).get("Code", ""))


class S3Store:
    """S3(또는 S3 호환) 버킷 저장소 — 운영용.

    키는 `<접두사><종류>/<이름>` 이다. 접두사를 두는 이유는 같은 버킷을 다른 용도와
    나눠 쓸 때 수명 주기 규칙·권한을 접두사 단위로 걸 수 있게 하기 위해서다.
    """

    backend = "s3"

    def __init__(self, client: Any, bucket: str, prefix: str) -> None:
        self._client = client
        self._bucket = bucket
        self._prefix = prefix

    def key(self, name: str) -> str:
        return f"{self._prefix}{_checked(name)}"

    def put(self, name: str, data: bytes, *, content_type: str) -> None:
        try:
            self._client.put_object(
                Bucket=self._bucket,
                Key=self.key(name),
                Body=data,
                ContentType=content_type,
            )
        except FileNotFoundError:
            raise
        except Exception as exc:  # noqa: BLE001 — botocore 예외를 한 종류로 접는다.
            raise StoreError(f"S3 저장 실패: {name}") from exc

    def open(self, name: str) -> OpenedBlob:
        key = self.key(name)
        try:
            response = self._client.get_object(Bucket=self._bucket, Key=key)
        except Exception as exc:  # noqa: BLE001
            if _s3_error_code(exc) in _S3_MISSING:
                raise FileNotFoundError(name) from exc
            raise StoreError(f"S3 읽기 실패: {name}") from exc
        return OpenedBlob(stream=response["Body"], size=response.get("ContentLength"))

    def delete(self, name: str) -> None:
        try:
            key = self.key(name)
        except FileNotFoundError:
            return
        try:
            # S3 의 삭제는 없는 키에도 성공한다 — 로컬의 `missing_ok` 와 같다.
            self._client.delete_object(Bucket=self._bucket, Key=key)
        except Exception as exc:  # noqa: BLE001
            raise StoreError(f"S3 삭제 실패: {name}") from exc

    def exists(self, name: str) -> bool:
        try:
            self._client.head_object(Bucket=self._bucket, Key=self.key(name))
        except FileNotFoundError:
            return False
        except Exception as exc:  # noqa: BLE001
            if _s3_error_code(exc) in _S3_MISSING:
                return False
            raise StoreError(f"S3 확인 실패: {name}") from exc
        return True


def resolve_backend(settings: Settings) -> Literal["local", "s3"]:
    """설정으로 저장소 구현을 고른다.

    `auto` 는 버킷 이름이 있으면 S3, 없으면 로컬이다. `s3` 를 강제했는데 버킷이
    비어 있으면 조용히 로컬로 떨어지지 않고 실패한다 — 운영에서 첨부가 다시
    컨테이너 디스크로 가는 일을 기동 단계에서 막는다(`app.core.startup_checks`).
    """
    choice = settings.attachment_storage
    bucket = settings.attachment_s3_bucket.strip()
    if choice == "local":
        return "local"
    if choice == "s3":
        if not bucket:
            raise RuntimeError(
                "ATTACHMENT_STORAGE=s3 인데 ATTACHMENT_S3_BUCKET 이 비어 있습니다."
            )
        return "s3"
    return "s3" if bucket else "local"


@lru_cache(maxsize=4)
def _s3_client(region: str, endpoint_url: str) -> Any:
    """boto3 S3 클라이언트. 같은 설정이면 재사용한다(스레드 안전).

    boto3 는 운영 저장소를 쓸 때만 필요하다 — 로컬 개발에서 import 비용을 내지
    않게 여기서 늦게 부른다.
    """
    import boto3
    from botocore.config import Config

    return boto3.client(
        "s3",
        region_name=region or None,
        endpoint_url=endpoint_url or None,
        # 무응답 S3 가 요청 스레드를 붙잡지 않게 연결·읽기 한도를 건다.
        config=Config(connect_timeout=5, read_timeout=30, retries={"max_attempts": 3}),
    )


def _s3_prefix(settings: Settings, kind: Kind) -> str:
    base = settings.attachment_s3_prefix.strip().strip("/")
    return f"{base}/{kind}/" if base else f"{kind}/"


def get_store(kind: Kind, settings: Settings | None = None) -> BlobStore:
    """[kind] 첨부의 저장소. 매번 설정을 다시 읽는다(테스트가 디렉터리를 바꿔 낀다)."""
    settings = settings or get_settings()
    if resolve_backend(settings) == "s3":
        client = _s3_client(
            settings.attachment_s3_region.strip(),
            settings.attachment_s3_endpoint_url.strip(),
        )
        return S3Store(client, settings.attachment_s3_bucket.strip(), _s3_prefix(settings, kind))
    return local_store(kind, settings)


def local_store(kind: Kind, settings: Settings | None = None) -> LocalDiskStore:
    """[kind] 첨부의 로컬 디렉터리 저장소 — 설정의 백엔드와 무관하게 로컬을 연다."""
    settings = settings or get_settings()
    root = (
        settings.chat_image_storage_dir
        if kind == "chat-images"
        else settings.report_pdf_storage_dir
    )
    return LocalDiskStore(Path(root))
