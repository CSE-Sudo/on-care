// GENERATED — 손으로 고치지 말 것.
//
// `python3 tool/gen_demo_fixture.py` 가
// `shared/demo_fixture/assets/kim_minsu.json` 과 함께 만든다. 고칠 값은 그 JSON 에
// 있고, 두 파일이 어긋나면 패키지 테스트가 잡는다.

/// 김민수 데모 픽스처의 JSON 원문.
const String kimMinsuFixtureJson = r'''
{
  "version": 1,
  "readme": "김민수 데모 데이터의 단일 원본. 사용자앱·트레이너웹·백엔드가 이 파일만 읽는다. 날짜는 상대값이다 — weeks[].weeksAgo 는 이번 주 월요일에서 몇 주 거슬러 올라가는지, days[].weekday 는 월(0)~일(6). recent[].offset 은 오늘로부터의 일수이고 주 격자 위를 덮는다. 이행률은 exercises[].done 개수에서 계산한다 — 퍼센트를 따로 적지 않는다.",
  "member": {
    "name": "김민수",
    "userAppSeedId": "user-7d4e9a2c5f18",
    "trainerClientId": "seed-client-1"
  },
  "historyWeeks": 35,
  "foods": {
    "oatmeal": {
      "name": "오트밀",
      "amountG": 240,
      "calories": 250,
      "sodiumMg": 100,
      "sugarG": 6.0,
      "carbsG": 42.0,
      "proteinG": 10.0,
      "fatG": 6.0
    },
    "banana": {
      "name": "바나나",
      "amountG": 120,
      "calories": 105,
      "sodiumMg": 1,
      "sugarG": 14.0,
      "carbsG": 27.0,
      "proteinG": 1.3,
      "fatG": 0.4
    },
    "greek-yogurt": {
      "name": "그릭 요거트",
      "amountG": 170,
      "calories": 170,
      "sodiumMg": 75,
      "sugarG": 7.0,
      "carbsG": 8.0,
      "proteinG": 18.0,
      "fatG": 8.0
    },
    "nuts": {
      "name": "견과류",
      "amountG": 25,
      "calories": 150,
      "sodiumMg": 5,
      "sugarG": 2.0,
      "carbsG": 6.0,
      "proteinG": 5.0,
      "fatG": 13.0
    },
    "scrambled-egg": {
      "name": "스크램블 에그",
      "amountG": 120,
      "calories": 185,
      "sodiumMg": 220,
      "sugarG": 0.8,
      "carbsG": 2.0,
      "proteinG": 13.0,
      "fatG": 14.0
    },
    "strawberry": {
      "name": "딸기",
      "amountG": 100,
      "calories": 32,
      "sodiumMg": 1,
      "sugarG": 5.5,
      "carbsG": 8.0,
      "proteinG": 0.5,
      "fatG": 0.5
    },
    "chicken-salad": {
      "name": "닭가슴살 샐러드",
      "amountG": 300,
      "calories": 315,
      "sodiumMg": 395,
      "sugarG": 10.0,
      "carbsG": 19.0,
      "proteinG": 34.0,
      "fatG": 11.1
    },
    "bibimbap": {
      "name": "야채비빔밥",
      "amountG": 500,
      "calories": 610,
      "sodiumMg": 900,
      "sugarG": 12.0,
      "carbsG": 92.0,
      "proteinG": 20.0,
      "fatG": 16.0
    },
    "jjamppong": {
      "name": "짬뽕",
      "amountG": 700,
      "calories": 750,
      "sodiumMg": 3200,
      "sugarG": 8.5,
      "carbsG": 107.0,
      "proteinG": 29.0,
      "fatG": 22.5
    },
    "doenjang-jjigae": {
      "name": "된장찌개",
      "amountG": 400,
      "calories": 300,
      "sodiumMg": 1300,
      "sugarG": 5.0,
      "carbsG": 18.0,
      "proteinG": 24.0,
      "fatG": 15.0
    },
    "rice": {
      "name": "밥",
      "amountG": 210,
      "calories": 310,
      "sodiumMg": 5,
      "sugarG": 0.7,
      "carbsG": 67.0,
      "proteinG": 6.0,
      "fatG": 2.5
    },
    "grilled-salmon": {
      "name": "연어구이",
      "amountG": 190,
      "calories": 395,
      "sodiumMg": 505,
      "sugarG": 9.0,
      "carbsG": 19.0,
      "proteinG": 35.0,
      "fatG": 19.0
    },
    "brown-rice": {
      "name": "현미밥",
      "amountG": 190,
      "calories": 280,
      "sodiumMg": 5,
      "sugarG": 0.0,
      "carbsG": 58.0,
      "proteinG": 6.0,
      "fatG": 2.0
    },
    "sweet-potato": {
      "name": "고구마",
      "amountG": 100,
      "calories": 130,
      "sodiumMg": 20,
      "sugarG": 6.5,
      "carbsG": 30.0,
      "proteinG": 2.0,
      "fatG": 0.2
    },
    "iced-americano": {
      "name": "아이스 아메리카노",
      "amountG": 350,
      "calories": 10,
      "sodiumMg": 5,
      "sugarG": 0.0,
      "carbsG": 2.0,
      "proteinG": 0.5,
      "fatG": 0.0
    },
    "nut-pack": {
      "name": "견과류 한 봉",
      "amountG": 15,
      "calories": 90,
      "sodiumMg": 2,
      "sugarG": 3.0,
      "carbsG": 1.0,
      "proteinG": 2.0,
      "fatG": 8.0
    },
    "samgyeopsal": {
      "name": "삼겹살 2인분",
      "amountG": 400,
      "calories": 620,
      "sodiumMg": 880,
      "sugarG": 1.0,
      "carbsG": 2.0,
      "proteinG": 42.0,
      "fatG": 50.0
    },
    "soju": {
      "name": "소주 1병",
      "amountG": 360,
      "calories": 55,
      "sodiumMg": 0,
      "sugarG": 0.0,
      "carbsG": 0.0,
      "proteinG": 0.0,
      "fatG": 0.0
    },
    "choco-cake": {
      "name": "초코 케이크 한 조각",
      "amountG": 90,
      "calories": 330,
      "sodiumMg": 280,
      "sugarG": 24.0,
      "carbsG": 42.0,
      "proteinG": 5.0,
      "fatG": 15.0
    },
    "cafe-latte": {
      "name": "카페라떼",
      "amountG": 200,
      "calories": 100,
      "sodiumMg": 95,
      "sugarG": 5.3,
      "carbsG": 10.0,
      "proteinG": 5.0,
      "fatG": 4.0
    }
  },
  "meals": {
    "breakfast-oatmeal-banana": {
      "mealType": "breakfast",
      "timeLabel": "08:05",
      "photoAsset": "assets/images/diet-oatmeal-banana.jpeg",
      "aiComment": "오트밀로 식이섬유를 챙긴 아침이에요.",
      "foods": [
        "oatmeal",
        "banana"
      ]
    },
    "breakfast-greek-yogurt-nuts": {
      "mealType": "breakfast",
      "timeLabel": "08:30",
      "photoAsset": "assets/images/diet-greek-yogurt-nuts.jpeg",
      "aiComment": "단백질과 불포화지방을 고르게 섭취했어요.",
      "foods": [
        "greek-yogurt",
        "nuts"
      ]
    },
    "breakfast-egg-strawberry": {
      "mealType": "breakfast",
      "timeLabel": "07:50",
      "photoAsset": "assets/images/breakfast-scrambled-egg-strawberry.jpg",
      "aiComment": "달걀 단백질에 과일로 비타민을 더했어요.",
      "foods": [
        "scrambled-egg",
        "strawberry"
      ]
    },
    "lunch-chicken-salad": {
      "mealType": "lunch",
      "timeLabel": "12:30",
      "photoAsset": "assets/images/diet-chicken-salad.jpg",
      "aiComment": "닭가슴살과 채소로 단백질·식이섬유를 챙겼어요.",
      "foods": [
        "chicken-salad"
      ]
    },
    "lunch-bibimbap": {
      "mealType": "lunch",
      "timeLabel": "12:20",
      "photoAsset": "assets/images/diet-vegetable-bibimbap.jpg",
      "aiComment": "야채가 풍부해요. 고추장을 줄이면 나트륨이 더 좋아져요.",
      "foods": [
        "bibimbap"
      ]
    },
    "lunch-jjamppong": {
      "mealType": "lunch",
      "timeLabel": "12:50",
      "photoAsset": "assets/images/lunch-jjamppong.jpg",
      "aiComment": "국물 나트륨이 높은 날이에요. 국물은 남기는 편이 좋아요.",
      "foods": [
        "jjamppong"
      ]
    },
    "lunch-doenjang-rice": {
      "mealType": "lunch",
      "timeLabel": "12:10",
      "photoAsset": "assets/images/diet-doenjang-rice.jpeg",
      "aiComment": "집밥 한 상이에요. 찌개 국물만 조금 남겨 보세요.",
      "foods": [
        "doenjang-jjigae",
        "rice"
      ]
    },
    "dinner-salmon-brown-rice": {
      "mealType": "dinner",
      "timeLabel": "18:40",
      "photoAsset": "assets/images/diet-salmon-brown-rice.jpeg",
      "aiComment": "연어의 지방과 현미밥의 복합 탄수화물 조합이 좋아요.",
      "foods": [
        "grilled-salmon",
        "brown-rice"
      ]
    },
    "dinner-doenjang-rice": {
      "mealType": "dinner",
      "timeLabel": "19:10",
      "photoAsset": "assets/images/diet-doenjang-rice.jpeg",
      "aiComment": "포만감은 좋지만 국물 나트륨이 높은 편이에요.",
      "foods": [
        "doenjang-jjigae",
        "rice"
      ]
    },
    "dinner-chicken-salad-sweet-potato": {
      "mealType": "dinner",
      "timeLabel": "18:20",
      "photoAsset": "assets/images/diet-chicken-salad.jpg",
      "aiComment": "가볍게 마무리한 저녁이에요.",
      "foods": [
        "chicken-salad",
        "sweet-potato"
      ]
    },
    "dinner-samgyeopsal": {
      "mealType": "dinner",
      "timeLabel": "19:30",
      "photoAsset": "assets/images/diet-doenjang-rice.jpeg",
      "aiComment": "고기와 술이 함께여서 칼로리가 크게 올라갔어요. 다음 날은 가볍게 시작해 보세요.",
      "foods": [
        "samgyeopsal",
        "rice",
        "soju"
      ]
    },
    "snack-coffee-nuts": {
      "mealType": "snack",
      "timeLabel": "15:40",
      "photoAsset": "assets/images/snack-coffee-nuts.jpg",
      "aiComment": "당류가 낮고 건강한 지방을 채운 간식이에요.",
      "foods": [
        "iced-americano",
        "nut-pack"
      ]
    },
    "snack-cake-latte": {
      "mealType": "snack",
      "timeLabel": "21:10",
      "photoAsset": "assets/images/snack-coffee-nuts.jpg",
      "aiComment": "디저트로 당류가 하루 목표를 넘었어요.",
      "foods": [
        "choco-cake",
        "cafe-latte"
      ]
    }
  },
  "recent": [
    {
      "offset": 0,
      "label": "PT 세션 · 트레이너 지도",
      "pt": true,
      "clientFeedback": "무릎이 좀 당겼지만 트레이너님 덕분에 잘 마쳤어요 😊",
      "trainerNote": "무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.",
      "dayMessage": "점심 짬뽕으로 오늘 나트륨 섭취가 많았어요. 저녁은 양념을 줄인 채소와 단백질 위주로 구성해 보세요.",
      "exercises": [
        {
          "name": "벤치프레스",
          "type": "strength",
          "minutes": 12,
          "calories": 72,
          "done": true,
          "sets": 4,
          "reps": 10,
          "weight": 40
        },
        {
          "name": "덤벨 숄더프레스",
          "type": "strength",
          "minutes": 10,
          "calories": 60,
          "done": true,
          "sets": 4,
          "reps": 12,
          "weight": 10
        },
        {
          "name": "랫풀다운",
          "type": "strength",
          "minutes": 12,
          "calories": 72,
          "done": true,
          "sets": 4,
          "reps": 12,
          "weight": 45
        },
        {
          "name": "플랭크 60초",
          "type": "strength",
          "minutes": 6,
          "calories": 36,
          "done": true,
          "sets": 3,
          "weight": 0
        }
      ],
      "meals": [
        {
          "meal": "breakfast-egg-strawberry",
          "id": "seed-diet-breakfast",
          "timeLabel": "08:20",
          "aiComment": "단백질과 식이섬유의 깔끔한 조합으로, 소금 간과 기름만 조절하면 혈당과 혈압 모두 잡는 우수한 식단입니다."
        },
        {
          "meal": "lunch-jjamppong",
          "id": "seed-diet-lunch",
          "timeLabel": "12:40",
          "aiComment": "정제 면과 높은 나트륨으로 혈압·혈당 부담이 매우 크니, 국물은 남기고 야채 위주로 드시는 것이 좋습니다."
        },
        {
          "meal": "snack-coffee-nuts",
          "id": "seed-diet-snack",
          "timeLabel": "15:30",
          "aiComment": "당류와 칼로리가 낮고 견과류의 건강한 지방이 채워져 완벽한 간식입니다."
        }
      ]
    },
    {
      "offset": 1,
      "label": "AI 개인운동",
      "pt": false,
      "clientFeedback": "하체 스트레칭은 시간이 없어서 못 했어요",
      "trainerNote": "",
      "dayMessage": "약속이 있어 칼로리와 당류가 목표를 넘은 하루예요. 오늘은 가볍게 시작해 보세요.",
      "exercises": [
        {
          "name": "저강도 유산소 (걷기)",
          "type": "cardio",
          "minutes": 30,
          "calories": 270,
          "done": true
        },
        {
          "name": "코어 강화",
          "type": "strength",
          "minutes": 10,
          "calories": 60,
          "done": true,
          "sets": 3,
          "reps": 15
        },
        {
          "name": "어깨 관절 보호 스트레칭",
          "type": "stretching",
          "minutes": 8,
          "calories": 24,
          "done": true
        },
        {
          "name": "하체 스트레칭",
          "type": "stretching",
          "minutes": 15,
          "calories": 45,
          "done": false
        }
      ],
      "meals": [
        {
          "meal": "breakfast-oatmeal-banana",
          "id": "seed-diet-yesterday-breakfast",
          "timeLabel": "08:10",
          "aiComment": "오트밀로 식이섬유를 챙겼어요. 바나나가 들어가 당류는 다소 높은 편이에요."
        },
        {
          "meal": "lunch-bibimbap",
          "id": "seed-diet-yesterday-lunch",
          "timeLabel": "12:30",
          "aiComment": "야채가 풍부한 비빔밥이에요. 고추장을 줄이면 나트륨을 더 조절할 수 있어요."
        },
        {
          "meal": "dinner-samgyeopsal",
          "id": "seed-diet-yesterday-dinner"
        },
        {
          "meal": "snack-cake-latte",
          "id": "seed-diet-yesterday-snack"
        }
      ]
    },
    {
      "offset": 2,
      "label": "AI 개인운동",
      "pt": false,
      "clientFeedback": "오늘은 다 했어요! 뿌듯해요 💪",
      "trainerNote": "",
      "dayMessage": "연어와 현미밥으로 탄단지 균형을 잘 맞췄어요.",
      "exercises": [
        {
          "name": "저강도 유산소 (걷기)",
          "type": "cardio",
          "minutes": 30,
          "calories": 270,
          "done": true
        },
        {
          "name": "코어 강화",
          "type": "strength",
          "minutes": 10,
          "calories": 60,
          "done": true,
          "sets": 3,
          "reps": 15
        },
        {
          "name": "하체 스트레칭",
          "type": "stretching",
          "minutes": 15,
          "calories": 45,
          "done": true
        }
      ],
      "meals": [
        {
          "meal": "breakfast-greek-yogurt-nuts",
          "id": "seed-diet-two-days-ago-breakfast",
          "timeLabel": "08:35",
          "aiComment": "그릭 요거트의 단백질과 견과류의 불포화지방을 고르게 섭취했어요."
        },
        {
          "meal": "lunch-bibimbap",
          "id": "seed-diet-two-days-ago-lunch",
          "timeLabel": "12:20",
          "aiComment": "야채가 풍부한 비빔밥이에요. 고추장을 줄이면 나트륨을 더 조절할 수 있어요."
        },
        {
          "meal": "dinner-salmon-brown-rice",
          "id": "seed-diet-two-days-ago-dinner",
          "timeLabel": "18:50",
          "aiComment": "연어의 지방과 현미밥의 복합 탄수화물 조합이 좋아요."
        }
      ]
    }
  ],
  "weeks": [
    {
      "weeksAgo": 0,
      "note": "평소의 한 주 — 국물이 잦지만 기록은 성실하다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 1,
      "note": "가볍게 간 한 주 — 세 지표가 모두 목표 안에 든다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 2,
      "note": "회식이 몰린 주 — 칼로리와 당류가 함께 목표를 넘는다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-samgyeopsal"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 3,
      "note": "코칭이 먹힌 주 — 국물을 줄여 나트륨이 목표 안으로 들어온다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            },
            {
              "name": "북한산 등산",
              "type": "other",
              "minutes": 90,
              "calories": 450,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 4,
      "note": "평범한 한 주 — 구내식당 국물이 나트륨을 밀어 올린다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 5,
      "note": "야근이 많던 주 — 늦은 저녁은 기록이 비어 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "PT 세션 · 트레이너 지도",
          "pt": true,
          "clientFeedback": "레그프레스 무게가 붙었어요. 마지막 세트가 힘들었어요.",
          "trainerNote": "하체 근력 향상 확인. 다음 세션 레그프레스 5kg 증량.",
          "exercises": [
            {
              "name": "레그프레스",
              "type": "strength",
              "minutes": 12,
              "calories": 72,
              "done": true,
              "sets": 4,
              "reps": 12,
              "weight": 70
            },
            {
              "name": "레그컬",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 12,
              "weight": 35
            },
            {
              "name": "카프레이즈",
              "type": "strength",
              "minutes": 6,
              "calories": 36,
              "done": true,
              "sets": 3,
              "reps": 20,
              "weight": 0
            },
            {
              "name": "마무리 러닝머신",
              "type": "cardio",
              "minutes": 15,
              "calories": 135,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 6,
      "note": "기록을 막 시작한 주 — 아예 빠진 날이 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 4,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 7,
      "note": "평소의 한 주 — 국물이 잦지만 기록은 성실하다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 8,
      "note": "가볍게 간 한 주 — 세 지표가 모두 목표 안에 든다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            },
            {
              "name": "탁구",
              "type": "other",
              "minutes": 40,
              "calories": 200,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 9,
      "note": "회식이 몰린 주 — 칼로리와 당류가 함께 목표를 넘는다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-samgyeopsal"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 10,
      "note": "코칭이 먹힌 주 — 국물을 줄여 나트륨이 목표 안으로 들어온다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 11,
      "note": "평범한 한 주 — 구내식당 국물이 나트륨을 밀어 올린다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "PT 세션 · 트레이너 지도",
          "pt": true,
          "clientFeedback": "데드리프트 자세를 잡아주셔서 허리가 편했어요.",
          "trainerNote": "데드리프트 힙힌지 안정적. 중량 55kg 유지 후 다음 달 60kg.",
          "exercises": [
            {
              "name": "데드리프트",
              "type": "strength",
              "minutes": 12,
              "calories": 72,
              "done": true,
              "sets": 4,
              "reps": 8,
              "weight": 55
            },
            {
              "name": "루마니안 데드리프트",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 10,
              "weight": 40
            },
            {
              "name": "플랭크 45초",
              "type": "strength",
              "minutes": 6,
              "calories": 36,
              "done": true,
              "sets": 3,
              "weight": 0
            },
            {
              "name": "마무리 러닝머신",
              "type": "cardio",
              "minutes": 12,
              "calories": 108,
              "done": true
            },
            {
              "name": "허리 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 12,
      "note": "야근이 많던 주 — 늦은 저녁은 기록이 비어 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 13,
      "note": "기록을 막 시작한 주 — 아예 빠진 날이 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 4,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 14,
      "note": "평소의 한 주 — 국물이 잦지만 기록은 성실하다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            },
            {
              "name": "자전거 라이딩",
              "type": "other",
              "minutes": 60,
              "calories": 300,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 15,
      "note": "가볍게 간 한 주 — 세 지표가 모두 목표 안에 든다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 16,
      "note": "회식이 몰린 주 — 칼로리와 당류가 함께 목표를 넘는다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-samgyeopsal"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 17,
      "note": "코칭이 먹힌 주 — 국물을 줄여 나트륨이 목표 안으로 들어온다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "PT 세션 · 트레이너 지도",
          "pt": true,
          "clientFeedback": "어깨가 아직 조금 불편해서 무게를 낮췄어요.",
          "trainerNote": "오른쪽 어깨 가동범위 제한. 숄더프레스 중량 낮추고 밴드 보강 병행.",
          "exercises": [
            {
              "name": "숄더프레스",
              "type": "strength",
              "minutes": 12,
              "calories": 72,
              "done": true,
              "sets": 4,
              "reps": 12,
              "weight": 10
            },
            {
              "name": "밴드 외전",
              "type": "strength",
              "minutes": 6,
              "calories": 36,
              "done": true,
              "sets": 3,
              "reps": 20,
              "weight": 0
            },
            {
              "name": "인클라인 푸시업",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 12,
              "weight": 0
            },
            {
              "name": "마무리 러닝머신",
              "type": "cardio",
              "minutes": 10,
              "calories": 90,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 12,
              "calories": 36,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 18,
      "note": "평범한 한 주 — 구내식당 국물이 나트륨을 밀어 올린다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 19,
      "note": "야근이 많던 주 — 늦은 저녁은 기록이 비어 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 20,
      "note": "기록을 막 시작한 주 — 아예 빠진 날이 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 4,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 21,
      "note": "평소의 한 주 — 국물이 잦지만 기록은 성실하다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 22,
      "note": "가볍게 간 한 주 — 세 지표가 모두 목표 안에 든다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 23,
      "note": "회식이 몰린 주 — 칼로리와 당류가 함께 목표를 넘는다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "PT 세션 · 트레이너 지도",
          "pt": true,
          "clientFeedback": "벤치프레스가 처음이라 어색했지만 재밌었어요 💪",
          "trainerNote": "상체 근력 기초 확인. 벤치프레스 35kg 로 시작해 자세 우선.",
          "exercises": [
            {
              "name": "벤치프레스",
              "type": "strength",
              "minutes": 12,
              "calories": 72,
              "done": true,
              "sets": 4,
              "reps": 10,
              "weight": 35
            },
            {
              "name": "체스트프레스",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 12,
              "weight": 25
            },
            {
              "name": "랫풀다운",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 12,
              "weight": 30
            },
            {
              "name": "마무리 러닝머신",
              "type": "cardio",
              "minutes": 15,
              "calories": 135,
              "done": true
            },
            {
              "name": "상체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-samgyeopsal"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 24,
      "note": "코칭이 먹힌 주 — 국물을 줄여 나트륨이 목표 안으로 들어온다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 25,
      "note": "평범한 한 주 — 구내식당 국물이 나트륨을 밀어 올린다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 26,
      "note": "야근이 많던 주 — 늦은 저녁은 기록이 비어 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 27,
      "note": "기록을 막 시작한 주 — 아예 빠진 날이 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 4,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 28,
      "note": "평소의 한 주 — 국물이 잦지만 기록은 성실하다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 29,
      "note": "가볍게 간 한 주 — 세 지표가 모두 목표 안에 든다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "PT 세션 · 트레이너 지도",
          "pt": true,
          "clientFeedback": "첫 PT 라 긴장했는데 생각보다 할 만했어요.",
          "trainerNote": "첫 세션. 체력 수준 점검 위주로 가볍게 진행.",
          "exercises": [
            {
              "name": "고블릿 스쿼트",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 12,
              "weight": 12
            },
            {
              "name": "케틀벨 스윙",
              "type": "strength",
              "minutes": 9,
              "calories": 54,
              "done": true,
              "sets": 3,
              "reps": 15,
              "weight": 12
            },
            {
              "name": "코어 서킷",
              "type": "strength",
              "minutes": 6,
              "calories": 36,
              "done": true,
              "sets": 2,
              "reps": 12,
              "weight": 0
            },
            {
              "name": "마무리 러닝머신",
              "type": "cardio",
              "minutes": 10,
              "calories": 90,
              "done": true
            },
            {
              "name": "전신 스트레칭",
              "type": "stretching",
              "minutes": 12,
              "calories": 36,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 30,
      "note": "회식이 몰린 주 — 칼로리와 당류가 함께 목표를 넘는다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-samgyeopsal"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-samgyeopsal"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-cake-latte"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 31,
      "note": "코칭이 먹힌 주 — 국물을 줄여 나트륨이 목표 안으로 들어온다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 32,
      "note": "평범한 한 주 — 구내식당 국물이 나트륨을 밀어 올린다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 33,
      "note": "야근이 많던 주 — 늦은 저녁은 기록이 비어 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 40,
              "calories": 360,
              "done": false
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": true,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 4,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 45,
              "calories": 405,
              "done": true
            },
            {
              "name": "어깨 관절 보호 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": true,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": true
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        }
      ]
    },
    {
      "weeksAgo": 34,
      "note": "기록을 막 시작한 주 — 아예 빠진 날이 있다.",
      "days": [
        {
          "weekday": 0,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 30,
              "calories": 270,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 10,
              "calories": 60,
              "done": true,
              "sets": 3,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 1,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 2,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-doenjang-rice"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        },
        {
          "weekday": 3,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 35,
              "calories": 315,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 20,
              "calories": 120,
              "done": false,
              "sets": 5,
              "reps": 15
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 5,
              "calories": 15,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-greek-yogurt-nuts"
            },
            {
              "meal": "lunch-doenjang-rice"
            }
          ]
        },
        {
          "weekday": 4,
          "exercises": [],
          "meals": []
        },
        {
          "weekday": 5,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 25,
              "calories": 225,
              "done": true
            },
            {
              "name": "코어 강화",
              "type": "strength",
              "minutes": 30,
              "calories": 180,
              "done": false,
              "sets": 8,
              "reps": 12
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 15,
              "calories": 45,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-oatmeal-banana"
            },
            {
              "meal": "lunch-bibimbap"
            },
            {
              "meal": "dinner-chicken-salad-sweet-potato"
            },
            {
              "meal": "snack-coffee-nuts"
            }
          ]
        },
        {
          "weekday": 6,
          "label": "AI 개인운동",
          "pt": false,
          "exercises": [
            {
              "name": "저강도 유산소 (걷기)",
              "type": "cardio",
              "minutes": 20,
              "calories": 180,
              "done": true
            },
            {
              "name": "하체 스트레칭",
              "type": "stretching",
              "minutes": 10,
              "calories": 30,
              "done": false
            }
          ],
          "meals": [
            {
              "meal": "breakfast-egg-strawberry"
            },
            {
              "meal": "lunch-chicken-salad"
            },
            {
              "meal": "dinner-salmon-brown-rice"
            }
          ]
        }
      ]
    }
  ],
  "routines": [
    {
      "id": "seed-routine-user-7d4e9a2c5f18-0",
      "name": "저강도 유산소 (걷기)",
      "minutes": 30,
      "type": "유산소",
      "reason": "혈압 안정에 효과적",
      "source": "ai"
    },
    {
      "id": "seed-routine-user-7d4e9a2c5f18-1",
      "name": "하체 스트레칭",
      "minutes": 15,
      "type": "스트레칭",
      "reason": "혈액순환 개선",
      "source": "trainer"
    },
    {
      "id": "seed-routine-user-7d4e9a2c5f18-2",
      "name": "코어 강화",
      "minutes": 10,
      "type": "근력",
      "reason": "기초대사량 향상",
      "source": "ai",
      "sets": 3,
      "reps": 15,
      "weight": 0
    },
    {
      "id": "seed-routine-user-7d4e9a2c5f18-3",
      "name": "어깨 관절 보호 스트레칭",
      "minutes": 8,
      "type": "스트레칭",
      "reason": "PT 피드백 반영 · 오른쪽 어깨 보호",
      "source": "trainer"
    }
  ]
}
''';
