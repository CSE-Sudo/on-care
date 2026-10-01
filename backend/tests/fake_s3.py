"""테스트용 S3 클라이언트 대역. (#2817)

boto3 클라이언트에서 저장소가 부르는 네 메서드(`put_object`·`get_object`·
`delete_object`·`head_object`)만 흉내 낸다. 버킷 내용은 인스턴스 밖의 dict 로 줄 수
있어, **서로 다른 클라이언트·저장소 인스턴스가 같은 버킷을 보는** 상황(재배포 뒤의
새 컨테이너, 두 번째 인스턴스)을 만들 수 있다.
"""
from __future__ import annotations

import io


class FakeClientError(Exception):
    """botocore `ClientError` 와 같은 모양 — `response["Error"]["Code"]`."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeS3:
    def __init__(self, objects: dict[tuple[str, str], tuple[bytes, str]] | None = None):
        #: (bucket, key) → (bytes, content type)
        self.objects = objects if objects is not None else {}
        #: 다음 호출을 이 코드로 실패시킨다(장애 흉내).
        self.fail_with: str | None = None
        self.calls: list[tuple[str, str]] = []

    def _maybe_fail(self) -> None:
        if self.fail_with is not None:
            raise FakeClientError(self.fail_with)

    def put_object(self, *, Bucket: str, Key: str, Body: bytes, ContentType: str):
        self.calls.append(("put", Key))
        self._maybe_fail()
        self.objects[(Bucket, Key)] = (bytes(Body), ContentType)
        return {}

    def get_object(self, *, Bucket: str, Key: str):
        self.calls.append(("get", Key))
        self._maybe_fail()
        if (Bucket, Key) not in self.objects:
            raise FakeClientError("NoSuchKey")
        data, content_type = self.objects[(Bucket, Key)]
        return {
            "Body": io.BytesIO(data),
            "ContentLength": len(data),
            "ContentType": content_type,
        }

    def delete_object(self, *, Bucket: str, Key: str):
        self.calls.append(("delete", Key))
        self._maybe_fail()
        self.objects.pop((Bucket, Key), None)
        return {}

    def head_object(self, *, Bucket: str, Key: str):
        self.calls.append(("head", Key))
        self._maybe_fail()
        if (Bucket, Key) not in self.objects:
            raise FakeClientError("404")
        return {"ContentLength": len(self.objects[(Bucket, Key)][0])}
