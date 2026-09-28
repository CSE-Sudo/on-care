/// 전송 완료 목록의 순서. (#2447)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';

import '../../helpers/client_factory.dart';

final DateTime _monday = DateTime(2026, 9, 21);

ReportQueueEntry _entry(String id, String name) => ReportQueueEntry(
  client: makeClient(id: id, name: name),
  report: null,
  sent: true,
);

ReportSendRecord _record(String id, {required bool read}) => ReportSendRecord(
  clientId: id,
  weekStart: _monday,
  sentAt: _monday.add(const Duration(hours: 9)),
  message: '',
  read: read,
);

List<String> _ids(List<ReportQueueEntry> entries) => <String>[
  for (final ReportQueueEntry e in entries) e.client.id,
];

void main() {
  final List<ReportQueueEntry> done = <ReportQueueEntry>[
    _entry('a', '나회원'),
    _entry('b', '가회원'),
    _entry('c', '다회원'),
    _entry('d', '라회원'),
  ];
  final Map<String, ReportSendRecord> records = <String, ReportSendRecord>{
    'a': _record('a', read: true),
    'b': _record('b', read: true),
    'c': _record('c', read: false),
    'd': _record('d', read: false),
  };

  test('기본값은 안 읽은 회원 먼저다', () {
    expect(ReportSentSort.values.first, ReportSentSort.unreadFirst);
  });

  test('안 읽은 회원이 위로, 같은 무리 안에서는 이름순', () {
    final List<ReportQueueEntry> sorted = sortSentEntries(
      done,
      records: records,
      sort: ReportSentSort.unreadFirst,
    );
    expect(_ids(sorted), <String>['c', 'd', 'b', 'a']);
  });

  test('이름 오름차순', () {
    expect(
      _ids(sortSentEntries(done, records: records, sort: ReportSentSort.name)),
      <String>['b', 'a', 'c', 'd'],
    );
  });

  test('이름 내림차순', () {
    expect(
      _ids(
        sortSentEntries(
          done,
          records: records,
          sort: ReportSentSort.nameDescending,
        ),
      ),
      <String>['d', 'c', 'a', 'b'],
    );
  });

  test('전송 기록이 없는 줄은 안 읽은 줄로 단정하지 않는다', () {
    final List<ReportQueueEntry> sorted = sortSentEntries(
      <ReportQueueEntry>[_entry('x', '가나중'), _entry('c', '다회원')],
      records: records,
      sort: ReportSentSort.unreadFirst,
    );
    expect(_ids(sorted), <String>['c', 'x']);
  });

  test('모두 읽었으면 이름순과 같다', () {
    final Map<String, ReportSendRecord> allRead = <String, ReportSendRecord>{
      for (final ReportQueueEntry e in done)
        e.client.id: _record(e.client.id, read: true),
    };
    expect(
      _ids(
        sortSentEntries(
          done,
          records: allRead,
          sort: ReportSentSort.unreadFirst,
        ),
      ),
      _ids(sortSentEntries(done, records: allRead, sort: ReportSentSort.name)),
    );
  });

  test('입력 목록을 바꾸지 않는다', () {
    final List<String> before = _ids(done);
    sortSentEntries(done, records: records, sort: ReportSentSort.name);
    expect(_ids(done), before);
  });

  test('빈 목록은 빈 목록', () {
    expect(
      sortSentEntries(
        const <ReportQueueEntry>[],
        records: records,
        sort: ReportSentSort.unreadFirst,
      ),
      isEmpty,
    );
  });
}
