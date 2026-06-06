/*
 * Headless tests for the data layer (assets/store.js + assets/history.js).
 * Runs in plain Node by stubbing the few browser globals the store touches.
 * Covers BOTH backends: local (localStorage) and cloud (mock Supabase).
 *
 *   node tests/run.js
 */
const fs = require("fs");
const path = require("path");
const { makeFake } = require("./fake-supabase.js");

const ASSETS = path.join(__dirname, "..", "assets");

let failures = 0;
function assert(cond, msg) {
  if (!cond) { failures++; console.error("  ✗ " + msg); }
  else console.log("  ✓ " + msg);
}

// Build a fresh, isolated module environment for each backend.
function bootstrap({ cloud }) {
  const ls = {};
  const win = {
    WC_CONFIG: cloud ? { supabaseUrl: "x", supabaseAnonKey: "y" } : { supabaseUrl: "", supabaseAnonKey: "" },
  };
  const fake = cloud ? makeFake() : null;
  if (cloud) win.supabase = { createClient: () => fake };
  const sandbox = {
    window: win,
    localStorage: {
      getItem: (k) => (k in ls ? ls[k] : null),
      setItem: (k, v) => { ls[k] = String(v); },
      removeItem: (k) => { delete ls[k]; },
    },
    Date,
    console,
  };
  const load = (f) => {
    const code = fs.readFileSync(path.join(ASSETS, f), "utf8");
    // Expose the stubbed globals to the asset's IIFE.
    new Function("window", "localStorage", "Date", "console", code)
      .call(sandbox, win, sandbox.localStorage, Date, console);
  };
  load("supabase.js");
  load("store.js");
  load("history.js");
  load("import.js");
  load("quickadd.js");
  return { WC: win.WC, fake };
}

function testQuickAdd() {
  console.log("\nQuick-add parser:");
  const { WC } = bootstrap({ cloud: false });
  const Q = WC.Quick;
  let r = Q.parse("Email Bob 3pm");
  assert(r.text === "Email Bob" && r.due === "15:00" && !r.flagged, "12h '3pm' -> 15:00");
  r = Q.parse("Standup 9:30 !");
  assert(r.text === "Standup" && r.due === "09:30" && r.flagged, "24h time + '!' flag");
  r = Q.parse("Call vendor at 9");
  assert(r.text === "Call vendor" && r.due === "09:00", "'at 9' -> 09:00");
  r = Q.parse("Lunch 12pm");
  assert(r.due === "12:00", "noon '12pm' -> 12:00");
  r = Q.parse("Pay rent !!");
  assert(r.text === "Pay rent" && r.due === "" && r.flagged, "flag with no time");
  r = Q.parse("Review 1-on-1 notes");
  assert(r.text === "Review 1-on-1 notes" && r.due === "", "leaves non-time text alone");
}

async function testRecurringTemplates() {
  console.log("\nRecurring templates:");
  const { WC } = bootstrap({ cloud: false });
  const S = WC.Store; S.onChange = () => {};
  await S.init();
  await S.addTemplate("Daily review", "17:00");          // every day
  await S.addTemplate("Monday plan", "", [1]);            // Mondays only
  assert(S.templates.length === 2, "adds templates with day rules");
  assert(S.templatesForDay(1).length === 2, "Monday includes both");
  assert(S.templatesForDay(3).length === 1 && S.templatesForDay(3)[0].text === "Daily review", "Wednesday excludes Monday-only");
  const mon = S.templates.find((t) => t.text === "Monday plan");
  await S.updateTemplate(mon.id, { days: [2, 4] });
  assert(S.templatesForDay(1).length === 1, "editing days reschedules off Monday");
  assert(S.templatesForDay(2).length === 2, "now included on Tuesday");
}

function testImport() {
  console.log("\nUniversal import parsers:");
  const { WC } = bootstrap({ cloud: false });
  const I = WC.Import;

  const txt = I.parseText("Email inbox\n- Standup 09:30\n* Review @ 5:00\n\n[ ] Plan day");
  assert(txt.length === 4, "parses one task per non-empty line");
  assert(txt[0].text === "Email inbox" && txt[0].due === "", "plain line, no time");
  assert(txt[1].text === "Standup" && txt[1].due === "09:30", "strips bullet + trailing time");
  assert(txt[2].text === "Review" && txt[2].due === "05:00", "handles '@ H:MM' and pads hour");
  assert(txt[3].text === "Plan day", "strips a checkbox marker");

  const ics = I.parseICS(
    "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Team sync\r\nDTSTART;TZID=America/New_York:20240115T143000\r\nEND:VEVENT\r\n" +
    "BEGIN:VEVENT\r\nSUMMARY:All-day off-site\r\nDTSTART;VALUE=DATE:20240116\r\nEND:VEVENT\r\nEND:VCALENDAR"
  );
  assert(ics.length === 2, "parses each VEVENT");
  assert(ics[0].text === "Team sync" && ics[0].due === "14:30", "event summary + local start time -> due");
  assert(ics[1].text === "All-day off-site" && ics[1].due === "", "all-day event has no due time");

  const csv = I.parseCSV('Task,Due\n"Pay invoice, urgent",09:00\nCall vendor,\n');
  assert(csv.length === 2, "parses CSV rows with header");
  assert(csv[0].text === "Pay invoice, urgent" && csv[0].due === "09:00", "respects quoted comma + due column");
  assert(csv[1].text === "Call vendor" && csv[1].due === "", "missing due is empty");

  const f = I.fromFile("backup.json", '{"tasks":[{"text":"x"}]}');
  assert(f.json && f.data.tasks.length === 1, "routes .json to backup data");
  assert(I.fromFile("list.csv", "Buy milk,08:00").items[0].due === "08:00", "routes .csv to CSV parser");
  assert(I.fromFile("notes.txt", "Just a line").items[0].text === "Just a line", "routes other text to line parser");

  // Google API transforms
  const cal = I.gcalToItems({ items: [
    { summary: "Sync", status: "confirmed", start: { dateTime: "2024-01-15T14:30:00Z" } },
    { summary: "Off-site", start: { date: "2024-01-16" } },
    { summary: "Canceled", status: "cancelled", start: { dateTime: "2024-01-15T10:00:00Z" } },
  ] });
  assert(cal.length === 2, "gcal: skips cancelled events");
  assert(cal[0].text === "Sync" && /^\d{2}:\d{2}$/.test(cal[0].due), "gcal: timed event yields a due time");
  assert(cal[1].text === "Off-site" && cal[1].due === "", "gcal: all-day event has no due");

  const gt = I.gtasksToItems({ items: [
    { title: "Buy milk", status: "needsAction" },
    { title: "Done thing", status: "completed" },
    { title: "  ", status: "needsAction" },
  ] });
  assert(gt.length === 1 && gt[0].text === "Buy milk", "gtasks: only active, titled tasks");

  const push = I.itemsToGtasks([{ text: "Task A", note: "hi" }, { text: "Task B" }]);
  assert(push[0].title === "Task A" && push[0].notes === "hi", "itemsToGtasks maps title + notes");
  assert(push[1].title === "Task B" && !("notes" in push[1]), "itemsToGtasks omits empty notes");
}

