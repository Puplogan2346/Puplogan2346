/*
 * Natural-language quick-add parser. Pure + unit-tested.
 * Turns what you type in the add box into { text, due, flagged }:
 *   "Email Bob 3pm"        -> { text: "Email Bob",  due: "15:00", flagged: false }
 *   "Standup 9:30 !"       -> { text: "Standup",    due: "09:30", flagged: true  }
 *   "Call vendor at 9"     -> { text: "Call vendor",due: "09:00", flagged: false }
 *   "Pay rent !!"          -> { text: "Pay rent",   due: "",      flagged: true  }
 *
 * Exposes window.WC.Quick.
 */
(function () {
  const WC = (window.WC = window.WC || {});
  const pad = (n) => String(n).padStart(2, "0");

  function parse(raw) {
    let text = String(raw || "").trim();
    let due = "", flagged = false;

    // Priority: one or more "!" as a standalone/trailing token flags the task.
    if (/(^|\s)!+(\s|$)/.test(text) || /!+$/.test(text)) flagged = true;
    text = text.replace(/(^|\s)!+(?=\s|$)/g, " ").trim();

    // 1) 12-hour clock: 3pm, 3:30pm, 12 am
    let m = text.match(/\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*([ap])\.?m\.?\b/i);
    if (m) {
      let h = parseInt(m[1], 10) % 12;
      if (/p/i.test(m[3])) h += 12;
      due = pad(h) + ":" + (m[2] || "00");
      text = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).trim();
    } else {
      // 2) 24-hour HH:MM, optionally after "at" or "@"
      m = text.match(/(?:\bat\s+|@\s*)?\b([01]?\d|2[0-3]):([0-5]\d)\b/);
      if (m) {
        due = pad(parseInt(m[1], 10)) + ":" + m[2];
        text = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).trim();
      } else {
        // 3) bare hour after "at": "at 9"
        m = text.match(/\bat\s+(1[0-2]|0?[1-9])\b/i);
        if (m) {
          due = pad(parseInt(m[1], 10)) + ":00";
          text = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).trim();
        }
      }
    }

    // Tidy leftover separators/whitespace.
    text = text.replace(/\s{2,}/g, " ").replace(/\s*[-@]\s*$/, "").trim();
    return { text, due, flagged };
  }

  WC.Quick = { parse };
})();
