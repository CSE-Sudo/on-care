part of 'seed_data.dart';

/// 데모 시드의 영어판 — 한국어 원문 → 영어. (#2304)
///
/// 시드 데이터(수치·순서·날짜 규칙)는 한 벌만 둔다. 영어판을 따로 복사해 두면
/// 숫자를 고칠 때 한쪽만 바뀌어 두 언어의 데모가 서로 다른 이야기를 한다. 그래서
/// 여기에는 **문구만** 있고, 시딩이 영어로 심을 때 원문을 이 표로 바꾼다.
///
/// 김민수의 음식·운동·메모는 공유 픽스처(`tool/gen_demo_fixture.py`)에서 오지만
/// 픽스처는 회원 앱·백엔드와 함께 쓰는 원본이라 건드리지 않고, 그 문구도 이
/// 표로 옮긴다.
///
/// 원문을 고치면 이 표의 키도 같이 고쳐야 한다. 빠지면 영어 시드에 한국어가
/// 남고, `seed_language_test.dart` 가 그 자리를 짚는다.
///
/// 운동 한 줄(`Squat · 4 sets · 10 reps · 50kg`)은 이름 뒤를 `·` 로 끊는다 —
/// 리포트가 같은 운동을 묶을 때 첫 `·` 앞을 이름으로 읽는다(`exerciseBaseName`).
const Map<String, String> _seedEnglish = <String, String>{
  '체중 감량 · 혈압 관리': 'Weight loss · Blood pressure',
  '오늘': 'Today',
  '민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?':
      "Minsu, I went through last week's logs and your completion rate jumps around from day to day. Are some days always busier?",
  '화요일이랑 목요일이 야근이 많아요 😥': 'I usually work late on Tuesdays and Thursdays 😥',
  '그럼 그 이틀은 15분짜리 짧은 프로그램으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다':
      "Then I'll switch those two days to a short 15-minute program. It's far better than skipping",
  '그 정도면 퇴근하고도 할 수 있을 것 같아요': 'I think I can manage that after work',
  '혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요':
      "Are you still taking your blood pressure medication at the same time? I'll keep cardio away from it",
  '네, 아침 8시 그대로예요': 'Yes, still 8 a.m.',
  '확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂':
      "Got it. I've sent Tuesday and Thursday as 15-minute low-intensity sessions 🙂",
  '민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?':
      'Minsu, your sodium has been hovering around the 2,000mg target lately. Do you eat a lot of soups and stews?',
  '회사 구내식당이라 국물이 늘 나와요 😅': 'The office cafeteria always serves soup 😅',
  '국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠':
      "Leaving half the broth cuts 400–500mg. Let's start with just that",
  '오늘은 국물 안 마셨어요! 걷기도 25분 했습니다':
      'I skipped the broth today! I also walked for 25 minutes',
  '좋아요 👏 그 한 가지만 지켜도 추이가 달라져요':
      'Great 👏 That one habit alone will change the trend',
  '내일 프로그램은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요':
      "I've bumped tomorrow's program up a little to a 20-minute walk. Let's keep this pace through the weekend",
  '민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?':
      'Minsu, I got your AI diet analysis 👍 Your sodium went a bit over target today. How was your day?',
  '찌개 먹을 때 국물을 많이 마셨나봐요 😅': 'I guess I drank a lot of the stew broth 😅',
  '그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?':
      "I see! Any injuries or discomfort after today's PT?",
  '무릎이 가볍게 당기긴 했는데 괜찮아요': "My knee was a little sore, but it's fine",
  '이번 주 리포트 등록해 뒀어요. 확인해 보세요': "This week's report is up. Take a look",
  '확인했어요. AI가 오늘 식단 기반으로 유산소 프로그램을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪':
      "Got it. The AI suggested a cardio program based on today's meals, but given your knee I'll swap running for walking. See you at the next PT 💪",
  '체중 감량 · 체력 강화': 'Weight loss · Fitness',
  '어제': 'Yesterday',
  '아침': 'Breakfast',
  '그릭요거트': 'Greek yogurt',
  '블루베리': 'Blueberries',
  '점심': 'Lunch',
  '현미밥': 'Brown rice',
  '불고기': 'Bulgogi',
  '시금치나물': 'Seasoned spinach',
  '저녁': 'Dinner',
  '연어 샐러드': 'Salmon salad',
  '인터벌 런닝': 'Interval running',
  '체지방 연소 효율↑': 'Better fat burning',
  '스쿼트': 'Squat',
  '하체 근력 강화': 'Lower-body strength',
  '플랭크': 'Plank',
  '코어 안정화': 'Core stability',
  'AI 개인운동': 'AI personal exercise',
  '인터벌 런닝 25분 ✓': 'Interval running · 25 min ✓',
  '스쿼트 3세트 · 12회 · 40kg ✓': 'Squat · 3 sets · 12 reps · 40kg ✓',
  '플랭크 3세트 · 3회 · 0kg ✓': 'Plank · 3 sets · 3 reps · 0kg ✓',
  '런닝이 힘들었는데 다 했어요! 숨이 많이 찼어요':
      'The run was tough but I finished it all! I was really out of breath',
  '심폐지구력 향상 중. 다음 주 런닝 강도 소폭 올릴 예정.':
      'Cardio endurance improving. Will raise running intensity slightly next week.',
  'PT 세션 · 트레이너 지도': 'PT session · Trainer-led',
  '데드리프트 3세트 · 8회 · 55kg': 'Deadlift · 3 sets · 8 reps · 55kg',
  '런지 3세트 · 12회 · 10kg': 'Lunge · 3 sets · 12 reps · 10kg',
  '코어 서킷 2세트 · 12회 · 0kg': 'Core circuit · 2 sets · 12 reps · 0kg',
  '데드리프트 자세 교정 도움 많이 됐어요!': 'The deadlift form fixes really helped!',
  '런닝 25분 ✓': 'Running · 25 min ✓',
  '스쿼트 ✓': 'Squat ✓',
  '플랭크 ✗ (피로)': 'Plank ✗ (fatigue)',
  '마지막 플랭크는 너무 지쳐서 못 했어요': 'I was too worn out for the last plank',
  '지수님, AI 운동 데이터 수신했어요 — 오늘 인터벌 런닝 25분 완료! 컨디션은 어때요?':
      'Jisu, your AI workout data came in — 25 minutes of interval running done today! How are you feeling?',
  '생각보다 괜찮았어요. 숨이 금방 차더라고요 😮‍💨':
      'Better than I expected. I got out of breath quickly though 😮‍💨',
  '심폐 지구력 올라가는 과정이에요 💪 AI 분석 보니까 당류는 목표 안에 있고, 프로그램 다음 주부터 근력 비중 늘려볼게요. 식단도 AI 추천 참고해서 업데이트해 드릴게요':
      "That's your endurance building 💪 The AI analysis shows your sugar is within target, so from next week I'll add more strength work. I'll update your meal plan with the AI suggestions too",
  '근력 향상': 'Strength',
  '5일 전': '5 days ago',
  '삶은 계란 3개': '3 boiled eggs',
  '잼 토스트': 'Toast with jam',
  '짜장면': 'Jajangmyeon',
  '삼겹살': 'Pork belly',
  '쌈채소': 'Lettuce wraps',
  '쌈장': 'Ssamjang',
  '벤치프레스': 'Bench press',
  '상체 근력 목표': 'Upper-body strength goal',
  '데드리프트': 'Deadlift',
  '전신 근력 향상': 'Full-body strength',
  '유산소 쿨다운': 'Cardio cool-down',
  '나트륨 배출 지원': 'Helps flush sodium',
  '벤치프레스 4세트 · 8회 · 65kg': 'Bench press · 4 sets · 8 reps · 65kg',
  '인클라인 덤벨 3세트 · 10회 · 26kg':
      'Incline dumbbell press · 3 sets · 10 reps · 26kg',
  '트라이셉스 딥 3세트 · 12회 · 0kg': 'Triceps dip · 3 sets · 12 reps · 0kg',
  '가슴이 많이 타는 느낌이었어요. 좋았어요!': 'My chest was really burning. Loved it!',
  '벤치 중량 62.5kg → 65kg 도전 가능. 다음 PT 때 시도 예정.':
      'Ready to move bench from 62.5kg to 65kg. Will try at the next PT.',
  '벤치프레스 ✓': 'Bench press ✓',
  '데드리프트 ✗': 'Deadlift ✗',
  '유산소 ✗': 'Cardio ✗',
  '회사 일이 생겨서 벤치만 하고 나왔어요':
      'Something came up at work, so I only did bench and left',
  '벤치프레스 ✗': 'Bench press ✗',
  '못 갔어요 😓': "Couldn't make it 😓",
  '성호님, 이번 주 운동 기록이 AI 쪽에서 안 잡히는데 몸은 괜찮으세요?':
      "Seongho, the AI hasn't picked up any workouts from you this week. Are you doing okay?",
  '이번 주 일이 너무 많아서 못 갔어요 😓': "Work was crazy this week so I couldn't go 😓",
  '이해해요! 대신 AI 식단 분석 보니까 나트륨이 좀 높더라고요. 주말에 30분 걷기라도 하면 도움 돼요. AI가 그에 맞는 프로그램 다시 짜줬으니까 앱에서 확인해보세요 🙂':
      'Totally understand! Your AI diet analysis shows sodium running a bit high, though. Even a 30-minute walk over the weekend helps. The AI has put together a matching program, so check it in the app 🙂',
  '체력 강화 · 재활': 'Fitness · Rehab',
  '통밀토스트': 'Whole-wheat toast',
  '아보카도': 'Avocado',
  '닭가슴살 도시락': 'Chicken breast lunch box',
  '채소 스프': 'Vegetable soup',
  '두부': 'Tofu',
  '저강도 걷기': 'Low-intensity walk',
  '회복기 심박 관리': 'Heart-rate control during recovery',
  '골반 안정화': 'Pelvic stability',
  '스트레칭': 'Stretching',
  '산후 코어 재활': 'Postpartum core rehab',
  '밴드 로우': 'Band row',
  '상체 자세 교정': 'Upper-body posture',
  '걷기 25분 ✓': 'Walking · 25 min ✓',
  '골반 안정화 15분 ✓': 'Pelvic stability · 15 min ✓',
  '밴드 로우 3세트 · 15회 · 0kg ✓': 'Band row · 3 sets · 15 reps · 0kg ✓',
  '컨디션 돌아온 게 느껴져요. 다 했습니다!':
      'I can feel my energy coming back. Finished everything!',
  '2주 공백 후 복귀 성공. 다음 주부터 강도 10% 상향.':
      'Back on track after a two-week break. Raising intensity 10% from next week.',
  '골반 안정화 ✗ (아이 컨디션)': 'Pelvic stability ✗ (child was unwell)',
  '아이가 아파서 절반만 했어요': 'My kid was sick, so I only did half',
  '걷기 ✗': 'Walking ✗',
  '골반 안정화 ✗': 'Pelvic stability ✗',
  '밴드 로우 ✗': 'Band row ✗',
  '한 주 통째로 쉬었어요': 'I took the whole week off',
  '하윤님, 지난주 공백 뒤에 오늘 세 개 다 채우셨네요 👏':
      "Hayun, after last week's break you finished all three today 👏",
  '몸이 다시 붙는 느낌이에요. 나트륨도 신경 썼어요!':
      "I feel like I'm getting back into shape. I watched my sodium too!",
  '추이 보니 확실히 내려왔어요. 이 페이스로 한 주만 더 가보죠 🙂':
      "The trend is clearly coming down. Let's keep this pace for one more week 🙂",
  '체력 강화': 'Fitness',
  '오트밀': 'Oatmeal',
  '바나나': 'Banana',
  '견과': 'Nuts',
  '흰살생선': 'White fish',
  '나물': 'Seasoned greens',
  '닭가슴살': 'Chicken breast',
  '고구마': 'Sweet potato',
  '파스타': 'Pasta',
  '간식': 'Snack',
  '스포츠음료': 'Sports drink',
  '바나나 2개': '2 bananas',
  'LSD 러닝': 'LSD run',
  '유산소 기반 다지기': 'Aerobic base building',
  '힙 힌지 드릴': 'Hip hinge drill',
  '러닝 이코노미 개선': 'Better running economy',
  '종아리 스트레칭': 'Calf stretch',
  '부상 예방': 'Injury prevention',
  'LSD 러닝 45분 ✓': 'LSD run · 45 min ✓',
  '힙 힌지 3세트 · 12회 · 0kg ✓': 'Hip hinge · 3 sets · 12 reps · 0kg ✓',
  '스트레칭 10분 ✓': 'Stretching · 10 min ✓',
  '페이스 안정적이었어요': 'My pace was steady',
  '7일 연속 100%. 과훈련 신호 없는지 다음 주 확인.':
      '100% for 7 days straight. Check for signs of overtraining next week.',
  '인터벌 러닝 30분 ✓': 'Interval running · 30 min ✓',
  '코어 서킷 3세트 · 12회 · 0kg ✓': 'Core circuit · 3 sets · 12 reps · 0kg ✓',
  '스트레칭 ✓': 'Stretching ✓',
  '인터벌 끝나고 다리가 후들거렸어요 😅': 'My legs were shaking after the intervals 😅',
  '우진님, 이번 주 7일 전부 100% 나왔어요. 무리는 없으세요?':
      'Woojin, you hit 100% all seven days this week. Not overdoing it?',
  '아직은 괜찮아요! 주말 장거리만 잘 넘기면 될 것 같아요':
      "I'm fine so far! I just need to get through the weekend long run",
  '좋아요. 대신 수요일은 회복 프로그램으로 잡아둘게요 🙂':
      "Sounds good. I'll make Wednesday a recovery program, though 🙂",
  '체중 감량': 'Weight loss',
  '금요일': 'Friday',
  '마라탕': 'Malatang',
  '치킨': 'Fried chicken',
  '맥주': 'Beer',
  '주말 회복 걷기': 'Weekend recovery walk',
  '주말 나트륨 배출': 'Flush weekend sodium',
  '전신 서킷': 'Full-body circuit',
  '평일 프로그램 유지': 'Keep the weekday program',
  '상체 스트레칭': 'Upper-body stretch',
  '피로 해소': 'Fatigue relief',
  '전신 서킷 ✗': 'Full-body circuit ✗',
  '스트레칭 ✗': 'Stretching ✗',
  '주말은 약속이 계속 있었어요 😅': 'I had plans all weekend 😅',
  '평일 100% / 주말 0% 패턴 5주째. 주말용 15분 프로그램으로 분리 검토.':
      'Weekdays 100% / weekends 0% for 5 weeks. Consider a separate 15-minute weekend program.',
  '전신 서킷 4세트 · 12회 · 0kg ✓': 'Full-body circuit · 4 sets · 12 reps · 0kg ✓',
  '걷기 30분 ✓': 'Walking · 30 min ✓',
  '평일엔 프로그램대로 잘 되고 있어요': 'Weekdays are going to plan',
  '서연님, 평일은 완벽한데 주말에 나트륨이 3100까지 올라갔어요':
      'Seoyeon, your weekdays are perfect, but your sodium climbed to 3,100 on the weekend',
  '주말엔 약속이 많아서요 😅 마라탕이 문제였나봐요':
      'I have a lot of plans on weekends 😅 I guess the malatang was the problem',
  '주말만 따로 15분짜리 가벼운 프로그램으로 잡아드릴게요. 안 하는 것보다 훨씬 나아요 🙂':
      "I'll set up a light 15-minute program just for weekends. It's much better than nothing 🙂",
  '자세 교정': 'Posture correction',
  '체력 측정 걷기': 'Fitness assessment walk',
  '기초 체력 파악': 'Baseline fitness check',
  '맨몸 스쿼트': 'Bodyweight squat',
  '하체 기준선 측정': 'Lower-body baseline',
  '전신 스트레칭': 'Full-body stretch',
  '가동범위 확인': 'Range-of-motion check',
  '혈압 관리': 'Blood pressure',
  '6일 전': '6 days ago',
  '편의점 삼각김밥 2개': '2 convenience-store rice balls',
  '부대찌개': 'Budae-jjigae',
  '공기밥': 'Bowl of rice',
  '족발': 'Jokbal',
  '소주': 'Soju',
  '혈압 우선 안정': 'Stabilize blood pressure first',
  '호흡 이완': 'Breathing relaxation',
  '교감신경 완화': 'Calms the nervous system',
  '의자 스쿼트': 'Chair squat',
  '최소 부하로 재시작': 'Restart with minimal load',
  '걷기 ✓ (10분만)': 'Walking ✓ (only 10 min)',
  '호흡 이완 ✗': 'Breathing relaxation ✗',
  '의자 스쿼트 ✗': 'Chair squat ✗',
  '10분 걷다가 회사에서 전화 와서 끊었어요':
      'I walked 10 minutes, then work called and I had to stop',
  '나트륨 3000 돌파 + 이행률 20%. 이번 주 안에 전화 상담 필요.':
      'Sodium over 3,000 + 20% completion. Needs a phone check-in this week.',
  '걷기 ✓': 'Walking ✓',
  '피곤해서 걷기만 했어요': 'I was tired, so I only walked',
  '세라님, 나트륨이 6일 연속 올라서 3250까지 왔어요. 혈압은 재보셨어요?':
      'Sera, your sodium has gone up six days in a row and reached 3,250. Have you checked your blood pressure?',
  '요즘 너무 바빠서 못 하고 있어요. 허리도 좀 아프고요':
      "I've been too busy to. My back hurts a bit too",
  '주말엔 꼭 재볼게요...': "I'll definitely check it this weekend...",
  '체력 강화 · 운동 습관': 'Fitness · Exercise habit',
  '4일 전': '4 days ago',
  '아메리카노': 'Americano',
  '김치찌개': 'Kimchi stew',
  '편의점 도시락': 'Convenience-store lunch box',
  '크림빵 2개': '2 cream buns',
  '퇴근 후 걷기': 'Walk after work',
  '짧게라도 유지': 'Keep it going, even briefly',
  '목·어깨 스트레칭': 'Neck and shoulder stretch',
  '장시간 착석 보완': 'Offsets long hours of sitting',
  '최소 코어 유지': 'Maintain minimal core work',
  '목·어깨 스트레칭 ✓': 'Neck and shoulder stretch ✓',
  '플랭크 ✗': 'Plank ✗',
  '자기 전에 스트레칭만 겨우 했어요': 'I barely managed a stretch before bed',
  '15분 프로그램도 못 채우는 주가 반복. 5분 버전으로 낮춰볼 것.':
      'Keeps missing even the 15-minute program. Try a 5-minute version.',
  '걷기 15분 ✓': 'Walking · 15 min ✓',
  '준혁님, 이번 주도 야근이 이어지네요. 5분짜리로 줄여볼까요?':
      'Junhyeok, more late nights this week. Shall we cut it down to 5 minutes?',
  '오늘도 야근이라 못 갈 것 같아요': 'Working late again today, so I cannot make it',
  '재활': 'Rehab',
  '두유': 'Soy milk',
  '삶은 계란 2개': '2 boiled eggs',
  '비빔밥 (고추장 절반)': 'Bibimbap (half the gochujang)',
  '샐러드': 'Salad',
  '실내 자전거': 'Stationary bike',
  '무릎 부담 없는 유산소': 'Knee-friendly cardio',
  '레그 익스텐션': 'Leg extension',
  '대퇴사두 재건': 'Rebuild the quads',
  '무릎 가동범위': 'Knee range of motion',
  '재활 프로토콜': 'Rehab protocol',
  '실내 자전거 20분 ✓': 'Stationary bike · 20 min ✓',
  '레그 익스텐션 3세트 · 12회 · 20kg ✓': 'Leg extension · 3 sets · 12 reps · 20kg ✓',
  '가동범위 10분 ✓': 'Range of motion · 10 min ✓',
  '무릎 통증 없이 다 했어요!': 'Finished everything with no knee pain!',
  '3주 연속 개선. 다음 주 러닝머신 걷기 추가 검토.':
      'Improving 3 weeks in a row. Consider adding treadmill walking next week.',
  '실내 자전거 ✓': 'Stationary bike ✓',
  '레그 익스텐션 ✓': 'Leg extension ✓',
  '가동범위 ✗': 'Range of motion ✗',
  '마지막에 시간이 부족했어요': 'I ran out of time at the end',
  '유나님, 나트륨 추이가 2800에서 1700까지 내려왔어요 👏':
      'Yuna, your sodium trend has come down from 2,800 to 1,700 👏',
  '이번 주는 다 지켰어요 :)': 'I stuck to everything this week :)',
  '무릎 상태 괜찮으면 다음 주에 걷기 조금 얹어볼게요':
      "If your knee feels okay, I'll add a little walking next week",
  '식습관 개선 · 운동 습관': 'Eating habits · Exercise habit',
  '시리얼': 'Cereal',
  '우유': 'Milk',
  '백반 정식': 'Korean set meal',
  '된장찌개': 'Doenjang stew',
  '트레드밀 경사 걷기': 'Incline treadmill walk',
  '정체 구간 자극 변화': 'New stimulus for the plateau',
  '풀업 어시스트': 'Assisted pull-up',
  '상체 자극 전환': 'Shift the upper-body stimulus',
  '회복': 'Recovery',
  '경사 걷기 ✓': 'Incline walk ✓',
  '풀업 어시스트 ✓': 'Assisted pull-up ✓',
  '늘 하던 만큼 했어요': 'Did the same as always',
  '7주째 같은 이행률·같은 나트륨. 자극 변화 필요.':
      'Same completion and sodium for 7 weeks. Needs a new stimulus.',
  '지호님, 몇 주째 수치가 거의 안 움직여요. 프로그램을 좀 바꿔볼까요?':
      'Jiho, your numbers have barely moved for weeks. Shall we change up the program?',
  '똑같은 것 같아요': 'Feels the same to me',
  '다음 주는 경사·중량 쪽으로 자극을 바꿔서 보내드릴게요 🙂':
      "Next week I'll send a program that shifts to incline and heavier weights 🙂",
  '3주 전': '3 weeks ago',
  '토스트': 'Toast',
  '커피': 'Coffee',
  '샌드위치': 'Sandwich',
  '가벼운 걷기': 'Light walk',
  '복귀 준비': 'Getting ready to return',
  '휴식기 스트레칭 유지': 'Keep stretching during the break',
  '최소 근력 유지': 'Maintain minimal strength',
  '걷기 20분 ✓': 'Walking · 20 min ✓',
  '스쿼트 ✗': 'Squat ✗',
  '당분간 쉬려고요': "I'm going to take a break for a while",
  '3주째 기록 없음. 휴면 전환. 복귀 의사 확인 필요.':
      'No logs for 3 weeks. Moved to inactive. Check whether they plan to return.',
  '가영님, 3주째 기록이 없어서요. 복귀 계획 있으실까요?':
      "Gayeong, there haven't been any logs for three weeks. Are you planning to come back?",
  '근력 향상 · 식습관 개선': 'Strength · Eating habits',
  '계란 5개': '5 eggs',
  '소고기 덮밥': 'Beef rice bowl',
  '현미밥 곱빼기': 'Large brown rice',
  '프로틴': 'Protein shake',
  '하체 볼륨 확보': 'Lower-body volume',
  '상체 볼륨 확보': 'Upper-body volume',
  '나트륨 배출': 'Flush sodium',
  '스쿼트 5세트 · 8회 · 80kg': 'Squat · 5 sets · 8 reps · 80kg',
  '벤치프레스 5세트 · 8회 · 60kg': 'Bench press · 5 sets · 8 reps · 60kg',
  '유산소 쿨다운 10분': 'Cardio cool-down · 10 min',
  '오늘은 제대로 했습니다': 'Did it properly today',
  '하는 날과 안 하는 날 편차가 큼. 주 4회 고정 스케줄 제안.':
      'Big swings between on and off days. Suggest a fixed 4-day weekly schedule.',
  '쿨다운 ✗': 'Cool-down ✗',
  '어제는 아예 못 갔어요': "I didn't go at all yesterday",
  '태경님, 하는 날은 100%인데 격일로 완전히 비네요':
      'Taekyung, you hit 100% on the days you train, but every other day is completely empty',
  '근데 식단은 자신이 없네요 😅': "I'm not so confident about my diet, though 😅",
  '식습관 개선': 'Eating habits',
  '북엇국': 'Dried pollock soup',
  '칼국수': 'Kalguksu',
  '겉절이': 'Fresh kimchi',
  '닭가슴살 샐러드': 'Chicken breast salad',
  '오렌지주스': 'Orange juice',
  '러닝머신': 'Treadmill',
  '전신 근력 서킷': 'Full-body strength circuit',
  '현 프로그램 유지': 'Keep the current program',
  '러닝머신 30분 ✓': 'Treadmill · 30 min ✓',
  '근력 서킷 25분 ✓': 'Strength circuit · 25 min ✓',
  '운동은 빠짐없이 하고 있어요': "I haven't missed a single workout",
  '이행률 100%인데 나트륨 7일 연속 초과. 식단 상담으로 전환.':
      '100% completion but sodium over target 7 days straight. Switch to diet counseling.',
  '서진님, 운동은 7일 다 채우셨어요. 다만 나트륨이 계속 2500 위예요':
      'Seojin, you completed all 7 days of workouts. Your sodium keeps staying above 2,500, though',
  '국물을 못 끊겠어요': 'I just cannot give up the broth',
  '국물만 절반 남기셔도 400~500은 빠져요. 그것부터 해보죠 🙂':
      "Leaving half the broth cuts 400–500. Let's start there 🙂",
  '운동 습관': 'Exercise habit',
  '샐러드 볼': 'Salad bowl',
  '두부 스테이크': 'Tofu steak',
  '잡곡밥': 'Multigrain rice',
  '걷기': 'Walking',
  '습관 형성 우선': 'Build the habit first',
  '부담 없는 시작': 'An easy start',
  '운동 후 회복': 'Post-workout recovery',
  '맨몸 스쿼트 3세트 · 15회 · 0kg ✓': 'Bodyweight squat · 3 sets · 15 reps · 0kg ✓',
  '첫 운동 했어요! 생각보다 할 만했어요': 'Did my first workout! It was easier than I thought',
  '첫 기록. 다음 주까지 주 3회 유지가 목표.':
      'First log. Goal is 3 times a week through next week.',
  '은채님, 첫 프로그램 완주 축하해요 🎉':
      'Eunchae, congrats on finishing your first program 🎉',
  '첫 운동 했어요!': 'Did my first workout!',
  '이번 주는 3번만 채워보죠. 무리 안 하는 게 더 중요해요 🙂':
      "Let's aim for just three this week. Not overdoing it matters more 🙂",
  '야식': 'Late-night snack',
  '스쿼트 4세트 · 10회 · 50kg': 'Squat · 4 sets · 10 reps · 50kg',
  '레그컬 3세트 · 12회 · 35kg': 'Leg curl · 3 sets · 12 reps · 35kg',
  '벤치프레스 4세트 · 8회 · 50kg': 'Bench press · 4 sets · 8 reps · 50kg',
  '푸시업 3세트 · 15회 · 0kg': 'Push-up · 3 sets · 15 reps · 0kg',
  '덤벨 플라이 3세트 · 12회 · 10kg': 'Dumbbell fly · 3 sets · 12 reps · 10kg',
  '데드리프트 4세트 · 8회 · 60kg': 'Deadlift · 4 sets · 8 reps · 60kg',
  '바벨 로우 3세트 · 10회 · 40kg': 'Barbell row · 3 sets · 10 reps · 40kg',
  '풀업 3세트 · 8회 · 0kg': 'Pull-up · 3 sets · 8 reps · 0kg',
  '숄더 프레스 4세트 · 10회 · 20kg': 'Shoulder press · 4 sets · 10 reps · 20kg',
  '사이드 레터럴 3세트 · 15회 · 6kg': 'Lateral raise · 3 sets · 15 reps · 6kg',
  '페이스 풀 3세트 · 15회 · 15kg': 'Face pull · 3 sets · 15 reps · 15kg',
  '런닝 30분': 'Running · 30 min',
  '사이클 20분': 'Cycling · 20 min',
  '코어 서킷 3세트 · 12회 · 0kg': 'Core circuit · 3 sets · 12 reps · 0kg',
  '레그프레스 4세트 · 12회 · 70kg': 'Leg press · 4 sets · 12 reps · 70kg',
  '힙 쓰러스트 3세트 · 12회 · 40kg': 'Hip thrust · 3 sets · 12 reps · 40kg',
  '카프 레이즈 3세트 · 20회 · 0kg': 'Calf raise · 3 sets · 20 reps · 0kg',
  '플랭크 3세트 · 3회 · 0kg': 'Plank · 3 sets · 3 reps · 0kg',
  '버피 3세트 · 12회 · 0kg': 'Burpee · 3 sets · 12 reps · 0kg',
  '마운틴 클라이머 3세트 · 20회 · 0kg': 'Mountain climber · 3 sets · 20 reps · 0kg',
  '출근 전 수업. 상체 위주로 짧게 끊어 간다.':
      'Session before work. Keep it short and upper-body focused.',
  '랫풀다운': 'Lat pulldown',
  '숄더프레스': 'Shoulder press',
  '식단 기록 습관 점검. 저녁 외식 빈도를 함께 본다.':
      'Review meal-logging habits. Look at how often they eat out for dinner.',
  '데드리프트 자세 교정 중. 허리 통증 여부를 매 세트 확인한다.':
      'Working on deadlift form. Check for back pain after every set.',
  '백익스텐션': 'Back extension',
  '유산소 비중을 늘리는 주. 심박 130 안쪽으로 유지한다.':
      'A cardio-heavy week. Keep heart rate under 130.',
  '어깨 가동 범위 회복 단계. 중량보다 자세를 본다.':
      'Recovering shoulder range of motion. Form over weight.',
  '밴드 외전': 'Band abduction',
  '인클라인 푸시업': 'Incline push-up',
  '하체 중량 구간. 무릎 각도 확인하며 스쿼트 깊이를 잡는다.':
      'Heavy lower-body block. Set squat depth while watching the knee angle.',
  '체지방 감량 목표. 근력과 유산소를 반씩 섞는다.':
      'Fat-loss goal. Split the session between strength and cardio.',
  '고블릿 스쿼트': 'Goblet squat',
  '로잉머신': 'Rowing machine',
  '수업 시간대 변경 상담. 오전 이동 가능 여부를 확인한다.':
      'Consultation on changing session times. Check whether mornings work.',
  '야간 수업. 다음 날 근육통을 고려해 볼륨을 낮게 잡는다.':
      'Late session. Keep volume low to limit next-day soreness.',
  '전신 순환. 세트 사이 휴식을 45초로 줄여 본다.':
      'Full-body circuit. Try cutting rest between sets to 45 seconds.',
  '케틀벨 스윙': 'Kettlebell swing',
  '재활 마무리 단계. 통증 없는 범위에서만 중량을 올린다.':
      'Final stage of rehab. Only add weight within a pain-free range.',
  '주 마지막 근력 수업. 상체 볼륨을 채운다.':
      'Last strength session of the week. Fill out the upper-body volume.',
  '신규 상담. 운동 경험과 무릎 부상 이력을 듣는다.':
      'New consultation. Ask about training experience and past knee injuries.',
  '주 2회 중 두 번째 수업. 월요일에 못 채운 하체를 넣는다.':
      'Second of two weekly sessions. Add the lower-body work missed on Monday.',
  '레그프레스': 'Leg press',
  '런지': 'Lunge',
  '컨디션에 따라 유산소로 대체할 수 있다.':
      'Can be swapped for cardio depending on how they feel.',
  '주말 수업. 평일보다 길게 가져가되 마무리 스트레칭을 넉넉히 둔다.':
      'Weekend session. Run longer than weekdays, with plenty of stretching at the end.',
  '체스트프레스': 'Chest press',
  '시티드로우': 'Seated row',
  '주말 보강 수업. 평일에 빠진 하체를 채운다.':
      'Weekend make-up session. Cover the lower-body work missed during the week.',
  '주말 상담. 헬스장 이용 시간대와 목표를 맞춰 본다.':
      'Weekend consultation. Match gym hours with their goals.',
  '가벼운 마무리 수업. 다음 주 계획을 함께 정한다.':
      'Light wrap-up session. Plan next week together.',
  '무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.':
      'Knee range of motion needs checking. Adjust weights next session.',
  '덤벨 숄더프레스': 'Dumbbell shoulder press',
  '플랭크 60초': 'Plank 60 sec',
  '데드리프트 자세 안정적. 다음 세션 60kg 도전.':
      'Deadlift form is solid. Try 60kg next session.',
  '루마니안 데드리프트': 'Romanian deadlift',
  '코어 서킷': 'Core circuit',
  '인클라인 덤벨 프레스': 'Incline dumbbell press',
  '트라이셉스 딥': 'Triceps dip',
  '오른쪽 어깨': 'Right shoulder',
  '야근이 많아서 저녁 운동을 못 갔어요. 벤치 할 때 어깨가 좀 걸리는 느낌이 있습니다.':
      'Lots of late nights, so I missed my evening workouts. My shoulder catches a bit on the bench.',
  '지난 주보다 컨디션은 나았는데 저녁 단백질은 계속 놓쳤어요.':
      'I felt better than last week, but I kept missing protein at dinner.',
  '스쿼트 무게 올린 게 오히려 재밌었어요.': 'Going heavier on squats was actually fun.',
  '출장이 겹쳐서 헬스장에 못 갔습니다. 다음 주부터 다시 갈게요.':
      "Back-to-back business trips kept me out of the gym. I'll be back next week.",
  '허리': 'Lower back',
  '데드리프트 하고 나서 허리가 계속 뻐근합니다.':
      'My lower back has been stiff ever since deadlifts.',
  '그릭 요거트': 'Greek yogurt',
  '견과류': 'Mixed nuts',
  '스크램블 에그': 'Scrambled eggs',
  '딸기': 'Strawberries',
  '야채비빔밥': 'Vegetable bibimbap',
  '짬뽕': 'Jjamppong',
  '연어구이': 'Grilled salmon',
  '아이스 아메리카노': 'Iced americano',
  '견과류 한 봉': 'A pack of nuts',
  '삼겹살 2인분': 'Pork belly for two',
  '소주 1병': '1 bottle of soju',
  '초코 케이크 한 조각': 'A slice of chocolate cake',
  '카페라떼': 'Caffè latte',
  '무릎이 좀 당겼지만 트레이너님 덕분에 잘 마쳤어요 😊':
      'My knee felt a bit tight, but thanks to you I finished strong 😊',
  '하체 스트레칭은 시간이 없어서 못 했어요': "I didn't have time for the lower-body stretch",
  '저강도 유산소 (걷기)': 'Low-intensity cardio (walking)',
  '코어 강화': 'Core strengthening',
  '어깨 관절 보호 스트레칭': 'Shoulder-joint care stretch',
  '하체 스트레칭': 'Lower-body stretch',
  '오늘은 다 했어요! 뿌듯해요 💪': 'Did it all today! Feeling proud 💪',
  '북한산 등산': 'Bukhansan hike',
  '레그프레스 무게가 붙었어요. 마지막 세트가 힘들었어요.':
      'My leg press weight went up. The last set was tough.',
  '하체 근력 향상 확인. 다음 세션 레그프레스 5kg 증량.':
      'Lower-body strength is improving. Add 5kg to leg press next session.',
  '레그컬': 'Leg curl',
  '카프레이즈': 'Calf raise',
  '마무리 러닝머신': 'Treadmill finisher',
  '탁구': 'Table tennis',
  '데드리프트 자세를 잡아주셔서 허리가 편했어요.':
      'Thanks for fixing my deadlift form. My back felt fine.',
  '데드리프트 힙힌지 안정적. 중량 55kg 유지 후 다음 달 60kg.':
      'Deadlift hip hinge is stable. Hold 55kg, then 60kg next month.',
  '허리 스트레칭': 'Lower-back stretch',
  '자전거 라이딩': 'Bike ride',
  '어깨가 아직 조금 불편해서 무게를 낮췄어요.':
      'My shoulder is still a little uncomfortable, so I went lighter.',
  '오른쪽 어깨 가동범위 제한. 숄더프레스 중량 낮추고 밴드 보강 병행.':
      'Limited right-shoulder range of motion. Lower shoulder press weight and add band work.',
  '벤치프레스가 처음이라 어색했지만 재밌었어요 💪':
      'Bench press was new and felt awkward, but it was fun 💪',
  '상체 근력 기초 확인. 벤치프레스 35kg 로 시작해 자세 우선.':
      'Checked baseline upper-body strength. Start bench at 35kg, form first.',
  '첫 PT 라 긴장했는데 생각보다 할 만했어요.':
      'I was nervous for my first PT, but it was easier than I thought.',
  '첫 세션. 체력 수준 점검 위주로 가볍게 진행.':
      'First session. Kept it light, mostly a fitness check.',
  '혈압 안정에 효과적': 'Helps keep blood pressure steady',
  '혈액순환 개선': 'Improves circulation',
  '기초대사량 향상': 'Boosts basal metabolism',
  'PT 피드백 반영 · 오른쪽 어깨 보호': 'Based on PT feedback · Protects the right shoulder',
};
