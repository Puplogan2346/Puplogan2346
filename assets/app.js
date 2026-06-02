/*
 * UI controller. Reads from WC.Store, calls Store mutations, re-renders on
 * Store.onChange. Works the same in local and cloud mode.
 */
(function () {
  const WC = window.WC;
  const Store = WC.Store;
  const Auth = WC.Auth;
  const History = WC.History;
  const esc = WC.escapeHtml;

  function q(id) { return document.getElementById(id); }
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  let filter = Store.getFilter();
  let dragId = null;
  let wasAllDone = false;
  const notified = new Set();
  let recordTimer = null;

  const el = {};

  // =====================================================================
  // Init
  // =====================================================================
  async function init() {
    [
      "date", "count", "pct", "bar", "barFill", "streak", "addForm", "taskInput", "timeInput",
      "list", "filters", "clearDone", "resetDay", "openTemplates", "enableReminders",
      "exportBtn", "importBtn", "importFile", "installBtn", "themeToggle",
      "listSwitch", "listSelect", "newListBtn", "shareBtn", "historyBtn",
      "toast", "toastMsg", "toastUndo", "appName",
      "templateBanner", "bannerText", "bannerApply", "bannerDismiss",
    ].forEach((id) => (el[id] = q(id)));

    applyTheme(localStorage.getItem("wc_theme") || (window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"));

    if (window.WC_CONFIG && window.WC_CONFIG.appName) el.appName.textContent = window.WC_CONFIG.appName;

    Store.onChange = render;
    Store.onAuthChange = () => { notified.clear(); render(); Auth.render(); checkNewDay(); };

    bindEvents();
    Auth.init();
    await Store.init();
    render();
    checkNewDay();
    el.taskInput.focus();

    // Reminders
    if ("Notification" in window && Notification.permission === "granted") {
      el.enableReminders.classList.add("active");
      el.enableReminders.textContent = "🔔 Reminders on";
    }
    checkReminders();
    setInterval(checkReminders, 30000);
  }

  // =====================================================================
  // Rendering
  // =====================================================================
  function render() {
    el.date.textContent = new Date().toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });

    // List switcher (cloud only)
    if (Store.cloud && Store.lists.length) {
      el.listSwitch.classList.remove("hidden");
      el.listSelect.innerHTML = "";
      for (const l of Store.lists) {
        const opt = document.createElement("option");
        opt.value = l.id;
        opt.textContent = l.name + (l.role !== "owner" ? " (shared)" : "");
        if (l.id === Store.currentListId) opt.selected = true;
        el.listSelect.appendChild(opt);
      }
      const owner = Store.currentList && Store.currentList.role === "owner";
      el.shareBtn.style.display = owner ? "" : "none";
    } else {
      el.listSwitch.classList.add("hidden");
    }

    const tasks = Store.tasks;
    const total = tasks.length;
    const done = tasks.filter((t) => t.done).length;
    const pct = total ? Math.round((done / total) * 100) : 0;
    const allDone = total > 0 && done === total;

    el.count.textContent = allDone ? "All done — nice work! 🎉" : `${done} of ${total} done`;
    el.pct.textContent = `${pct}%`;
    el.barFill.style.width = pct + "%";
    el.bar.classList.toggle("complete", allDone);
    el.clearDone.disabled = done === 0;
    el.resetDay.disabled = total === 0;

    // Streak line
    const s = History.stats(Store.history || []);
    el.streak.innerHTML =
      `🔥 <strong>${s.streak}</strong>-day streak` +
      ` · <strong>${s.perfectDays}</strong> perfect day${s.perfectDays === 1 ? "" : "s"}` +
      ` · <strong>${s.totalCompleted}</strong> tasks done all-time`;

    if (allDone && !wasAllDone && !reducedMotion) confetti();
    wasAllDone = allDone;

    // List
    const visible = tasks.filter((t) => (filter === "active" ? !t.done : filter === "done" ? t.done : true));
    el.list.innerHTML = "";
    if (visible.length === 0) {
      const empty = document.createElement("div");
      empty.className = "empty";
      if (total === 0) empty.innerHTML = '<span class="big">📝</span>No tasks yet — add one above, or apply your <strong>⭐ template</strong>.';
      else if (filter === "active") empty.innerHTML = '<span class="big">✅</span>Nothing active. Everything is checked off!';
      else empty.innerHTML = '<span class="big">🗂️</span>Nothing here for this filter yet.';
      el.list.appendChild(empty);
    } else {
      for (const t of visible) el.list.appendChild(taskNode(t));
    }

    scheduleRecord();
  }

  function taskNode(t) {
    const editable = Store.canEdit;
    const li = document.createElement("li");
    li.className = "task" + (t.done ? " done" : "") + (isOverdue(t) ? " overdue" : "");
    li.dataset.id = t.id;
    li.draggable = editable;

    const main = document.createElement("div");
    main.className = "task-main";

    const handle = document.createElement("span");
    handle.className = "handle"; handle.textContent = "⋮⋮"; handle.setAttribute("aria-hidden", "true");

    const idx = Store.tasks.findIndex((x) => x.id === t.id);
    const reorder = document.createElement("div");
    reorder.className = "reorder";
    const up = mkBtn("▲", "Move up", () => moveBy(t.id, -1)); up.disabled = idx <= 0 || !editable;
    const down = mkBtn("▼", "Move down", () => moveBy(t.id, 1)); down.disabled = idx >= Store.tasks.length - 1 || !editable;
    up.className = "icon-btn"; down.className = "icon-btn";
    reorder.append(up, down);

    const check = document.createElement("button");
    check.className = "check";
    check.setAttribute("aria-label", (t.done ? "Mark not done: " : "Mark done: ") + t.text);
    check.setAttribute("aria-pressed", String(t.done));
    check.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#04121f" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    check.disabled = !editable;
    check.addEventListener("click", () => Store.updateTask(t.id, { done: !t.done }));

    const body = document.createElement("div");
    body.className = "body";

    const label = document.createElement("span");
    label.className = "label"; label.textContent = t.text; label.title = editable ? "Double-click to edit" : "";
    if (editable) {
      label.addEventListener("dblclick", () => { label.setAttribute("contenteditable", "true"); label.focus(); document.getSelection().selectAllChildren(label); });
      label.addEventListener("blur", () => { label.removeAttribute("contenteditable"); const v = label.textContent.trim(); if (v && v !== t.text) Store.updateTask(t.id, { text: v }); else label.textContent = t.text; });
      label.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); label.blur(); } if (e.key === "Escape") { label.textContent = t.text; label.blur(); } });
    }

    const meta = document.createElement("div");
    meta.className = "meta-line";
    if (t.due) {
      const d = document.createElement("span"); d.className = "due-badge";
      d.textContent = (isOverdue(t) ? "⚠️ Due " : "⏰ ") + fmtDue(t.due);
      meta.appendChild(d);
    }
    const added = document.createElement("span"); added.className = "added-time";
    added.textContent = t.done && t.doneAt ? "✓ done " + fmtTime(t.doneAt) : "added " + fmtTime(t.createdAt);
    meta.appendChild(added);
    if (t.note) { const np = document.createElement("span"); np.className = "note-preview"; np.textContent = "🗒 " + t.note.split("\n")[0]; meta.appendChild(np); }
    body.append(label, meta);

    const actions = document.createElement("div");
    actions.className = "actions";
    const dueBtn = mkBtn("⏰", "Set due time"); if (t.due) dueBtn.classList.add("active");
    const noteBtn = mkBtn("🗒", "Add a note"); if (t.note) noteBtn.classList.add("active");
    const del = mkBtn("×", "Delete task", () => deleteTask(t)); del.classList.add("del");
    dueBtn.disabled = noteBtn.disabled = del.disabled = !editable;
    actions.append(dueBtn, noteBtn, del);

    main.append(handle, reorder, check, body, actions);

    // extras
    const extras = document.createElement("div");
    extras.className = "extras";
    const dueRow = document.createElement("div"); dueRow.className = "extras-row";
    const dueLabel = document.createElement("label"); dueLabel.textContent = "Due time:";
    const dueInput = document.createElement("input"); dueInput.type = "time"; dueInput.value = t.due || "";
    dueInput.addEventListener("change", () => { notified.delete(t.id); Store.updateTask(t.id, { due: dueInput.value }); });
    const clearDue = document.createElement("button"); clearDue.className = "btn-clear-due"; clearDue.textContent = "Clear";
    clearDue.addEventListener("click", () => { notified.delete(t.id); Store.updateTask(t.id, { due: "" }); });
    dueRow.append(dueLabel, dueInput, clearDue);
    const note = document.createElement("textarea"); note.placeholder = "Notes…"; note.value = t.note || "";
    let noteTimer = null;
    note.addEventListener("input", () => { clearTimeout(noteTimer); noteTimer = setTimeout(() => Store.updateTask(t.id, { note: note.value }), 500); });
    note.addEventListener("blur", () => { clearTimeout(noteTimer); Store.updateTask(t.id, { note: note.value }); });
    extras.append(dueRow, note);
    dueBtn.addEventListener("click", () => { extras.classList.toggle("open"); dueInput.focus(); });
    noteBtn.addEventListener("click", () => { extras.classList.toggle("open"); note.focus(); });

    if (editable) {
      li.addEventListener("dragstart", () => { dragId = t.id; li.classList.add("dragging"); });
      li.addEventListener("dragend", () => { dragId = null; li.classList.remove("dragging"); });
      li.addEventListener("dragover", (e) => { e.preventDefault(); if (dragId && dragId !== t.id) li.classList.add("drag-over"); });
      li.addEventListener("dragleave", () => li.classList.remove("drag-over"));
      li.addEventListener("drop", (e) => { e.preventDefault(); li.classList.remove("drag-over"); if (dragId) dropReorder(dragId, t.id); });
    }

    li.append(main, extras);
    return li;
  }

  function mkBtn(text, label, onClick) {
    const b = document.createElement("button");
    b.className = "icon-btn"; b.textContent = text; b.title = label; b.setAttribute("aria-label", label);
    if (onClick) b.addEventListener("click", onClick);
    return b;
  }

  // =====================================================================
  // Task helpers
  // =====================================================================
  function snapshot() { return JSON.parse(JSON.stringify(Store.tasks)); }
  function undoRemoval(prev, removed) {
    if (Store.cloud) Store.restoreTasks(removed);
    else Store.replaceTasks(prev);
  }
  function deleteTask(t) {
    const prev = snapshot();
    Store.removeTask(t.id);
    toast(`Deleted “${t.text}”`, () => undoRemoval(prev, [t]));
  }
  function moveBy(id, dir) {
    const ids = Store.tasks.map((t) => t.id);
    const i = ids.indexOf(id), j = i + dir;
    if (i < 0 || j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    Store.reorder(ids);
  }
  function dropReorder(fromId, toId) {
    const ids = Store.tasks.map((t) => t.id);
    const from = ids.indexOf(fromId), to = ids.indexOf(toId);
    if (from < 0 || to < 0) return;
    ids.splice(to, 0, ids.splice(from, 1)[0]);
    Store.reorder(ids);
  }

  function fmtTime(ts) { return new Date(ts).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); }
  function fmtDue(hhmm) { const [h, m] = hhmm.split(":").map(Number); const d = new Date(); d.setHours(h, m, 0, 0); return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); }
  function isOverdue(t) { if (!t.due || t.done) return false; const [h, m] = t.due.split(":").map(Number); const now = new Date(); return now.getHours() * 60 + now.getMinutes() > h * 60 + m; }

  // History recording (debounced)
  function scheduleRecord() {
    clearTimeout(recordTimer);
    recordTimer = setTimeout(async () => { await Store.recordToday(); el.streak && refreshStreak(); }, 1200);
  }
  function refreshStreak() {
    const s = History.stats(Store.history || []);
    el.streak.innerHTML = `🔥 <strong>${s.streak}</strong>-day streak · <strong>${s.perfectDays}</strong> perfect day${s.perfectDays === 1 ? "" : "s"} · <strong>${s.totalCompleted}</strong> tasks done all-time`;
  }

  // =====================================================================
  // Toast
  // =====================================================================
  let toastTimer = null;
  function toast(message, undoFn) {
    el.toastMsg.textContent = message;
    el.toastUndo.hidden = !undoFn;
    el.toast.classList.add("show");
    clearTimeout(toastTimer);
    const dismiss = () => el.toast.classList.remove("show");
    toastTimer = setTimeout(dismiss, 6000);
    el.toastUndo.onclick = undoFn ? () => { clearTimeout(toastTimer); dismiss(); undoFn(); } : null;
  }

  // =====================================================================
  // Reminders
  // =====================================================================
  function requestReminders() {
    if (!("Notification" in window)) { alert("This browser doesn't support notifications."); return; }
    Notification.requestPermission().then((p) => {
      el.enableReminders.classList.toggle("active", p === "granted");
      el.enableReminders.textContent = p === "granted" ? "🔔 Reminders on" : "🔔 Reminders";
      if (p === "denied") alert("Reminders are blocked. Enable notifications for this page in your browser settings.");
    });
  }
  function checkReminders() {
    if (!("Notification" in window) || Notification.permission !== "granted") return;
    const now = new Date(); const cur = now.getHours() * 60 + now.getMinutes();
    for (const t of Store.tasks) {
      if (t.done || !t.due || notified.has(t.id)) continue;
      const [h, m] = t.due.split(":").map(Number);
      if (cur >= h * 60 + m) { notified.add(t.id); new Notification("⏰ Task due: " + t.text, { body: t.note || "Due at " + fmtDue(t.due), tag: t.id }); }
    }
  }

  // =====================================================================
  // New-day banner + carry over
  // =====================================================================
  function checkNewDay() {
    const { changed } = Store.isNewDay();
    if (changed && Store.templates.length > 0) {
      el.bannerText.textContent = `New day! Apply your daily template (${Store.templates.length} task${Store.templates.length > 1 ? "s" : ""})?`;
      el.templateBanner.classList.add("show");
    }
    Store.markDaySeen();
  }

  // =====================================================================
  // Theme + confetti
  // =====================================================================
  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    el.themeToggle && (el.themeToggle.textContent = theme === "light" ? "🌙" : "☀️");
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "light" ? "#f1f5f9" : "#0f172a");
  }
  function toggleTheme() {
    const next = document.documentElement.getAttribute("data-theme") === "light" ? "dark" : "light";
    localStorage.setItem("wc_theme", next);
    applyTheme(next);
  }
  function confetti() {
    const colors = ["#38bdf8", "#22c55e", "#fbbf24", "#f87171", "#a78bfa"];
    for (let i = 0; i < 60; i++) {
      const p = document.createElement("div");
      p.style.cssText = `position:fixed;top:-10px;left:${Math.random() * 100}vw;width:9px;height:9px;background:${colors[i % colors.length]};z-index:200;border-radius:2px;pointer-events:none;`;
      document.body.appendChild(p);
      const dx = (Math.random() - 0.5) * 240, dur = 1400 + Math.random() * 1200;
      p.animate(
        [ { transform: "translate(0,0) rotate(0)", opacity: 1 },
          { transform: `translate(${dx}px, ${window.innerHeight + 40}px) rotate(${Math.random() * 720}deg)`, opacity: 1 } ],
        { duration: dur, easing: "cubic-bezier(0.2,0.6,0.4,1)" }
      ).onfinish = () => p.remove();
    }
  }

  // =====================================================================
  // Modals: templates, share, history (built on demand)
  // =====================================================================
  function openTemplates() {
    const overlay = buildOverlay("Daily template", (modal) => {
      const sub = document.createElement("p"); sub.className = "sub";
      sub.textContent = "Recurring tasks for every work day. Apply with one click, or you'll be prompted each new day.";
      const form = document.createElement("form"); form.className = "tmpl-add";
      form.innerHTML = '<input type="text" placeholder="Recurring task…" autocomplete="off" /><input type="time" aria-label="Default due time" /><button class="btn-primary" type="submit">Add</button>';
      const list = document.createElement("ul"); list.className = "tmpl-list";
      const actions = document.createElement("div"); actions.className = "modal-actions";
      const saveBtn = document.createElement("button"); saveBtn.className = "btn-ghost"; saveBtn.textContent = "Save today's list as template";
      const applyBtn = document.createElement("button"); applyBtn.className = "btn-primary"; applyBtn.textContent = "Apply to today";
      actions.append(saveBtn, applyBtn);

      function renderList() {
        list.innerHTML = "";
        if (!Store.templates.length) { const e = document.createElement("li"); e.className = "tmpl-empty"; e.textContent = "No recurring tasks yet."; list.appendChild(e); return; }
        for (const item of Store.templates) {
          const li = document.createElement("li"); li.className = "tmpl-item";
          li.innerHTML = `<span class="t-text">${esc(item.text)}</span><span class="t-time">${item.due ? "⏰ " + fmtDue(item.due) : ""}</span>`;
          const del = mkBtn("×", "Remove", async () => { await Store.removeTemplate(item.id); renderList(); }); del.classList.add("del");
          li.appendChild(del); list.appendChild(li);
        }
      }
      form.addEventListener("submit", async (e) => { e.preventDefault(); const txt = form.children[0].value.trim(); if (!txt) return; await Store.addTemplate(txt, form.children[1].value); form.children[0].value = ""; form.children[1].value = ""; renderList(); form.children[0].focus(); });
      saveBtn.addEventListener("click", async () => { if (!Store.tasks.length) { alert("No tasks to save yet."); return; } if (Store.templates.length && !confirm("Replace your current template with today's list?")) return; await Store.setTemplatesFromTasks(); renderList(); });
      applyBtn.addEventListener("click", async () => { await Store.applyTemplate(); closeOverlay(overlay); });

      modal.append(sub, form, list, actions);
      renderList();
    });
  }

  async function openShare() {
    const overlay = buildOverlay("Share this list", async (modal) => {
      const sub = document.createElement("p"); sub.className = "sub";
      sub.textContent = "Share “" + (Store.currentList ? Store.currentList.name : "") + "” with another account by email. They'll see and (as editor) change the same tasks live.";
      const form = document.createElement("form"); form.className = "share-add";
      form.innerHTML = '<input type="email" placeholder="person@example.com" /><select aria-label="Role"><option value="editor">Editor</option><option value="viewer">Viewer</option></select><button class="btn-primary" type="submit">Share</button>';
      const err = document.createElement("p"); err.className = "field-error";
      const list = document.createElement("ul"); list.className = "share-list";

      async function renderShares() {
        list.innerHTML = "";
        let shares = [];
        try { shares = await Store.getShares(); } catch (e) {}
        if (!shares.length) { const e = document.createElement("li"); e.className = "tmpl-empty"; e.textContent = "Not shared with anyone yet."; list.appendChild(e); return; }
        for (const s of shares) {
          const li = document.createElement("li"); li.className = "share-item";
          li.innerHTML = `<span class="s-text">${esc(s.email || s.userId)}</span><span class="s-role">${esc(s.role)}</span>`;
          const del = mkBtn("×", "Remove access", async () => { await Store.unshare(s.userId); renderShares(); }); del.classList.add("del");
          li.appendChild(del); list.appendChild(li);
        }
      }
      form.addEventListener("submit", async (e) => {
        e.preventDefault(); err.textContent = "";
        const email = form.children[0].value.trim(); const role = form.children[1].value;
        if (!email) return;
        try { await Store.shareList(email, role); form.children[0].value = ""; renderShares(); toast("Shared with " + email, null); }
        catch (ex) { err.textContent = (ex && ex.message) || "Could not share."; }
      });
      modal.append(sub, form, err, list);
      renderShares();
    });
  }

  function openHistory() {
    buildOverlay("History & streaks", (modal) => {
      const s = History.stats(Store.history || []);
      const grid = document.createElement("div"); grid.className = "history-grid";
      grid.innerHTML =
        `<div class="stat"><div class="n">${s.streak}</div><div class="l">Day streak</div></div>` +
        `<div class="stat"><div class="n">${s.perfectDays}</div><div class="l">Perfect days</div></div>` +
        `<div class="stat"><div class="n">${s.totalCompleted}</div><div class="l">Tasks done</div></div>`;
      const sub = document.createElement("p"); sub.className = "sub"; sub.textContent = "Last 14 days — green bars are days you finished everything.";
      const spark = document.createElement("div"); spark.className = "spark";
      const recent = (Store.history || []).slice(-14);
      if (!recent.length) { const e = document.createElement("p"); e.className = "tmpl-empty"; e.textContent = "No history yet — complete some tasks to start your streak!"; modal.append(grid, e); return; }
      const max = Math.max(1, ...recent.map((h) => h.total));
      for (const h of recent) {
        const col = document.createElement("div"); col.className = "col";
        const bar = document.createElement("div"); bar.className = "bar2" + (History.isPerfect(h) ? " perfect" : "");
        bar.style.height = Math.round((h.completed / max) * 100) + "%";
        bar.title = `${h.day}: ${h.completed}/${h.total}`;
        const d = document.createElement("div"); d.className = "d"; d.textContent = h.day.slice(5);
        col.append(bar, d); spark.appendChild(col);
      }
      modal.append(grid, sub, spark);
    });
  }

  // Generic overlay builder
  function buildOverlay(title, fill) {
    const overlay = document.createElement("div"); overlay.className = "overlay open";
    const modal = document.createElement("div"); modal.className = "modal"; modal.setAttribute("role", "dialog"); modal.setAttribute("aria-modal", "true");
    const close = document.createElement("button"); close.className = "modal-close"; close.setAttribute("aria-label", "Close"); close.textContent = "×";
    close.addEventListener("click", () => closeOverlay(overlay));
    const h = document.createElement("h2"); h.textContent = title;
    modal.append(close, h);
    overlay.appendChild(modal);
    overlay.addEventListener("click", (e) => { if (e.target === overlay) closeOverlay(overlay); });
    overlay._esc = (e) => { if (e.key === "Escape") closeOverlay(overlay); };
    document.addEventListener("keydown", overlay._esc);
    document.body.appendChild(overlay);
    fill(modal);
    return overlay;
  }
  function closeOverlay(overlay) { document.removeEventListener("keydown", overlay._esc); overlay.remove(); }

  // =====================================================================
  // Events
  // =====================================================================
  function bindEvents() {
    el.addForm.addEventListener("submit", (e) => { e.preventDefault(); Store.addTask(el.taskInput.value, el.timeInput.value); el.taskInput.value = ""; el.timeInput.value = ""; el.taskInput.focus(); });

    el.filters.addEventListener("click", (e) => {
      const btn = e.target.closest(".filter"); if (!btn) return;
      filter = btn.dataset.filter; Store.setFilter(filter);
      [...el.filters.children].forEach((b) => b.classList.toggle("active", b === btn));
      render();
    });
    [...el.filters.children].forEach((b) => b.classList.toggle("active", b.dataset.filter === filter));

    el.clearDone.addEventListener("click", () => {
      const done = Store.tasks.filter((t) => t.done); if (!done.length) return;
      const prev = snapshot();
      Store.removeTasks(done.map((t) => t.id));
      toast(`Cleared ${done.length} completed task${done.length > 1 ? "s" : ""}`, () => undoRemoval(prev, done));
    });

    el.resetDay.addEventListener("click", async () => {
      if (!Store.tasks.length) return;
      await Store.recordToday();
      const done = Store.tasks.filter((t) => t.done); const prev = snapshot();
      const carried = Store.tasks.length - done.length;
      if (done.length) Store.removeTasks(done.map((t) => t.id)); else render();
      if (Store.templates.length) { el.bannerText.textContent = `New day! Apply your daily template (${Store.templates.length} task${Store.templates.length > 1 ? "s" : ""})?`; el.templateBanner.classList.add("show"); }
      const msg = done.length ? `New day — ${carried} carried over, ${done.length} cleared` : `New day — ${carried} task${carried === 1 ? "" : "s"} carried over`;
      toast(msg, () => undoRemoval(prev, done));
    });

    el.openTemplates.addEventListener("click", openTemplates);
    el.historyBtn.addEventListener("click", openHistory);
    el.shareBtn && el.shareBtn.addEventListener("click", openShare);
    el.themeToggle.addEventListener("click", toggleTheme);
    el.enableReminders.addEventListener("click", requestReminders);

    el.bannerApply.addEventListener("click", async () => { await Store.applyTemplate(); el.templateBanner.classList.remove("show"); });
    el.bannerDismiss.addEventListener("click", () => el.templateBanner.classList.remove("show"));

    // List switcher
    el.listSelect.addEventListener("change", () => Store.selectList(el.listSelect.value));
    el.newListBtn.addEventListener("click", async () => { const name = prompt("Name for the new list:", "New list"); if (name) await Store.createList(name.trim()); });

    // Export / import
    el.exportBtn.addEventListener("click", () => {
      const data = JSON.stringify({ version: 2, exportedAt: new Date().toISOString(), tasks: Store.tasks, templates: Store.templates }, null, 2);
      const blob = new Blob([data], { type: "application/json" });
      const url = URL.createObjectURL(blob); const a = document.createElement("a");
      a.href = url; a.download = `workday-checklist-${WC.todayKey()}.json`; a.click(); URL.revokeObjectURL(url);
      toast("Backup downloaded", null);
    });
    el.importBtn.addEventListener("click", () => el.importFile.click());
    el.importFile.addEventListener("change", () => {
      const file = el.importFile.files[0]; if (!file) return;
      const reader = new FileReader();
      reader.onload = async () => {
        try {
          const data = JSON.parse(reader.result);
          if (!data || (!Array.isArray(data.tasks) && !Array.isArray(data.templates))) throw new Error("bad");
          const prev = snapshot();
          await Store.importData(data);
          toast(Store.cloud ? "Backup imported into this list" : "Backup imported", Store.cloud ? null : () => Store.replaceTasks(prev));
        } catch (e) { alert("That doesn't look like a valid Workday Checklist backup file."); }
        el.importFile.value = "";
      };
      reader.readAsText(file);
    });

    // PWA install
    let deferredInstall = null;
    window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); deferredInstall = e; el.installBtn.hidden = false; });
    el.installBtn.addEventListener("click", async () => { if (!deferredInstall) return; deferredInstall.prompt(); await deferredInstall.userChoice; deferredInstall = null; el.installBtn.hidden = true; });
    window.addEventListener("appinstalled", () => { el.installBtn.hidden = true; });
    if ("serviceWorker" in navigator) window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));

    document.addEventListener("keydown", (e) => {
      const inField = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName) || document.activeElement.isContentEditable;
      if (e.key === "/" && !inField) { e.preventDefault(); el.taskInput.focus(); }
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
