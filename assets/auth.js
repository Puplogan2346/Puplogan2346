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
      this.mode = "signin";

      q("authClose").addEventListener("click", () => this.close());
      this.overlay.addEventListener("click", (e) => { if (e.target === this.overlay) this.close(); });
      this.toggleEl.addEventListener("click", () => this.setMode(this.mode === "signin" ? "signup" : "signin"));
      this.form.addEventListener("submit", (e) => this.submit(e));

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
        this.bar.innerHTML =
          '<span class="acct-muted">Signed in as <strong>' + escapeHtml(Store.user.email) + "</strong></span>" +
          '<button class="pill" id="signOutBtn">Sign out</button>';
        q("signOutBtn").addEventListener("click", () => Store.signOut());
      } else {
        this.bar.innerHTML =
          '<span class="acct-muted">Not signed in — using local data.</span>' +
          '<button class="pill" id="signInBtn">Sign in / Sign up</button>';
        q("signInBtn").addEventListener("click", () => this.open());
      }
    },

    open() { this.setMode("signin"); this.errEl.textContent = ""; this.overlay.classList.add("open"); this.emailEl.focus(); },
    close() { this.overlay.classList.remove("open"); },

    setMode(mode) {
      this.mode = mode;
      const signup = mode === "signup";
      this.titleEl.textContent = signup ? "Create account" : "Sign in";
      this.submitBtn.textContent = signup ? "Create account" : "Sign in";
      this.toggleEl.textContent = signup ? "Have an account? Sign in" : "New here? Create an account";
      this.nameRow.style.display = signup ? "flex" : "none";
      this.errEl.textContent = "";
    },

    async submit(e) {
      e.preventDefault();
      const email = this.emailEl.value.trim();
      const pw = this.pwEl.value;
      if (!email || !pw) return;
      this.submitBtn.disabled = true;
      this.errEl.textContent = "";
      try {
        if (this.mode === "signup") {
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
        this.errEl.textContent = (err && err.message) || "Something went wrong.";
      } finally {
        this.submitBtn.disabled = false;
      }
    },
  };

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  WC.Auth = Auth;
  WC.escapeHtml = escapeHtml;
})();
