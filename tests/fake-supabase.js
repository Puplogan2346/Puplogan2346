// In-memory fake of the subset of supabase-js that store.js uses.
function makeFake() {
  const db = { profiles: [], lists: [], list_shares: [], tasks: [], templates: [], history: [] };
  let idc = 1; const nid = () => "id" + (idc++);
  const calls = [];

  function match(row, filters) {
    return filters.every(([op, col, val]) =>
      op === "eq" ? row[col] === val : op === "in" ? val.includes(row[col]) : true);
  }

  class Q {
    constructor(table) { this.t = table; this.filters = []; this.op = "select"; this.cols = "*"; this._single = false; this._order = null; }
    select(cols) { if (this.op === "select") {} this.cols = cols || "*"; this._returnSel = true; return this; }
    eq(c, v) { this.filters.push(["eq", c, v]); return this; }
    in(c, v) { this.filters.push(["in", c, v]); return this; }
    order(c, o) { this._order = { c, asc: !o || o.ascending !== false }; return this; }
    single() { this._single = true; return this; }
    insert(rows) { this.op = "insert"; this.payload = rows; return this; }
    update(row) { this.op = "update"; this.payload = row; return this; }
    delete() { this.op = "delete"; return this; }
    upsert(row, opts) { this.op = "upsert"; this.payload = row; this.onConflict = opts && opts.onConflict; return this; }
    then(res) { res(this._run()); }
    _run() {
      calls.push({ table: this.t, op: this.op, cols: this.cols, filters: this.filters, payload: this.payload });
      const tbl = db[this.t];
      try {
        if (this.op === "insert") {
          const rows = Array.isArray(this.payload) ? this.payload : [this.payload];
          const inserted = rows.map((r) => this._defaults({ id: nid(), ...r }));
          tbl.push(...inserted);
          const data = this._returnSel ? (this._single ? inserted[0] : inserted) : null;
          return { data, error: null };
        }
        if (this.op === "update") {
          const hit = tbl.filter((r) => match(r, this.filters));
          hit.forEach((r) => Object.assign(r, this.payload));
          return { data: hit, error: null };
        }
        if (this.op === "delete") {
          db[this.t] = tbl.filter((r) => !match(r, this.filters));
          return { data: null, error: null };
        }
        if (this.op === "upsert") {
          const keys = (this.onConflict || "").split(",").map((s) => s.trim());
          const row = this.payload;
          const existing = tbl.find((r) => keys.every((k) => r[k] === row[k]));
          if (existing) Object.assign(existing, row);
          else tbl.push(this._defaults({ id: nid(), ...row }));
          return { data: null, error: null };
        }
        // select
        let rows = tbl.filter((r) => match(r, this.filters));
        if (this._order) rows = rows.slice().sort((a, b) => (a[this._order.c] < b[this._order.c] ? -1 : 1) * (this._order.asc ? 1 : -1));
        rows = rows.map((r) => this._embed(r));
        return { data: this._single ? rows[0] || null : rows, error: null };
      } catch (e) { return { data: null, error: { message: e.message } }; }
    }
    _defaults(r) {
      if (this.t === "tasks") return { done: false, due: "", note: "", created_at: new Date().toISOString(), done_at: null, position: 0, ...r };
      if (this.t === "templates") return { due: "", position: 0, ...r };
      return r;
    }
    _embed(r) {
      if (this.t === "list_shares" && /lists\s*\(/.test(this.cols)) {
        const l = db.lists.find((x) => x.id === r.list_id);
        return { role: r.role, lists: l ? { id: l.id, name: l.name, owner: l.owner } : null };
      }
      if (this.t === "list_shares" && /profiles/.test(this.cols)) {
        const p = db.profiles.find((x) => x.id === r.shared_with);
        return { role: r.role, shared_with: r.shared_with, profiles: p ? { email: p.email, display_name: p.display_name } : null };
      }
      return r;
    }
  }

  const client = {
    _db: db, _calls: calls,
    from: (t) => new Q(t),
    rpc: (name, params) => {
      calls.push({ rpc: name, params });
      if (name === "share_list_by_email") {
        const p = db.profiles.find((x) => x.email.toLowerCase() === params.target_email.toLowerCase());
        if (!p) return Promise.resolve({ data: null, error: { message: "No account found for " + params.target_email } });
        const row = { list_id: params.target_list, shared_with: p.id, role: params.target_role || "editor" };
        db.list_shares.push(row);
        return Promise.resolve({ data: row, error: null });
      }
      if (name === "get_list_shares") {
        const rows = db.list_shares
          .filter((x) => x.list_id === params.target_list)
          .map((x) => {
            const p = db.profiles.find((profile) => profile.id === x.shared_with);
            return { shared_with: x.shared_with, role: x.role, email: p ? p.email : "", display_name: p ? p.display_name : "" };
          });
        return Promise.resolve({ data: rows, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    auth: {
      getSession: () => Promise.resolve({ data: { session: { user: { id: "u1", email: "me@test.dev" } } } }),
      onAuthStateChange: () => ({ data: { subscription: {} } }),
      signInWithPassword: () => Promise.resolve({ error: null }),
      signUp: () => Promise.resolve({ error: null }),
      signOut: () => Promise.resolve({ error: null }),
    },
    channel: () => { const ch = { on: () => ch, subscribe: () => ch }; return ch; },
    removeChannel: () => {},
  };
  // seed a second user to test sharing
  db.profiles.push({ id: "u1", email: "me@test.dev", display_name: "Me" });
  db.profiles.push({ id: "u2", email: "teammate@test.dev", display_name: "Teammate" });
  return client;
}
module.exports = { makeFake };
