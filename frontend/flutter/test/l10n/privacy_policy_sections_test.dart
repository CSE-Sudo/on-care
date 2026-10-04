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
final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

/// 절 번호 순서대로의 제목. 한국어가 원본이고 영문은 같은 번호를 쓴다.
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

const List<String> _enSections = <String>[
  '1. Personal information collected',
  '2. Purpose of collection and use',
  '3. Retention and use period',
  '4. Provision to third parties',
  '5. Sharing with your trainer and withdrawing consent',
  '6. Entrusted processing',
  '7. Transfer of personal information overseas',
  '8. Processing of sensitive (health) information',
  '9. Children under 14',
  '10. Destruction procedure and method',
  '11. Automatic collection tools',
  '12. Safeguards',
  '13. Rights of the user and how to exercise them',
  '14. Personal information protection officer',
  '15. Remedies for infringement',
  '16. Changes to this policy',
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

    test('영문본에 같은 절이 같은 순서로 있다', () {
      final String body = en.myLegalPrivacyBody(
        LegalContact.privacyOfficerEmail,
      );
      int last = -1;
      for (final String heading in _enSections) {
        final int at = body.indexOf('\n$heading\n');
        expect(at, greaterThan(last), reason: '$heading 이 없거나 순서가 다르다');
        last = at;
      }
    });
  });

  group('처리 위탁·국외 이전', () {
    test('두 언어 모두 실제 수탁자를 적는다', () {
      for (final String name in _processors) {
        expect(
          ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
          contains(name),
          reason: name,
        );
        expect(
          en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
          contains(name),
          reason: name,
        );
      }
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('주식회사 카카오'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Kakao Corp.'),
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
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Singapore'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('the United States'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Article 28-8'),
      );
    });

    test('기록을 저장할 때마다 색인용으로 전송된다는 사실을 숨기지 않는다', () {
      // 기본 설정(rag_auto_ingest)에서 식단·운동 저장은 곧 Gemini 임베딩 호출이다.
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('저장할 때마다'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Each time you save'),
      );
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
      final String e = en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      expect(e, contains('food photos'));
      expect(e, contains('attached photos'));
      expect(e, contains('IP address'));
      expect(e, contains('current location'));
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
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('one year'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('two years'),
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
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('report PDF files'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains("trainer's work record"),
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
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Position:'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Contact: ${LegalContact.privacyOfficerEmail}'),
      );
    });

    test('시행일이 자리표시자(2026년 1월 1일)가 아니고 두 언어가 같다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('시행일: 2026년 10월 5일'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Effective date: 5 October 2026'),
      );
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        isNot(contains('2026년 1월 1일')),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        isNot(contains('1 January 2026')),
      );
      expect(ko.myLegalPrivacyEffectiveDate, '시행일 2026. 10. 05.');
      expect(en.myLegalPrivacyEffectiveDate, 'Effective Oct 5, 2026');
    });

    test('개정 이력이 있다', () {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('2026년 10월 1일: 제정'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('1 October 2026: first issued'),
      );
    });

    test('보호책임자 연락처 변경이 개정 이력의 맨 위에 있다 (#3132)', () {
      final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      final String e = en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
      expect(k, contains('- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경'));
      expect(
        e,
        contains(
          '- 5 October 2026: changed the contact address of the personal '
          'information protection officer',
        ),
      );
      // 새 항목이 옛 항목보다 앞에 온다 — 개정 이력은 최신순이다.
      expect(k.indexOf('2026년 10월 5일:'), lessThan(k.indexOf('2026년 10월 3일:')));
      expect(
        e.indexOf('5 October 2026:'),
        lessThan(e.indexOf('3 October 2026:')),
      );
    });

    test('보호책임자 연락처가 팀 수신 주소로 채워진다 (#3132)', () {
      expect(LegalContact.privacyOfficerEmail, 'sudo.capstone@gmail.com');
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('연락처: sudo.capstone@gmail.com'),
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains('Contact: sudo.capstone@gmail.com'),
      );
      for (final String body in <String>[
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      ]) {
        expect(body, isNot(contains('{contact}')));
        expect(body, isNot(contains('@oncare.com')));
      }
    });

    test('약관의 시행일도 자리표시자가 아니다 — 처리방침과 따로 간다', () {
      expect(ko.myLegalTermsBody, contains('2026년 10월 3일부터 시행'));
      expect(ko.myLegalTermsEffectiveDate, '시행일 2026. 10. 03.');
      expect(en.myLegalTermsEffectiveDate, 'Effective Oct 3, 2026');
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
          ('en', const Locale('en'), en),
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
        final List<String> sections = tag == 'ko' ? _koSections : _enSections;
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
