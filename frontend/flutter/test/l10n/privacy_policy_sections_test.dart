/// 회원 앱 개인정보 처리방침의 법정 기재 절이 빠지지 않는지. (#2820)
///
/// 처리방침은 수집 항목·목적·보유 기간·제3자 제공·트레이너 공유만 담고 있었다.
/// 실제로는 음식 사진·대화가 Google Gemini 로, 기록 전체가 싱가포르의 AWS·Neon 으로
/// 가는데 그 위탁·국외 이전이 고지되지 않았고, 파기 절차·보호책임자·시행일도 자리를
/// 채우는 수준이었다. 원본 표는 `docs/privacy_processing.md` 다.
///
/// 문장을 통째로 비교하지 않는다 — 문안은 법률 검토를 거치며 다듬어진다. 절 제목,
/// 실제 수탁자·국가, 실제 보관 기간과 탈퇴 동작처럼 **빠지면 안 되는 사실**만 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/legal_contact.dart';

final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

/// 절 번호 순서대로의 제목.
const List<String> _koSections = <String>[
  '1. 수집하는 개인정보 항목',
  '2. 개인정보의 수집 및 이용 목적',
  '3. 개인정보의 보유 및 이용 기간',
  '4. 개인정보의 제3자 제공',
  '5. 담당 트레이너와의 정보 공유 및 동의 철회',
  '6. 개인정보 처리의 위탁',
  '7. 개인정보의 국외 이전',
  '8. 민감정보(건강정보)의 처리',
  '9. 만 14세 미만 아동의 개인정보',
  '10. 개인정보의 파기 절차 및 방법',
  '11. 개인정보 자동 수집 장치의 설치·운영 및 거부',
  '12. 개인정보의 안전성 확보 조치',
  '13. 이용자의 권리와 행사 방법',
  '14. 개인정보 보호책임자',
  '15. 권익침해 구제 방법',
  '16. 처리방침의 변경',
];

/// 실제로 쓰는 수탁자 — `docs/privacy_processing.md` 1절과 같다.
const List<String> _processors = <String>[
  'Amazon Web Services, Inc.',
  'Neon',
  'Google LLC',
  'Functional Software, Inc.',
];

