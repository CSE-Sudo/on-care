"""
RAG 문서 관리 라우터.

  POST /coach/documents/public  -> 공공문서 적재 (user_id=NULL, 전체 공유)
       body: { content, domain, title }

회원 개인 기록(식단·운동·채팅 요약)은 기록이 생길 때 자동 적재하므로
여기서는 공공문서 업로드만 노출합니다. (스크립트 scripts/ingest_public 도 동일 기능)

관리자 전용입니다 — 비관리자는 403, 미인증은 401. 적재는 감사 로그에 남습니다.
"""
from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.deps import RequireAdmin
from app.db.session import get_db
from app.services.audit import client_ip, record as audit
from app.services.coach.rag import ingest_document

logger = logging.getLogger(__name__)

router = APIRouter(tags=["coach-docs"])


class PublicDocIn(BaseModel):
    content: str
    domain: str = "general"  # diet|exercise|general
    title: str = ""
    source: str = "public"


@router.post("/coach/documents/public", status_code=201)
def upload_public_doc(
    payload: PublicDocIn,
    admin: RequireAdmin,  # 관리자 전용(비관리자 403, 미인증 401)
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    if not payload.content.strip():
        raise HTTPException(status_code=400, detail="content 가 비어 있어요.")
    try:
        n = ingest_document(
            db, payload.content, user_id=None,
            domain=payload.domain, source=payload.source, title=payload.title,
        )
    except RuntimeError:
        # 임베딩 키 미설정 등. 예외 문자열에는 provider·설정 값이 섞일 수 있어 응답에
        # 싣지 않는다 — 원인은 서버 로그에만 남기고, 상관은 응답의 `X-Request-ID` 로
        # 한다(로그 포맷이 같은 request id 를 찍는다). (#1556)
        logger.exception("public doc ingest unavailable")
        raise HTTPException(
            status_code=503, detail="임베딩을 사용할 수 없어 문서를 적재하지 못했어요."
        )
    except Exception:  # noqa: BLE001
        # SDK·DB·파일 경로 오류의 문자열이 그대로 응답에 실리던 자리다. 관리자 전용
        # 경로라 노출 범위는 좁지만, 내부 상세를 감추는 전역 500 처리와 형태를 맞춘다.
        logger.exception("public doc ingest failed")
        raise HTTPException(status_code=502, detail="문서를 적재하지 못했어요.")
    audit(
        db, event="admin.public_doc_upload", user_id=admin.id,
        ip=client_ip(request), success=True, detail=f"{payload.domain}:{payload.title}",
    )
    return {"ingested_chunks": n, "domain": payload.domain, "title": payload.title}
