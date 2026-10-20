import 'package:farmly_mobile/core/sync/farmly_task_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Farmly task occurrence schedule', () {
    test('uses the farm IANA timezone across a UTC date boundary', () {
      expect(
        farmlyTaskCivilDateAtUtc(
          DateTime.utc(2026, 10, 18, 17, 30),
          'Asia/Ho_Chi_Minh',
        ),
        '2026-10-19',
      );
    });

    test('formats a measurement instant in the farm IANA timezone', () {
      final farmTime = farmlyTaskDateTimeAtUtc(
        DateTime.utc(2026, 10, 18, 1, 2, 3),
        'Asia/Ho_Chi_Minh',
      );

      expect(farmTime.year, 2026);
      expect(farmTime.month, 10);
      expect(farmTime.day, 18);
      expect(farmTime.hour, 8);
      expect(farmTime.minute, 2);
      expect(farmTime.second, 3);
    });

    test('resolves farm civil time through a daylight-saving transition', () {
      expect(
        farmlyTaskCivilDateAtUtc(
          DateTime.utc(2026, 3, 8, 7, 30),
          'America/New_York',
        ),
        '2026-03-08',
      );
    });

    test(
      'matches daily and selected weekly dates inside the inclusive window',
      () {
        expect(
          farmlyTaskScheduleIncludesDate(
            frequency: 'daily',
            daysOfWeek: const [],
            startsOn: '2026-10-19',
            endsOn: '2026-10-21',
            occurrenceDate: '2026-10-21',
          ),
          isTrue,
        );
        expect(
          farmlyTaskScheduleIncludesDate(
            frequency: 'daily',
            daysOfWeek: const [],
            startsOn: '2026-10-19',
            endsOn: '2026-10-21',
            occurrenceDate: '2026-10-22',
          ),
          isFalse,
        );
        expect(
          farmlyTaskScheduleIncludesDate(
            frequency: 'weekly',
            daysOfWeek: const [1, 4],
            startsOn: '2026-10-19',
            endsOn: null,
            occurrenceDate: '2026-10-22',
          ),
          isTrue,
        );
        expect(
          farmlyTaskScheduleIncludesDate(
            frequency: 'weekly',
            daysOfWeek: const [1, 4],
            startsOn: '2026-10-19',
            endsOn: null,
            occurrenceDate: '2026-10-20',
          ),
          isFalse,
        );
        expect(
          farmlyTaskScheduleIncludesDate(
            frequency: 'weekly',
            daysOfWeek: const [],
            startsOn: '2026-10-19',
            endsOn: null,
            occurrenceDate: '2026-10-19',
          ),
          isFalse,
        );
      },
    );

    test('checks the inclusive template date window independently', () {
      expect(
        farmlyTaskDateWithinWindow(
          startsOn: '2026-10-19',
          endsOn: '2026-10-21',
          occurrenceDate: '2026-10-19',
        ),
        isTrue,
      );
      expect(
        farmlyTaskDateWithinWindow(
          startsOn: '2026-10-19',
          endsOn: '2026-10-21',
          occurrenceDate: '2026-10-21',
        ),
        isTrue,
      );
      expect(
        farmlyTaskDateWithinWindow(
          startsOn: '2026-10-19',
          endsOn: '2026-10-21',
          occurrenceDate: '2026-10-22',
        ),
        isFalse,
      );
      expect(
        farmlyTaskDateWithinWindow(
          startsOn: '2026-10-20',
          endsOn: null,
          occurrenceDate: '2026-10-19',
        ),
        isFalse,
      );
      expect(
        farmlyTaskDateWithinWindow(
          startsOn: '2026-02-30',
          endsOn: null,
          occurrenceDate: '2026-10-19',
        ),
        isFalse,
      );
    });

    test('matches the SQL deterministic ID vector for the default slot', () {
      expect(
        farmlyTaskOccurrenceResourceId(
          farmId: '00000000-0000-4000-8000-000000000100',
          templateId: '00000000-0000-4000-8000-000000000101',
          occurrenceDate: '2026-10-19',
          slot: ' default ',
        ),
        'd6b616b7-5153-57e6-87cc-2e379ee6a10b',
      );
    });
  });
}