void main() {
  group('절 제목', () {
    test('한국어본에 필수 절이 순서대로 모두 있다', () {
      final String body = ko.myLegalPrivacyBody(
        LegalContact.privacyOfficerEmail,
      );
      int last = -1;
      for (final String heading in _koSections) {
        final int at = body.indexOf('\n$heading\n');
        expect(at, greaterThan(last), reason: '$heading 이 없거나 순서가 다르다');
        last = at;
      }
    });
  });

  group('처리 위탁·국외 이전', () {
    test('실제 수탁자를 적는다', () {
      for (final String name in _processors) {
        expect(
          ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
          contains(name),
          reason: name,
        );
      }
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('주식회사 카카오'),
      );
    });

    test('이전 국가와 근거 조항을 적는다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('싱가포르'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('미국'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('제28조의8'),
      );
    });

    test('기록을 저장할 때마다 색인용으로 전송된다는 사실을 숨기지 않는다', () {
      // 기본 설정(rag_auto_ingest)에서 식단·운동 저장은 곧 Gemini 임베딩 호출이다.
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('저장할 때마다'),
      );
    });

    test('메일 발송(Gmail)을 위탁과 국외 이전에 함께 적는다 (#3443)', () {
      // 운영 메일은 Gmail SMTP 로 나간다(#480). 가입 인증 코드·비밀번호 재설정·
      // 로그인 이메일 변경 안내가 모두 같은 경로다.
      final String body = ko.myLegalPrivacyBody(
        LegalContact.privacyOfficerEmail,
      );
      expect(
        body,
        contains(
          '- Google LLC: 가입 인증 코드, 비밀번호 재설정, 로그인 이메일 변경 인증·안내 메일 발송(Gmail)',
        ),
      );
      expect(
        body,
        contains('⑤ Google LLC(Gmail) / 미국 등 Google이 운영하는 데이터센터 소재 국가 / '),
      );
      expect(body, contains('그 메일을 보내기 위해 ⑤로 전송됩니다'));
    });
  });

  group('수집 항목이 실제와 맞다', () {
    test('음식 사진·채팅 사진·접속 기록·위치를 적는다', () {
      final String body = ko.myLegalPrivacyBody(
        LegalContact.privacyOfficerEmail,
      );
      expect(body, contains('음식 사진'));
      expect(body, contains('첨부 사진'));
      expect(body, contains('IP 주소'));
      expect(body, contains('현재 위치'));
    });
  });

  group('소셜 로그인 수단 (#3217·#3499)', () {
    // 네이버 로그인은 제공하지 않는다(#3217). 애플은 한때 뺐다가 iOS 앱 심사
    // (App Review Guideline 4.8)를 위해 다시 넣었다(#3499). 처리방침이 쓰지 않는
    // 수집 경로를 적거나, 쓰는 경로를 빠뜨리면 사실과 다른 고지가 된다.
    test('수집 항목에 카카오·구글·애플을 적고, 애플 전달용 주소를 알린다', () {
      final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      expect(k, contains('소셜 로그인(카카오·구글·애플)으로 가입하면'));
      expect(k, contains('Apple이 만든 전달용 이메일 주소를 받습니다'));
    });

    test('탈퇴할 때 애플 로그인 연결 해제를 요청한다고 적는다', () {
      final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      final String destroy = k.split('\n10. ')[1].split('\n11. ')[0];
      expect(destroy, contains('Apple에 로그인 연결 해제(토큰 철회)도 요청'));
    });

    test('애플 추가가 맨 위 개정 이력이고, 옛 제외 기록도 남는다', () {
      final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      expect(
        k,
        contains(
          '- 2026년 10월 27일: 소셜 로그인 수단에 애플 추가(1항 ①), '
          '탈퇴할 때 애플 로그인 연결 해제 추가(10항 ①)',
        ),
      );
      expect(k, contains('소셜 로그인 수단에서 네이버·애플 제외'));
      expect(ko.myLegalPrivacyEffectiveDate, '시행일 2026. 10. 27.');
    });

    test('네이버는 제외를 알리는 개정 이력에만 남는다', () {
      final List<String> lines = ko
          .myLegalPrivacyBody(LegalContact.privacyOfficerEmail)
          .split('\n')
          .where((String line) => line.contains('네이버'))
          .toList();
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('- 2026년 10월 5일: '));
    });

    test('이용약관에는 소셜 로그인 수단으로 네이버·애플이 없다', () {
      expect(ko.myLegalTermsBody, isNot(contains('애플')));
      expect(ko.myLegalTermsBody, isNot(contains('네이버')));
    });
  });

  group('보관 기간과 파기', () {
    test('감사 기록 보관 기간(1년·2년)이 서버 설정과 같다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('접속 기록: 1년'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('탈퇴 기록: 2년'),
      );
    });

    test('탈퇴하면 첨부 파일까지 지운다는 것과 남는 것을 함께 적는다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('리포트 PDF 파일 포함'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('트레이너의 업무 기록으로 남습니다'),
      );
    });
  });

  group('보호책임자·시행일', () {
    test('보호책임자는 직책과 연락처로 적는다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('직책:'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('연락처: ${LegalContact.privacyOfficerEmail}'),
      );
    });

    test('시행일이 자리표시자(2026년 1월 1일)가 아니다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('시행일: 2026년 10월 27일'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        isNot(contains('2026년 1월 1일')),
      );
      expect(ko.myLegalPrivacyEffectiveDate, '시행일 2026. 10. 27.');
    });

    test('개정 이력이 있다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('2026년 10월 1일: 제정'),
      );
    });

    test('개정 이력은 최신순이고 맨 위가 애플 로그인 추가다 (#3132·#3443·#3499)', () {
      final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      expect(k, contains('- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경'));
      // 새 항목이 옛 항목보다 앞에 온다 — 개정 이력은 최신순이다.
      expect(k.indexOf('2026년 10월 27일:'), lessThan(k.indexOf('2026년 10월 14일:')));
      expect(k.indexOf('2026년 10월 14일:'), lessThan(k.indexOf('2026년 10월 5일:')));
      expect(k.indexOf('2026년 10월 5일:'), lessThan(k.indexOf('2026년 10월 3일:')));
    });

    test('보호책임자 연락처가 팀 수신 주소로 채워진다 (#3132)', () {
      expect(LegalContact.privacyOfficerEmail, 'sudo.capstone@gmail.com');
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('연락처: sudo.capstone@gmail.com'),
      );
      final String body = ko.myLegalPrivacyBody(
        LegalContact.privacyOfficerEmail,
      );
      expect(body, isNot(contains('{contact}')));
      expect(body, isNot(contains('@oncare.com')));
    });

    test('약관의 시행일도 자리표시자가 아니다 — 처리방침과 따로 간다', () {
      expect(ko.myLegalTermsBody, contains('2026년 10월 3일부터 시행'));
      expect(ko.myLegalTermsEffectiveDate, '시행일 2026. 10. 03.');
    });
  });

  group('처리방침 화면', () {
    Widget app(Locale locale, String document) => ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://dev.api.test',
            useMockApi: true,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LegalDocumentPage(document: document),
      ),
    );

    for (final (String tag, Locale locale, AppLocalizations l)
        in <(String, Locale, AppLocalizations)>[
          ('ko', const Locale('ko'), ko),
        ]) {
      testWidgets('[$tag] 위탁·국외 이전·파기·보호책임자 절과 처리방침 시행일이 보인다', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(locale, 'privacy'));
        await tester.pumpAndSettle();

        final String shown = tester
            .widget<Text>(
              find.text(l.myLegalPrivacyBody(LegalContact.privacyOfficerEmail)),
            )
            .data!;
        const List<String> sections = _koSections;
        for (final int i in <int>[5, 6, 9, 13]) {
          expect(shown, contains(sections[i]));
        }
        // 시행일은 긴 본문 아래에 있다 — 끝까지 내려 본다.
        await tester.scrollUntilVisible(
          find.text(l.myLegalPrivacyEffectiveDate),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(l.myLegalPrivacyEffectiveDate), findsOneWidget);
        expect(find.text(l.myLegalTermsBody), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] 처리방침 화면이 연락처 자리에 팀 수신 주소를 채운다 (#3132)', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(locale, 'privacy'));
        await tester.pumpAndSettle();

        final String shown = tester
            .widget<Text>(
              find.text(l.myLegalPrivacyBody(LegalContact.privacyOfficerEmail)),
            )
            .data!;
        expect(shown, contains('sudo.capstone@gmail.com'));
        expect(shown, isNot(contains('{contact}')));
        expect(shown, isNot(contains('@oncare.com')));
      });

      testWidgets('[$tag] 약관 화면은 약관 시행일을 단다', (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(locale, 'terms'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text(l.myLegalTermsEffectiveDate),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(l.myLegalTermsEffectiveDate), findsOneWidget);
        // 날짜만으로 문서를 가리지 않는다 — 본문으로 약관 화면임을 본다.
        expect(find.text(l.myLegalTermsBody), findsOneWidget);
        expect(
          find.text(l.myLegalPrivacyBody(LegalContact.privacyOfficerEmail)),
          findsNothing,
        );
      });
    }
  });
}
