/*
 * History & streaks helpers. Pure functions over an array of
 * { day: "YYYY-MM-DD", completed, total } records.
 */
(function () {
  const WC = (window.WC = window.WC || {});

  function dateFromKey(key) {
    const [y, m, d] = key.split("-").map(Number);
    return new Date(y, m - 1, d);
  }
  function keyFromDate(d) { return d.toLocaleDateString("en-CA"); }

  // A day "counts" toward a streak if every task was completed (and there was
  // at least one task).
  function isPerfect(rec) { return rec.total > 0 && rec.completed >= rec.total; }

  function currentStreak(history) {
    const perfect = new Set(history.filter(isPerfect).map((h) => h.day));
    let streak = 0;
    const cursor = new Date();
    // Allow today to be "not done yet" without breaking the streak: if today
    // isn't perfect, start counting from yesterday.
    if (!perfect.has(keyFromDate(cursor))) cursor.setDate(cursor.getDate() - 1);
    while (perfect.has(keyFromDate(cursor))) {
      streak++;
      cursor.setDate(cursor.getDate() - 1);
    }
    return streak;
  }

  function stats(history) {
    const days = history.length;
    const totalCompleted = history.reduce((s, h) => s + h.completed, 0);
    const perfectDays = history.filter(isPerfect).length;
    const last7 = history.slice(-7);
    return {
      streak: currentStreak(history),
      perfectDays,
      daysTracked: days,
      totalCompleted,
      last7,
    };
  }

  WC.History = { currentStreak, stats, isPerfect, dateFromKey, keyFromDate };
})();
