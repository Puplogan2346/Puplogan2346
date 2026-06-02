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
  return { WC: win.WC, fake };
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
  console.log("");
  if (failures) { console.error(failures + " assertion(s) failed."); process.exit(1); }
  console.log("All tests passed.");
})().catch((e) => { console.error("Test run crashed:", e); process.exit(1); });
