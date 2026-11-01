/// Commission periods.
///
/// Before [weeklyStart] commission is recorded per MONTH (key "2026-10").
/// From [weeklyStart] on it is recorded per WEEK, Monday to Sunday, and the
/// key is the Monday of that week (key "2026-11-02"). A week ends on Sunday
/// at 11:59 PM, so anything unpaid is overdue from Monday 12:00 AM.
class CommissionPeriod {
  /// First Monday that uses weekly records. Change this date to switch earlier.
  static final DateTime weeklyStart = DateTime(2026, 11, 2);

  static String _two(int n) => n.toString().padLeft(2, '0');

  static DateTime _weekStart(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// The period key a date belongs to.
  static String keyFor(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (day.isBefore(weeklyStart)) return '${day.year}-${_two(day.month)}';
    final s = _weekStart(day);
    return '${s.year}-${_two(s.month)}-${_two(s.day)}';
  }

  static String currentKey() => keyFor(DateTime.now());

  static bool isWeekly(String key) => key.length == 10;

  /// "week" or "month"
  static String name(String key) => isWeekly(key) ? 'week' : 'month';

  /// First moment AFTER the period ends.
  static DateTime _endExclusive(String key) {
    if (isWeekly(key)) {
      final s = DateTime.parse(key);
      return DateTime(s.year, s.month, s.day + 7);
    }
    final y = int.parse(key.substring(0, 4));
    final m = int.parse(key.substring(5, 7));
    return DateTime(y, m + 1, 1);
  }

  /// True once the period has ended (so an unpaid balance is overdue).
  static bool isOverdueKey(String key) {
    try {
      return !DateTime.now().isBefore(_endExclusive(key));
    } catch (_) {
      return false;
    }
  }

  /// Days left in the current period after today (0 = today is the last day).
  static int daysLeft() {
    final key = currentKey();
    final lastDay = _endExclusive(key).subtract(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return lastDay.difference(today).inDays;
  }

  /// Last couple of days of the period (the "Pay Commission" stretch).
  static bool isEndOfPeriod() => daysLeft() <= (isWeekly(currentKey()) ? 1 : 2);

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Friendly label: "Nov 2 - Nov 8, 2026" for a week, the key itself for a month.
  static String label(String key) {
    if (!isWeekly(key)) return key;
    final s = DateTime.parse(key);
    final e = DateTime(s.year, s.month, s.day + 6);
    return '${_months[s.month - 1]} ${s.day} - ${_months[e.month - 1]} ${e.day}, ${e.year}';
  }
}