async function testLocal() {
  console.log("\nLocal mode:");
  const { WC } = bootstrap({ cloud: false });
  const S = WC.Store; S.onChange = () => {};
  await S.init();
  assert(S.mode === "local", "runs in local mode");
  await S.addTask("A", "09:30");
  await S.addTask("B", "");
  await S.addTask("C", "");
  assert(S.tasks.length === 3, "adds tasks");
  assert(S.tasks[0].due === "09:30", "stores due time");
  await S.updateTask(S.tasks[0].id, { done: true });
  assert(S.tasks[0].done && S.tasks[0].doneAt, "toggles done with timestamp");
  const ids = S.tasks.map((t) => t.id);
  await S.reorder([ids[2], ids[0], ids[1]]);
  assert(S.tasks[0].text === "C", "reorders tasks");
  await S.addTemplate("Review", "17:00");
  await S.applyTemplate();
  assert(S.tasks.some((t) => t.text === "Review" && t.due === "17:00"), "applies template");
  for (const t of S.tasks) await S.updateTask(t.id, { done: true });
  await S.recordToday();
  const st = WC.History.stats(S.history);
  assert(st.streak === 1 && st.perfectDays === 1, "records a perfect-day streak");
  const n = S.tasks.length;
  await S.removeTask(S.tasks[0].id);
  assert(S.tasks.length === n - 1, "removes a task");
  S.enterLocal();
  assert(S.tasks.length === n - 1, "persists across reload");
}

async function testCloud() {
  console.log("\nCloud mode (mock Supabase):");
  const { WC, fake } = bootstrap({ cloud: true });
  const S = WC.Store; S.onChange = () => {};
  await S.init();
  assert(S.mode === "cloud", "runs in cloud mode");
  assert(S.lists.length === 1 && S.currentList.role === "owner", "creates a default list");
  const listId = S.currentListId;
  await S.addTask("Email", "09:30");
  await S.addTask("Standup", "");
  assert(S.tasks.length === 2, "adds tasks");
  assert(fake._db.tasks.every((t) => t.list_id === listId), "scopes tasks to the list");
  await S.updateTask(S.tasks[0].id, { done: true });
  const dbT = fake._db.tasks.find((t) => t.text === "Email");
  assert(dbT.done && dbT.done_at, "persists done_at to the database");
  assert(S.tasks[0].doneAt, "maps done timestamp back to memory");
  const ids = S.tasks.map((t) => t.id);
  await S.reorder([ids[1], ids[0]]);
  assert(fake._db.tasks.find((t) => t.text === "Standup").position === 0, "persists reorder positions");
  await S.addTemplate("Daily review", "17:00");
  await S.applyTemplate();
  assert(S.tasks.some((t) => t.text === "Daily review"), "applies template");
  await S.recordToday(); await S.recordToday();
  assert(fake._db.history.length === 1, "upserts history (no duplicate days)");
  await S.createList("Personal");
  assert(S.lists.length === 2 && S.currentList.name === "Personal", "creates & selects a new list");
  assert(S.tasks.length === 0, "new list starts empty");
  await S.selectList(listId);
  const share = await S.shareList("teammate@test.dev", "editor");
  assert(share && share.shared_with === "u2", "shares a list by email");
  const shares = await S.getShares();
  assert(shares.length === 1 && shares[0].email === "teammate@test.dev", "lists current shares");
  let threw = false;
  try { await S.shareList("nobody@nope.dev", "editor"); } catch (e) { threw = true; }
  assert(threw, "rejects sharing to an unknown email");
  await S.deleteList(S.lists.find((l) => l.name === "Personal").id);
  assert(!S.lists.some((l) => l.name === "Personal"), "deletes a list");
}

(async () => {
  await testLocal();
  await testCloud();
  testImport();
  testQuickAdd();
  await testRecurringTemplates();
  console.log("");
  if (failures) { console.error(failures + " assertion(s) failed."); process.exit(1); }
  console.log("All tests passed.");
})().catch((e) => { console.error("Test run crashed:", e); process.exit(1); });
