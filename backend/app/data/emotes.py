"""채팅 이모티콘 id 목록 — 서버가 아는 값. (#2020)

앱이 보낸 id 가 우리가 아는 것인지만 본다. 그림과 묶음 이름은 앱에 있다(패키지
`oncare_ui` 의 에셋) — 서버가 그림을 들고 있을 이유가 없고, **id 는 지난 대화에
그대로 남는 값이라 바꾸지 않는다.**

모르는 id 를 그냥 저장하면, 앱이 그리지 못하는 빈 말풍선이 대화에 영구히 남는다.
"""

EMOTE_IDS: frozenset[str] = frozenset({
    # 오운완
    "oni_owoon",  # 오운완
    "oni_gains",  # 득근
    "oni_onfire",  # 불태움
    "oni_pr",  # 기록 갱신
    "oni_did_it",  # 해냈다
    "oni_drenched",  # 땀범벅
    # 하체데이
    "oni_help",  # 살려줘
    "oni_shaky",  # 후들후들
    "oni_one_more",  # 한 세트 더?
    "oni_sore",  # 근육통
    "oni_crawl",  # 기어감
    "oni_soul_out",  # 영혼 탈출
    # 식단
    "oni_cheat",  # 치팅데이
    "oni_breast",  # 닭가슴살
    "oni_held_back",  # 참았다
    "oni_midnight",  # 야식 고백
    "oni_water",  # 물 2L
    "oni_protein",  # 단백질 충전
    # 쌤이랑
    "oni_yes_coach",  # 네 쌤!
    "oni_thanks",  # 감사합니다
    "oni_see_you",  # 내일 봬요
    "oni_got_it",  # 확인했어요
    "oni_late",  # 늦어요ㅠ
    "oni_best",  # 쌤 최고
    # 컨디션
    "oni_great",  # 컨디션 최고
    "oni_tired",  # 피곤해요
    "oni_sleepy",  # 잠 부족
    "oni_stiff",  # 뻐근해요
    "oni_hurts",  # 아파요
    "oni_recover",  # 회복 중
    # 리액션
    "oni_lets_go",  # 가보자고
    "oni_can_do",  # 할 수 있다
    "oni_rest",  # 오늘은 쉼
    "oni_tomorrow",  # 내일부터
    "oni_agree",  # 인정
    "oni_lol",  # ㅋㅋㅋ
    # 댕댕
    "dog_walked",  # 산책 완료
    "dog_woof",  # 멍!
    "dog_snack",  # 간식 줘
    "dog_wag",  # 꼬리 흔들
    "dog_sleepy",  # 졸려
    "dog_praise",  # 칭찬해줘
    "dog_owoon",  # 댕운완
    "dog_love",  # 사랑해
    "dog_cool",  # 멋짐
    "dog_hehe",  # 헤헤
    "dog_sulky",  # 시무룩
    "dog_run",  # 달려!
    # 냥이
    "cat_owoon",  # 냥운완
    "cat_meh",  # 귀찮냥
    "cat_lying",  # 누워있냥
    "cat_churu",  # 츄르 줘
    "cat_knead",  # 꾹꾹이
    "cat_whatever",  # 관심 없냥
    "cat_hiss",  # 하악
    "cat_crush",  # 심쿵
    "cat_chic",  # 시크
    "cat_hide",  # 숨숨
    "cat_stretch",  # 기지개
    "cat_king",  # 냥님
})
