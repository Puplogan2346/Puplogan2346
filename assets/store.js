/*
 * Data layer. One uniform API the UI calls; two backends behind it:
 *   - local  : everything in localStorage, no account (offline / try-it-out).
 *   - cloud  : Supabase (accounts, cross-device sync, sharing, realtime).
 *
 * The UI never talks to localStorage or Supabase directly — only through here.
 * After any change, Store.onChange() fires so the UI can re-render.
 */
(function () {
  const WC = (window.WC = window.WC || {});
  const sb = WC.sb;

  const LK = {
    tasks: "wc_local_tasks",
    templates: "wc_local_templates",
    history: "wc_local_history",
    lastDay: "wc_local_lastday",
    filter: "wc_local_filter",
  };

  function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 6); }
  function todayKey() { return new Date().toLocaleDateString("en-CA"); } // YYYY-MM-DD
  function loadJSON(key, fallback) {
    try { const r = localStorage.getItem(key); if (r) return JSON.parse(r); } catch (e) {}
    return fallback;
  }

  const Store = {
    mode: "local",
    user: null,
    lists: [],
    currentListId: null,
    tasks: [],
    templates: [],
    history: [],          // [{ day, completed, total }]
    onChange: function () {},
    onAuthChange: function () {},
    onRecovery: function () {},   // fires when arriving from a password-reset link
    onSync: function () {},       // fires with "syncing" | "synced" | "remote"
    remoteUpdate: false,          // set when the last onChange came from realtime
    providerToken: null,          // Google OAuth access token (set right after sign-in)
    googleScopes: "https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/tasks",

    get cloud() { return this.mode === "cloud"; },
    get canEdit() {
      if (!this.cloud) return true;
      const l = this.lists.find((x) => x.id === this.currentListId);
      return !l || l.role !== "viewer";
    },
    get currentList() { return this.lists.find((x) => x.id === this.currentListId) || null; },

    // ---- filter persists locally regardless of mode (it's a view preference) ----
    getFilter() { return localStorage.getItem(LK.filter) || "all"; },
    setFilter(f) { localStorage.setItem(LK.filter, f); },

    // ===================================================================
    // Init
    // ===================================================================
    async init() {
      if (WC.cloudEnabled && sb) {
        const { data } = await sb.auth.getSession();
        if (data && data.session) {
          this.providerToken = data.session.provider_token || null;
          await this.enterCloud(data.session.user);
        } else {
          this.enterLocal();
        }
        // React to login / logout.
        sb.auth.onAuthStateChange(async (_event, session) => {
          if (session && session.provider_token) this.providerToken = session.provider_token;
          if (_event === "PASSWORD_RECOVERY") { this.onRecovery(); return; }
          if (session && session.user) {
            if (this.mode !== "cloud" || (this.user && this.user.id !== session.user.id)) {
              await this.enterCloud(session.user);
              this.onAuthChange();
            }
          } else if (this.mode === "cloud") {
            this.enterLocal();
            this.onAuthChange();
          }
        });
      } else {
        this.enterLocal();
      }
    },

    enterLocal() {
      this.mode = "local";
      this.user = null;
      this.lists = [];
      this.currentListId = null;
      this.tasks = loadJSON(LK.tasks, []);
      this.templates = loadJSON(LK.templates, []);
      this.history = loadJSON(LK.history, []);
      this.onChange();
    },

    async enterCloud(user) {
      this.mode = "cloud";
      const meta = user.user_metadata || {};
      this.user = {
        id: user.id,
        email: user.email,
        name: meta.display_name || meta.full_name || meta.name || user.email,
        avatar: meta.avatar_url || meta.picture || "",
      };
      await this.loadLists();
      await this.reload();
      this.subscribeRealtime();
    },

    // ===================================================================
    // Auth (cloud only)
    // ===================================================================
    async signIn(email, password) {
      const { error } = await sb.auth.signInWithPassword({ email, password });
      if (error) throw error;
    },
    async signUp(email, password, displayName) {
      const { error } = await sb.auth.signUp({
        email, password, options: { data: { display_name: displayName || email } },
      });
      if (error) throw error;
    },
    async signInWithGoogle() {
      const redirectTo = window.location.href.split("#")[0];
      const { error } = await sb.auth.signInWithOAuth({ provider: "google", options: { redirectTo } });
      if (error) throw error;
    },

    // ---- Google data: connect (with API scopes), read, and push ----
    hasGoogleToken() { return !!this.providerToken; },
    async connectGoogle(intent) {
      // Stash what to do after the OAuth round-trip, then redirect to Google.
      if (intent) localStorage.setItem("wc_google_intent", intent);
      const redirectTo = window.location.href.split("#")[0];
      const { error } = await sb.auth.signInWithOAuth({
        provider: "google",
        options: { scopes: this.googleScopes, redirectTo, queryParams: { access_type: "offline", prompt: "consent" } },
      });
      if (error) throw error;
    },
    consumeGoogleIntent() {
      const i = localStorage.getItem("wc_google_intent");
      if (i) localStorage.removeItem("wc_google_intent");
      return i;
    },
    async googleFetch(url, opts) {
      if (!this.providerToken) throw new Error("Not connected to Google.");
      const res = await fetch(url, Object.assign(
        { headers: { Authorization: "Bearer " + this.providerToken, "Content-Type": "application/json" } },
        opts || {}
      ));
      if (res.status === 401 || res.status === 403) { this.providerToken = null; throw new Error("Google session expired — please connect again."); }
      if (!res.ok) throw new Error("Google API error (" + res.status + ")");
      return res.status === 204 ? null : res.json();
    },
    async fetchGoogleCalendarToday() {
      const now = new Date();
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
      const end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).toISOString();
      const url = "https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime" +
        "&timeMin=" + encodeURIComponent(start) + "&timeMax=" + encodeURIComponent(end);
      return WC.Import.gcalToItems(await this.googleFetch(url));
    },
    async _defaultTaskListId() {
      const lists = await this.googleFetch("https://tasks.googleapis.com/tasks/v1/users/@me/lists");
      return lists && lists.items && lists.items[0] ? lists.items[0].id : "@default";
    },
    async fetchGoogleTasks() {
      const listId = await this._defaultTaskListId();
      const data = await this.googleFetch(
        "https://tasks.googleapis.com/tasks/v1/lists/" + encodeURIComponent(listId) + "/tasks?showCompleted=false&maxResults=100"
      );
      return WC.Import.gtasksToItems(data);
    },
    async pushToGoogleTasks(tasks) {
      const listId = await this._defaultTaskListId();
      let n = 0;
      for (const body of WC.Import.itemsToGtasks(tasks)) {
        await this.googleFetch(
          "https://tasks.googleapis.com/tasks/v1/lists/" + encodeURIComponent(listId) + "/tasks",
          { method: "POST", body: JSON.stringify(body) }
        );
        n++;
      }
      return n;
    },
    async signOut() { if (sb) await sb.auth.signOut(); },
    async resetPassword(email) {
      const redirectTo = window.location.href.split("#")[0];
      const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo });
      if (error) throw error;
    },
    async updatePassword(password) {
      const { error } = await sb.auth.updateUser({ password });
      if (error) throw error;
    },

    // ===================================================================
    // Lists (cloud only; local mode has a single implicit list)
    // ===================================================================
    async loadLists() {
      // Owned lists.
      const owned = await sb.from("lists").select("id,name,owner").eq("owner", this.user.id);
      // Lists shared with me.
      const shared = await sb
        .from("list_shares")
        .select("role, lists ( id, name, owner )")
        .eq("shared_with", this.user.id);

      let lists = (owned.data || []).map((l) => ({ ...l, role: "owner" }));
      (shared.data || []).forEach((s) => {
        if (s.lists) lists.push({ id: s.lists.id, name: s.lists.name, owner: s.lists.owner, role: s.role });
      });

      // First run: create a default list.
      if (lists.length === 0) {
        const { data } = await sb.from("lists").insert({ owner: this.user.id, name: "My Day" }).select().single();
        if (data) lists = [{ ...data, role: "owner" }];
      }

      this.lists = lists;
      const saved = localStorage.getItem("wc_cloud_list_" + this.user.id);
      this.currentListId = lists.some((l) => l.id === saved) ? saved : lists[0].id;
    },

    async selectList(id) {
      this.currentListId = id;
      if (this.user) localStorage.setItem("wc_cloud_list_" + this.user.id, id);
      this.unsubscribeRealtime();
      await this.reload();
      this.subscribeRealtime();
      this.onChange();
    },

    async createList(name) {
      const { data, error } = await sb.from("lists").insert({ owner: this.user.id, name: name || "New list" }).select().single();
      if (error) throw error;
      this.lists.push({ ...data, role: "owner" });
      await this.selectList(data.id);
    },

    async renameList(id, name) {
      await sb.from("lists").update({ name }).eq("id", id);
      const l = this.lists.find((x) => x.id === id); if (l) l.name = name;
      this.onChange();
    },

    async deleteList(id) {
      await sb.from("lists").delete().eq("id", id);
      this.lists = this.lists.filter((l) => l.id !== id);
      if (this.currentListId === id && this.lists[0]) await this.selectList(this.lists[0].id);
      else this.onChange();
    },

    async shareList(email, role) {
      const { data, error } = await sb.rpc("share_list_by_email", {
        target_list: this.currentListId, target_email: email, target_role: role || "editor",
      });
      if (error) throw error;
      return data;
    },

    async getShares() {
      const { data } = await sb
        .from("list_shares")
        .select("role, shared_with, profiles:shared_with ( email, display_name )")
        .eq("list_id", this.currentListId);
      return (data || []).map((s) => ({
        userId: s.shared_with, role: s.role,
        email: s.profiles ? s.profiles.email : "", name: s.profiles ? s.profiles.display_name : "",
      }));
    },

    async unshare(userId) {
      await sb.from("list_shares").delete().eq("list_id", this.currentListId).eq("shared_with", userId);
    },

    // ===================================================================
    // Load tasks/templates/history for the current scope
    // ===================================================================
    async reload() {
      if (!this.cloud) {
        this.tasks = loadJSON(LK.tasks, []);
        this.templates = loadJSON(LK.templates, []);
        this.history = loadJSON(LK.history, []);
        return;
      }
      const [t, tpl, h] = await Promise.all([
        sb.from("tasks").select("*").eq("list_id", this.currentListId).order("position", { ascending: true }),
        sb.from("templates").select("*").eq("list_id", this.currentListId).order("position", { ascending: true }),
        sb.from("history").select("day,completed,total").eq("list_id", this.currentListId).order("day", { ascending: true }),
      ]);
      this.tasks = (t.data || []).map(normalizeTask);
      this.templates = (tpl.data || []).map((r) => ({ id: r.id, text: r.text, due: r.due || "" }));
      this.history = (h.data || []).map((r) => ({ day: r.day, completed: r.completed, total: r.total }));
    },

    // ===================================================================
    // Task mutations
    // ===================================================================
    async addTask(text, due) {
      const trimmed = (text || "").trim();
      if (!trimmed) return;
      if (this.cloud) {
        const position = nextPosition(this.tasks);
        await this._sync((async () => {
          await sb.from("tasks").insert({ list_id: this.currentListId, text: trimmed, due: due || "", position });
          await this.reload();
        })());
      } else {
        this.tasks.push({ id: uid(), text: trimmed, done: false, createdAt: Date.now(), due: due || "", note: "" });
        this.persistLocal();
      }
      this.onChange();
    },

    async addTasksBulk(items) {
      // items: [{ text, due }]
      if (this.cloud) {
        let position = nextPosition(this.tasks);
        const rows = items.map((it) => ({ list_id: this.currentListId, text: it.text.trim(), due: it.due || "", position: position++ }));
        if (rows.length) await sb.from("tasks").insert(rows);
        await this.reload();
      } else {
        for (const it of items) this.tasks.push({ id: uid(), text: it.text.trim(), done: false, createdAt: Date.now(), due: it.due || "", note: "" });
        this.persistLocal();
      }
      this.onChange();
    },

    async updateTask(id, patch) {
      const t = this.tasks.find((x) => x.id === id); if (!t) return;
      Object.assign(t, patch);
      if ("done" in patch) t.doneAt = patch.done ? Date.now() : null;
      if (this.cloud) {
        const row = {};
        if ("text" in patch) row.text = patch.text;
        if ("due" in patch) row.due = patch.due;
        if ("note" in patch) row.note = patch.note;
        if ("done" in patch) { row.done = patch.done; row.done_at = patch.done ? new Date().toISOString() : null; }
        await this._sync(sb.from("tasks").update(row).eq("id", id));
      } else {
        this.persistLocal();
      }
      this.onChange();
    },

    async removeTask(id) {
      this.tasks = this.tasks.filter((x) => x.id !== id);
      if (this.cloud) await this._sync(sb.from("tasks").delete().eq("id", id));
      else this.persistLocal();
      this.onChange();
    },

    async removeTasks(ids) {
      const set = new Set(ids);
      this.tasks = this.tasks.filter((x) => !set.has(x.id));
      if (this.cloud) await this._sync(sb.from("tasks").delete().in("id", ids));
      else this.persistLocal();
      this.onChange();
    },

    async replaceTasks(tasks) {
      // Local-mode undo: restore an exact snapshot.
      this.tasks = tasks;
      if (!this.cloud) this.persistLocal();
      this.onChange();
    },

    async restoreTasks(taskObjs) {
      // Cloud-mode undo of deletes: re-insert the removed task rows.
      if (this.cloud) {
        let position = nextPosition(this.tasks);
        const rows = taskObjs.map((t) => ({
          list_id: this.currentListId, text: t.text, done: !!t.done,
          due: t.due || "", note: t.note || "", position: position++,
          done_at: t.done ? new Date(t.doneAt || Date.now()).toISOString() : null,
        }));
        if (rows.length) await sb.from("tasks").insert(rows);
        await this.reload();
      } else {
        this.tasks = this.tasks.concat(taskObjs);
        this.persistLocal();
      }
      this.onChange();
    },

    async importData(data) {
      const tasks = Array.isArray(data.tasks) ? data.tasks : [];
      const templates = Array.isArray(data.templates) ? data.templates : [];
      if (this.cloud) {
        if (tasks.length) {
          let p = nextPosition(this.tasks);
          await sb.from("tasks").insert(tasks.map((t) => ({
            list_id: this.currentListId, text: t.text || "(untitled)", done: !!t.done,
            due: t.due || "", note: t.note || "", position: p++,
            done_at: t.done ? new Date(t.doneAt || Date.now()).toISOString() : null,
          })));
        }
        if (templates.length) {
          let p = nextPosition(this.templates);
          await sb.from("templates").insert(templates.map((t) => ({
            list_id: this.currentListId, text: t.text || "(untitled)", due: t.due || "", position: p++,
          })));
        }
        await this.reload();
      } else {
        this.tasks = tasks;
        this.templates = templates;
        this.persistLocal();
      }
      this.onChange();
    },

    async reorder(orderedIds) {
      const byId = new Map(this.tasks.map((t) => [t.id, t]));
      this.tasks = orderedIds.map((id) => byId.get(id)).filter(Boolean);
      if (this.cloud) {
        await this._sync(Promise.all(this.tasks.map((t, i) => sb.from("tasks").update({ position: i }).eq("id", t.id))));
      } else {
        this.persistLocal();
      }
      this.onChange();
    },

    // ===================================================================
    // Templates
    // ===================================================================
    async addTemplate(text, due) {
      const trimmed = (text || "").trim(); if (!trimmed) return;
      if (this.cloud) {
        await sb.from("templates").insert({ list_id: this.currentListId, text: trimmed, due: due || "", position: nextPosition(this.templates) });
        await this.reload();
      } else {
        this.templates.push({ id: uid(), text: trimmed, due: due || "" });
        this.persistLocal();
      }
      this.onChange();
    },

    async removeTemplate(id) {
      this.templates = this.templates.filter((x) => x.id !== id);
      if (this.cloud) await sb.from("templates").delete().eq("id", id);
      else this.persistLocal();
      this.onChange();
    },

    async setTemplatesFromTasks() {
      const items = this.tasks.map((t, i) => ({ text: t.text, due: t.due || "", position: i }));
      if (this.cloud) {
        await sb.from("templates").delete().eq("list_id", this.currentListId);
        if (items.length) await sb.from("templates").insert(items.map((it) => ({ list_id: this.currentListId, ...it })));
        await this.reload();
      } else {
        this.templates = items.map((it) => ({ id: uid(), text: it.text, due: it.due }));
        this.persistLocal();
      }
      this.onChange();
    },

    async applyTemplate() {
      await this.addTasksBulk(this.templates.map((t) => ({ text: t.text, due: t.due || "" })));
    },

    // ===================================================================
    // History & streaks
    // ===================================================================
    async recordToday() {
      const day = todayKey();
      const completed = this.tasks.filter((t) => t.done).length;
      const total = this.tasks.length;
      if (total === 0) return;
      const existing = this.history.find((h) => h.day === day);
      if (existing) { existing.completed = completed; existing.total = total; }
      else this.history.push({ day, completed, total });
      this.history.sort((a, b) => (a.day < b.day ? -1 : 1));
      if (this.cloud) {
        await sb.from("history").upsert(
          { list_id: this.currentListId, day, completed, total, updated_at: new Date().toISOString() },
          { onConflict: "list_id,day" }
        );
      } else {
        localStorage.setItem(LK.history, JSON.stringify(this.history));
      }
    },

    // ===================================================================
    // New-day handling (carry over + template prompt eligibility)
    // ===================================================================
    isNewDay() {
      const key = this.cloud ? "wc_cloud_lastday_" + this.user.id : LK.lastDay;
      const last = localStorage.getItem(key);
      return { last, today: todayKey(), changed: last !== todayKey() };
    },
    markDaySeen() {
      const key = this.cloud ? "wc_cloud_lastday_" + this.user.id : LK.lastDay;
      localStorage.setItem(key, todayKey());
    },

    // ===================================================================
    // Realtime (cloud only)
    // ===================================================================
    _channel: null,
    subscribeRealtime() {
      if (!this.cloud || !sb) return;
      this.unsubscribeRealtime();
      this._channel = sb
        .channel("list-" + this.currentListId)
        .on("postgres_changes", { event: "*", schema: "public", table: "tasks", filter: "list_id=eq." + this.currentListId }, async () => {
          await this.reload(); this.remoteUpdate = true; this.onChange(); this.remoteUpdate = false; this.onSync("remote");
        })
        .on("postgres_changes", { event: "*", schema: "public", table: "templates", filter: "list_id=eq." + this.currentListId }, async () => {
          await this.reload(); this.remoteUpdate = true; this.onChange(); this.remoteUpdate = false; this.onSync("remote");
        })
        .subscribe();
    },
    unsubscribeRealtime() {
      if (this._channel && sb) { sb.removeChannel(this._channel); this._channel = null; }
    },

    // ---- sync indicator: track in-flight cloud writes ----
    _pending: 0,
    async _sync(p) {
      if (!this.cloud) return p;
      this._pending++;
      this.onSync("syncing");
      try { return await p; }
      finally { if (--this._pending === 0) this.onSync("synced"); }
    },

    // ---- local persistence ----
    persistLocal() {
      localStorage.setItem(LK.tasks, JSON.stringify(this.tasks));
      localStorage.setItem(LK.templates, JSON.stringify(this.templates));
    },
  };

  function normalizeTask(r) {
    return {
      id: r.id, text: r.text, done: !!r.done, due: r.due || "", note: r.note || "",
      createdAt: r.created_at ? new Date(r.created_at).getTime() : Date.now(),
      doneAt: r.done_at ? new Date(r.done_at).getTime() : null,
    };
  }
  function nextPosition(arr) {
    return arr.length ? arr.length : 0;
  }

  WC.Store = Store;
  WC.uid = uid;
  WC.todayKey = todayKey;
})();
