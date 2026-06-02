/*
 * Universal import helpers. Pure functions (no DOM) so they can be unit-tested.
 * Turns pasted text, a calendar (.ics), or a spreadsheet (.csv) into a list of
 * { text, due } task items. JSON backups are handled separately (Store.importData).
 *
 * Exposes window.WC.Import.
 */
(function () {
  const WC = (window.WC = window.WC || {});

  function normalizeTime(s) {
    if (!s) return "";
    const m = String(s).trim().match(/^([0-2]?\d):([0-5]\d)/);
    if (!m) return "";
    const h = parseInt(m[1], 10), mm = m[2];
    if (h > 23) return "";
    return String(h).padStart(2, "0") + ":" + mm;
  }

  // ---- Plain text: one task per line, with an optional trailing time ----
  function parseText(text) {
    const items = [];
    for (let raw of String(text || "").split(/\r?\n/)) {
      const line = raw.trim();
      if (!line) continue;
      let txt = line, due = "";
      // Trailing time like "Standup 09:30", "Standup @ 9:30", "Standup - 09:30".
      const m = line.match(/\s*[@-]?\s*([0-2]?\d:[0-5]\d)\s*$/);
      if (m) {
        const t = normalizeTime(m[1]);
        if (t) { due = t; txt = line.slice(0, m.index).trim(); }
      }
      // Strip a leading "- ", "* ", "• " or checkbox marker.
      txt = txt.replace(/^([-*•]|\[[ xX]?\])\s+/, "").trim();
      if (txt) items.push({ text: txt, due });
    }
    return items;
  }

  // ---- iCalendar (.ics): each VEVENT -> a task ----
  function unescapeICS(s) {
    return String(s).replace(/\\n/gi, " ").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\").trim();
  }
  function icsTimeToDue(value) {
    // value like 20240115T143000Z, 20240115T143000, or 20240115 (date only)
    const m = String(value).match(/(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?/);
    if (!m || !m[4]) return ""; // date-only or unparseable -> no time
    const [, y, mo, d, hh, mi, ss, z] = m;
    if (z) {
      const dt = new Date(Date.UTC(+y, +mo - 1, +d, +hh, +mi, +(ss || 0)));
      return normalizeTime(dt.getHours() + ":" + String(dt.getMinutes()).padStart(2, "0"));
    }
    return normalizeTime(hh + ":" + mi);
  }
  function parseICS(text) {
    // Unfold folded lines (RFC 5545: CRLF followed by space/tab).
    const unfolded = String(text || "").replace(/\r?\n[ \t]/g, "");
    const items = [];
    let cur = null;
    for (const line of unfolded.split(/\r?\n/)) {
      if (/^BEGIN:VEVENT/i.test(line)) { cur = { text: "", due: "" }; continue; }
      if (/^END:VEVENT/i.test(line)) { if (cur && cur.text) items.push(cur); cur = null; continue; }
      if (!cur) continue;
      const idx = line.indexOf(":");
      if (idx < 0) continue;
      const key = line.slice(0, idx).toUpperCase();
      const val = line.slice(idx + 1);
      if (key === "SUMMARY" || key.startsWith("SUMMARY;")) cur.text = unescapeICS(val);
      else if (key === "DTSTART" || key.startsWith("DTSTART;")) cur.due = icsTimeToDue(val);
    }
    return items;
  }

  // ---- CSV: a column for the task text, optional column for a time ----
  function parseCSVRows(text) {
    const rows = [];
    let row = [], field = "", inQuotes = false;
    const s = String(text || "");
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (inQuotes) {
        if (c === '"') { if (s[i + 1] === '"') { field += '"'; i++; } else inQuotes = false; }
        else field += c;
      } else if (c === '"') inQuotes = true;
      else if (c === ",") { row.push(field); field = ""; }
      else if (c === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
      else if (c === "\r") { /* skip */ }
      else field += c;
    }
    if (field.length || row.length) { row.push(field); rows.push(row); }
    return rows.filter((r) => r.some((c) => c.trim() !== ""));
  }
  function parseCSV(text) {
    const rows = parseCSVRows(text);
    if (!rows.length) return [];
    let textIdx = 0, dueIdx = -1, start = 0;
    const header = rows[0].map((h) => h.trim().toLowerCase());
    const looksLikeHeader = header.some((h) => /task|title|name|todo|item|due|time|when/.test(h));
    if (looksLikeHeader) {
      start = 1;
      const ti = header.findIndex((h) => /task|title|name|todo|item/.test(h));
      const di = header.findIndex((h) => /due|time|when/.test(h));
      if (ti >= 0) textIdx = ti;
      if (di >= 0) dueIdx = di;
    } else if (rows[0].length > 1 && normalizeTime(rows[0][1])) {
      dueIdx = 1; // second column looks like a time
    }
    const items = [];
    for (let i = start; i < rows.length; i++) {
      const r = rows[i];
      const txt = (r[textIdx] || "").trim();
      if (!txt) continue;
      const due = dueIdx >= 0 ? normalizeTime(r[dueIdx]) : "";
      items.push({ text: txt, due });
    }
    return items;
  }

  // ---- Google API JSON -> task items (pure transforms) ----
  function gcalToItems(data) {
    const out = [];
    for (const ev of (data && data.items) || []) {
      if (ev.status === "cancelled") continue;
      const text = (ev.summary || "(no title)").trim();
      let due = "";
      if (ev.start && ev.start.dateTime) {
        const d = new Date(ev.start.dateTime);
        if (!isNaN(d.getTime())) due = normalizeTime(d.getHours() + ":" + String(d.getMinutes()).padStart(2, "0"));
      }
      out.push({ text, due });
    }
    return out;
  }
  function gtasksToItems(data) {
    const out = [];
    for (const t of (data && data.items) || []) {
      if (t.status === "completed") continue;
      const text = (t.title || "").trim();
      if (text) out.push({ text, due: "" });
    }
    return out;
  }
  function itemsToGtasks(tasks) {
    return (tasks || []).map((t) => {
      const body = { title: (t.text || "(untitled)").trim() || "(untitled)" };
      if (t.note) body.notes = t.note;
      return body;
    });
  }

  // ---- Dispatch by file name / content ----
  function fromFile(name, content) {
    const ext = (name.split(".").pop() || "").toLowerCase();
    if (ext === "json") return { json: true, data: JSON.parse(content) };
    if (ext === "ics" || /BEGIN:VCALENDAR/i.test(content)) return { items: parseICS(content) };
    if (ext === "csv") return { items: parseCSV(content) };
    return { items: parseText(content) };
  }

  WC.Import = {
    parseText, parseICS, parseCSV, parseCSVRows, fromFile, normalizeTime,
    gcalToItems, gtasksToItems, itemsToGtasks,
  };
})();
