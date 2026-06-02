/*
 * Auth UI: the account bar (top of the app) and the sign-in / sign-up modal.
 * In local mode it shows a "Sign in to sync" prompt; cloud mode shows the
 * signed-in email and a sign-out button.
 */
(function () {
  const WC = (window.WC = window.WC || {});
  const Store = WC.Store;

  function q(id) { return document.getElementById(id); }

  const Auth = {
    init() {
      this.bar = q("accountBar");
      this.overlay = q("authOverlay");
      this.form = q("authForm");
      this.emailEl = q("authEmail");
      this.pwEl = q("authPassword");
      this.nameRow = q("authNameRow");
      this.nameEl = q("authName");
      this.errEl = q("authError");
      this.submitBtn = q("authSubmit");
      this.toggleEl = q("authToggle");
      this.titleEl = q("authTitle");
      this.subEl = q("authSub");
      this.forgotEl = q("authForgot");
      this.googleBtn = q("googleBtn");
      this.dividerEl = q("authDivider");
      this.mode = "signin";

      q("authClose").addEventListener("click", () => this.close());
      this.overlay.addEventListener("click", (e) => { if (e.target === this.overlay) this.close(); });
      this.toggleEl.addEventListener("click", () => this.setMode(this.mode === "signin" ? "signup" : "signin"));
      this.forgotEl && this.forgotEl.addEventListener("click", () => this.sendReset());
      this.googleBtn && this.googleBtn.addEventListener("click", () => this.googleSignIn());
      this.form.addEventListener("submit", (e) => this.submit(e));
      document.addEventListener("keydown", (e) => { if (e.key === "Escape" && this.overlay.classList.contains("open")) this.close(); });

      this.render();
    },

    render() {
      if (!this.bar) return;
      if (!WC.cloudEnabled) {
        this.bar.innerHTML =
          '<span class="acct-muted">Local mode — data stays in this browser. ' +
          '<a href="https://supabase.com" target="_blank" rel="noopener">Set up cloud sync</a> in <code>assets/config.js</code>.</span>';
        return;
      }
      if (Store.cloud && Store.user) {
        const name = Store.user.name && Store.user.name !== Store.user.email ? Store.user.name : null;
        const avatar = Store.user.avatar
          ? '<img class="acct-avatar" src="' + escapeHtml(Store.user.avatar) + '" alt="" referrerpolicy="no-referrer" />'
          : "";
        this.bar.innerHTML =
          '<span class="acct-muted acct-id">' + avatar + "Signed in as <strong>" + escapeHtml(name || Store.user.email) + "</strong>" +
          (name ? ' <span class="acct-email">' + escapeHtml(Store.user.email) + "</span>" : "") +
          "</span>" +
          '<span class="sync-status" id="syncStatus" role="status" aria-live="polite"></span>' +
          '<button class="pill" id="signOutBtn">Sign out</button>';
        q("signOutBtn").addEventListener("click", () => Store.signOut());
        this.setSync(navigator.onLine ? "synced" : "offline");
      } else {
        this.bar.innerHTML =
          '<span class="acct-muted">Not signed in — using local data.</span>' +
          '<button class="pill" id="signInBtn">Sign in / Sign up</button>';
        q("signInBtn").addEventListener("click", () => this.open());
      }
    },

    open() { this.setMode("signin"); this.errEl.textContent = ""; this._show(); this.emailEl.focus(); },
    openRecovery() { this.setMode("recovery"); this.errEl.textContent = ""; this._show(); this.pwEl.focus(); },
    _show() {
      this._prevFocus = document.activeElement;
      this.overlay.classList.add("open");
      if (WC.modalTrap) WC.modalTrap(this.overlay, this.overlay.querySelector(".modal"));
    },
    close() {
      this.overlay.classList.remove("open");
      if (WC.modalRelease) WC.modalRelease(this.overlay);
    },

    setMode(mode) {
      this.mode = mode;
      const signup = mode === "signup";
      const recovery = mode === "recovery";
      this.titleEl.textContent = recovery ? "Set a new password" : signup ? "Create account" : "Sign in";
      this.submitBtn.textContent = recovery ? "Save password" : signup ? "Create account" : "Sign in";
      this.toggleEl.textContent = signup ? "Have an account? Sign in" : "New here? Create an account";
      this.toggleEl.style.display = recovery ? "none" : "";
      this.nameRow.style.display = signup ? "flex" : "none";
      this.emailEl.style.display = recovery ? "none" : ""; // hide email field on recovery
      this.emailEl.required = !recovery;
      this.pwEl.placeholder = recovery ? "New password" : "Password";
      this.pwEl.autocomplete = recovery || signup ? "new-password" : "current-password";
      if (this.forgotEl) this.forgotEl.style.display = mode === "signin" ? "" : "none";
      if (this.subEl) this.subEl.style.display = recovery ? "none" : "";
      if (this.googleBtn) this.googleBtn.style.display = recovery ? "none" : "";
      if (this.dividerEl) this.dividerEl.style.display = recovery ? "none" : "";
      this.errEl.textContent = "";
    },

    async googleSignIn() {
      this.errEl.textContent = "";
      this.googleBtn.disabled = true;
      try {
        await Store.signInWithGoogle();   // redirects to Google, then back to the app
      } catch (err) {
        this.errEl.style.color = "var(--danger)";
        this.errEl.textContent = friendlyAuthError(err);
        this.googleBtn.disabled = false;
      }
    },

    async sendReset() {
      const email = this.emailEl.value.trim();
      if (!email) { this.errEl.style.color = "var(--danger)"; this.errEl.textContent = "Enter your email above first, then tap “Forgot password?”."; this.emailEl.focus(); return; }
      this.forgotEl.disabled = true;
      try {
        await Store.resetPassword(email);
        this.errEl.style.color = "var(--done)";
        this.errEl.textContent = "Password reset link sent — check your inbox (and spam).";
      } catch (err) {
        this.errEl.style.color = "var(--danger)";
        this.errEl.textContent = friendlyAuthError(err);
      } finally {
        this.forgotEl.disabled = false;
      }
    },

    async submit(e) {
      e.preventDefault();
      const email = this.emailEl.value.trim();
      const pw = this.pwEl.value;
      if (this.mode !== "recovery" && (!email || !pw)) return;
      if (this.mode === "recovery" && !pw) return;
      this.submitBtn.disabled = true;
      this.errEl.textContent = "";
      try {
        if (this.mode === "recovery") {
          await Store.updatePassword(pw);
          this.close();
        } else if (this.mode === "signup") {
          await Store.signUp(email, pw, this.nameEl.value.trim());
          // Some projects require email confirmation; sign-in may not be immediate.
          this.errEl.style.color = "var(--done)";
          this.errEl.textContent = "Account created. If email confirmation is on, check your inbox, then sign in.";
          this.setMode("signin");
        } else {
          await Store.signIn(email, pw);
          this.close();
        }
      } catch (err) {
        this.errEl.style.color = "var(--danger)";
        this.errEl.textContent = friendlyAuthError(err);
      } finally {
        this.submitBtn.disabled = false;
      }
    },

    setSync(state) {
      const elx = q("syncStatus");
      if (!elx) return;
      if (!navigator.onLine) state = "offline";
      const map = {
        syncing: ["…", "Saving…", "syncing"],
        synced: ["✓", "Synced", "ok"],
        remote: ["⟳", "Updated", "ok"],
        offline: ["•", "Offline", "offline"],
      };
      const [icon, text, cls] = map[state] || map.synced;
      elx.className = "sync-status " + cls;
      elx.textContent = icon + " " + text;
      if (state === "syncing" || state === "remote") {
        clearTimeout(this._syncT);
        this._syncT = setTimeout(() => this.setSync(navigator.onLine ? "synced" : "offline"), 1200);
      }
    },
  };

  function friendlyAuthError(err) {
    const m = (err && err.message) || "";
    if (/invalid login credentials/i.test(m)) return "Email or password is incorrect.";
    if (/already registered|already exists/i.test(m)) return "That email already has an account — try signing in.";
    if (/password should be at least|at least 6/i.test(m)) return "Password is too short (use at least 6 characters).";
    if (/email not confirmed/i.test(m)) return "Please confirm your email first — check your inbox.";
    if (/rate limit|too many/i.test(m)) return "Too many attempts. Please wait a moment and try again.";
    if (/network|fetch|failed to/i.test(m)) return "Network problem — check your connection and try again.";
    return m || "Something went wrong.";
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  WC.Auth = Auth;
  WC.escapeHtml = escapeHtml;
})();
