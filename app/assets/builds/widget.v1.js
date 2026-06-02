(function () {
  "use strict";

  // Bump this on every functional change to this file. It is exposed as
  // window.__chgtool.version for debugging and surfaces in error reports.
  // It does NOT drive cache busting on its own — that's handled by ETag +
  // Last-Modified on the /w/v1/loader.js response (see assets_controller).
  var WIDGET_VERSION = "1.5.0";

  // ---- boot guard ------------------------------------------------

  try {
    var LOG_PREFIX = "[changelog-tool]";
    // How long the JSON payload is reused from localStorage before re-fetching.
    // Kept short so that a release published in chibichange is visible to the
    // user within a minute on their next pageload (or Turbo navigation). The
    // beacon endpoint is rate-limited at 60/min/origin, well above this rate.
    var TTL_MS     = 60 * 1000;
    var TIMEOUT_MS = 5000;
    var HOST_ID    = "chgtool-host";
    var MAX_TEXT_LEN   = 4096;
    var MAX_LIST_DEPTH = 6;

    function log(level, msg, err) {
      if (typeof console === "undefined" || !console[level]) return;
      if (err) { console[level](LOG_PREFIX + " " + msg, err); }
      else     { console[level](LOG_PREFIX + " " + msg); }
    }

    // ---- error containment ---------------------------------------------

    var errorReportedThisLoad = {}; // key: (errorClass + ":" + label) → true
    var errorReportDebounceUntil = 0;

    function safe(fn, label) {
      return function () {
        try { return fn.apply(this, arguments); }
        catch (e) {
          log("error", "caught error in " + (label || "handler"), e);
          reportError(e, label);
        }
      };
    }

    // Best-effort error reporting (currently logs only).
    function reportError(err, label) {
      try {
        if (Date.now() < errorReportDebounceUntil) return;
        errorReportDebounceUntil = Date.now() + 5000;
        var errorClass = (err && err.name) ? String(err.name) : "Error";
        var key = errorClass + ":" + (label || "");
        if (errorReportedThisLoad[key]) return;
        errorReportedThisLoad[key] = true;
        // A future version may POST to an error endpoint here; for now, log only.
        log("warn", "error report queued: " + key);
      } catch (e) { /* never throw out of reportError */ }
    }

    var script = document.currentScript;
    if (!script) { log("error", "no document.currentScript — refusing to run"); return; }

    var slug    = script.getAttribute("data-slug");
    var version = script.getAttribute("data-version") || "unknown";

    if (!slug) { log("error", "data-slug attribute is required"); return; }
    if (!script.getAttribute("data-version")) {
      log("warn", "data-version attribute missing; latest-version comparison disabled");
    }

    // ---- consent gate -------------------------------------------------------
    // The host embeds this script ONLY after the end user has opted in, but we
    // enforce it here too: if data-consent is present and not exactly "granted",
    // the widget is a complete no-op — no DOM, no network, no beacon. Absent
    // attribute = granted (backward compatible with existing embeds).
    var consent = script.getAttribute("data-consent");
    if (consent !== null && consent !== "granted") {
      log("warn", "data-consent is not 'granted' — widget disabled");
      return;
    }

    // Optional inline-mount target. When data-mount resolves to an element, the
    // host is appended there (and the pill renders inline) instead of the default
    // fixed bottom-right pill on document.body. The modal stays a full-screen
    // overlay regardless of mount mode.
    var mountSelector = script.getAttribute("data-mount");
    var mountTarget   = null;
    if (mountSelector) {
      try {
        mountTarget = document.querySelector(mountSelector);
        if (!mountTarget) {
          log("warn", "data-mount selector did not match — falling back to body");
        }
      } catch (selErr) {
        log("warn", "data-mount selector invalid — falling back to body");
      }
    }

    // Namespace + single-instance guard
    window.__chgtool = window.__chgtool || { version: WIDGET_VERSION, instances: {} };
    if (window.__chgtool.instances[slug]) {
      log("warn", "widget for slug=" + slug + " already loaded — skipping");
      return;
    }

    var endpoint = (function () {
      try {
        var u = new URL(script.src);
        return u.origin + "/w/v1/" + encodeURIComponent(slug) + ".json?v=" + encodeURIComponent(version);
      } catch (e) {
        log("error", "could not derive endpoint from script src: " + script.src);
        return null;
      }
    })();
    if (!endpoint) return;

    var cacheKey = "chgtool:" + slug;
    var seenKey  = "chgtool:seen:" + slug;

    // ---- "seen" state -------------------------------------------------------
    //
    // A fingerprint of the latest release (version + release date) the user
    // has acknowledged. When the next payload's fingerprint matches, the pill
    // is suppressed; when a new release lands the fingerprint differs and the
    // pill returns. Independent of the JSON cache so a stale cache still
    // surfaces an unseen release once it expires.

    function fingerprintFor(data) {
      if (!data) return null;
      var v = data.latest_version || "";
      var t = data.latest_released_at || "";
      if (!v && !t) return null;
      return v + "|" + t;
    }

    function hasSeen(data) {
      var fp = fingerprintFor(data);
      if (!fp) return false;
      try { return localStorage.getItem(seenKey) === fp; } catch (e) { return false; }
    }

    function markSeen(data) {
      var fp = fingerprintFor(data);
      if (!fp) return;
      try { localStorage.setItem(seenKey, fp); } catch (e) { /* private mode etc */ }
    }

    // ---- cache --------------------------------------------------------------

    function loadCache() {
      try {
        var raw = window.localStorage.getItem(cacheKey);
        if (!raw) return null;
        var parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== "object") return null;
        return parsed;
      } catch (e) { return null; }
    }

    function saveCache(data) {
      try {
        var record = {};
        for (var k in data) { if (Object.prototype.hasOwnProperty.call(data, k)) record[k] = data[k]; }
        record.fetched_at = Date.now();
        window.localStorage.setItem(cacheKey, JSON.stringify(record));
      } catch (e) { log("warn", "localStorage write failed", e); }
    }

    function clearCache() {
      try { window.localStorage.removeItem(cacheKey); } catch (e) {}
    }

    // ---- fetch --------------------------------------------------------------

    function fetchPayload() {
      return new Promise(function (resolve, reject) {
        var controller = (typeof AbortController !== "undefined") ? new AbortController() : null;
        var timer = setTimeout(function () {
          if (controller) controller.abort();
          reject(new Error("timeout after " + TIMEOUT_MS + "ms"));
        }, TIMEOUT_MS);

        var opts = {
          credentials: "omit",
          mode: "cors",
          referrerPolicy: "strict-origin-when-cross-origin"
        };
        if (controller) opts.signal = controller.signal;

        fetch(endpoint, opts).then(function (res) {
          clearTimeout(timer);
          if (res.status === 404) { reject({ status: 404 }); return; }
          if (res.status === 429) { reject({ status: 429, retryAfter: res.headers.get("Retry-After") }); return; }
          if (!res.ok) { reject({ status: res.status }); return; }

          var contentType = (res.headers.get("content-type") || "").toLowerCase();
          if (contentType.indexOf("application/json") === -1) {
            reject(new Error("unexpected content-type: " + contentType));
            return;
          }

          var contentLength = parseInt(res.headers.get("content-length") || "0", 10);
          if (contentLength && contentLength > 262144) {
            reject(new Error("payload too large: " + contentLength + " bytes"));
            return;
          }

          return res.text().then(function (txt) {
            if (txt.length > 262144) {
              reject(new Error("payload too large: " + txt.length + " bytes"));
              return null;
            }
            try { return JSON.parse(txt); }
            catch (e) { reject(new Error("invalid JSON: " + e.message)); return null; }
          });
        }).then(function (data) {
          if (data) resolve(data);
        }).catch(function (err) {
          clearTimeout(timer);
          reject(err);
        });
      });
    }

    // ---- safe href validator ------------------------------------------------

    function validHref(href) {
      if (typeof href !== "string") return false;
      var trimmed = href.trim();
      // Reject any href containing control characters (NUL, tab, newline, etc.)
      // or DEL (0x7F). Mirrors server-side Markdown::Allowlist tightening.
      if (/[\x00-\x1f\x7f]/.test(trimmed)) return false;
      return /^https:/i.test(trimmed) || /^mailto:/i.test(trimmed);
    }

    // ---- token tree -> DOM (text nodes only, no markdown parser) -----------

    function renderTokens(tokens, parent, depth) {
      if (!Array.isArray(tokens)) return;
      depth = depth || 0;
      for (var i = 0; i < tokens.length; i++) {
        try {
          var node = tokens[i];
          if (!node || typeof node !== "object") continue;
          switch (node.t) {
            case "text":
              var raw = node.v == null ? "" : String(node.v);
              if (raw.length > MAX_TEXT_LEN) raw = raw.substring(0, MAX_TEXT_LEN) + "…";
              parent.appendChild(document.createTextNode(raw));
              continue;
            case "code":
              var code = document.createElement("code");
              var codeText = node.v == null ? "" : String(node.v);
              if (codeText.length > MAX_TEXT_LEN) codeText = codeText.substring(0, MAX_TEXT_LEN) + "…";
              code.textContent = codeText;
              parent.appendChild(code);
              continue;
            case "ul": case "ol":
              if (depth >= MAX_LIST_DEPTH) {
                // Render children as a flat sequence (no nested list) past the cap.
                renderTokens(node.c, parent, depth + 1);
                continue;
              }
              var listEl = document.createElement(node.t);
              renderTokens(node.c, listEl, depth + 1);
              parent.appendChild(listEl);
              continue;
            case "p": case "strong": case "em": case "li":
              var el = document.createElement(node.t);
              renderTokens(node.c, el, depth + 1);
              parent.appendChild(el);
              continue;
            case "a":
              if (!validHref(node.href)) { renderTokens(node.c, parent, depth + 1); continue; }
              var a = document.createElement("a");
              a.href = String(node.href);
              a.rel = "noopener noreferrer";
              a.target = "_blank";
              renderTokens(node.c, a, depth + 1);
              parent.appendChild(a);
              continue;
            default:
              log("warn", "unknown token type " + JSON.stringify(node.t));
              continue;
          }
        } catch (nodeErr) {
          log("warn", "renderTokens skipped a node", nodeErr);
          reportError(nodeErr, "render-token-" + (tokens[i] && tokens[i].t));
        }
      }
    }

    // Render version blocks with kind subsections. `versions` is the payload's
    // top-level `versions` array (newest first, capped server-side). Each
    // version contains `entries_by_kind`, an object whose keys are KEEP-A-
    // CHANGELOG kinds and values are flat token arrays.
    function renderVersions(versions, parent) {
      for (var i = 0; i < versions.length; i++) {
        try {
          var v = versions[i];
          if (!v || typeof v !== "object") continue;

          var vWrap = document.createElement("div");
          vWrap.className = "chgtool-version";

          var vHead = document.createElement("h3");
          vHead.className = "chgtool-version__h";
          var headText = String(v.number || "");
          if (v.released_at) headText += "  ·  " + v.released_at;
          vHead.textContent = headText;
          vWrap.appendChild(vHead);

          var ebk = (v.entries_by_kind && typeof v.entries_by_kind === "object") ? v.entries_by_kind : {};
          for (var k in ebk) {
            if (!Object.prototype.hasOwnProperty.call(ebk, k)) continue;
            var tokens = ebk[k];
            if (!Array.isArray(tokens) || tokens.length === 0) continue;

            var kindWrap = document.createElement("div");
            kindWrap.className = "chgtool-kind chgtool-kind--" + k;

            var kHead = document.createElement("h4");
            kHead.className = "chgtool-kind__h";
            kHead.textContent = k.charAt(0).toUpperCase() + k.slice(1);
            kindWrap.appendChild(kHead);

            var kBody = document.createElement("div");
            kBody.className = "chgtool-kind__body";
            renderTokens(tokens, kBody);
            kindWrap.appendChild(kBody);

            vWrap.appendChild(kindWrap);
          }

          parent.appendChild(vWrap);
        } catch (vErr) {
          log("warn", "renderVersions skipped a version", vErr);
          reportError(vErr, "render-version");
        }
      }
    }

    // ---- Shadow DOM root -------------------------------------------

    var hostElement      = null;
    var shadowRoot       = null;
    var pillElement      = null;
    // When in inline-mount mode the pill lives inside the mount target but the
    // modal is hoisted to document.body so it can escape any transformed /
    // contained ancestor (e.g. daisyUI tooltips, framer-motion wrappers).
    var modalHostElement = null;
    var modalShadowRoot  = null;

    var STYLESHEET = [
      ":host { all: initial; font: 14px/1.55 system-ui,-apple-system,sans-serif; color-scheme: light dark; }",
      ".chgtool-pill { position: fixed; right: 16px; bottom: 16px; z-index: 2147483646; background: #0f172a; color: #fff; font: 500 13px/1 inherit; padding: 8px 12px; border-radius: 9999px; cursor: pointer; border: 0; box-shadow: 0 4px 12px rgba(0,0,0,.15); }",
      ".chgtool-pill--inline { position: static; display: inline-block; width: 8px; height: 8px; min-width: 0; padding: 0; margin-left: 8px; background: #22c55e; border-radius: 9999px; vertical-align: middle; font-size: 0; line-height: 0; box-shadow: 0 0 0 0 rgba(34,197,94,.55); animation: chgtool-pulse 1.8s cubic-bezier(.4,0,.6,1) infinite; cursor: pointer; }",
      "@keyframes chgtool-pulse { 0%,100% { box-shadow: 0 0 0 0 rgba(34,197,94,.55); } 50% { box-shadow: 0 0 0 7px rgba(34,197,94,0); } }",
      "@media (prefers-reduced-motion: reduce) { .chgtool-pill--inline { animation: none; } }",
      ".chgtool-pill--seen { animation: none; box-shadow: none; opacity: .55; }",
      ".chgtool-pill__count { margin-left: 6px; background: #fff; color: #0f172a; border-radius: 9999px; padding: 1px 6px; font-size: 11px; }",
      ".chgtool-mask { position: fixed; inset: 0; z-index: 2147483647; background: rgba(15,23,42,.45); display: flex; align-items: center; justify-content: center; }",
      ".chgtool-dlg { position: relative; max-width: 520px; width: 90vw; max-height: 80vh; overflow: auto; background: #fff; color: #0f172a; border-radius: 12px; padding: 20px 22px; box-shadow: 0 20px 50px rgba(0,0,0,.25); }",
      ".chgtool-dlg__h { margin: 0 0 4px; font-size: 16px; font-weight: 600; }",
      ".chgtool-dlg__meta { color: #64748b; font-size: 12px; margin-bottom: 16px; }",
      ".chgtool-dlg__meta--update { color: #0369a1; }",
      ".chgtool-dlg__section { margin-top: 14px; }",
      ".chgtool-version { margin-bottom: 18px; padding-bottom: 14px; border-bottom: 1px solid #e2e8f0; }",
      ".chgtool-version:last-child { margin-bottom: 0; padding-bottom: 0; border-bottom: 0; }",
      ".chgtool-version__h { margin: 0 0 10px; font-size: 14px; font-weight: 600; color: #0f172a; letter-spacing: -.005em; }",
      ".chgtool-kind { margin-top: 10px; }",
      ".chgtool-kind:first-of-type { margin-top: 0; }",
      ".chgtool-kind__h { margin: 0 0 4px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; color: #64748b; }",
      ".chgtool-kind__body p { margin: 0 0 4px; }",
      ".chgtool-kind__body p:last-child { margin-bottom: 0; }",
      ".chgtool-kind__body ul, .chgtool-kind__body ol { margin: 0 0 4px; padding-left: 20px; }",
      ".chgtool-kind--added .chgtool-kind__h    { color: #059669; }",
      ".chgtool-kind--changed .chgtool-kind__h  { color: #d97706; }",
      ".chgtool-kind--deprecated .chgtool-kind__h { color: #6b7280; }",
      ".chgtool-kind--removed .chgtool-kind__h  { color: #dc2626; }",
      ".chgtool-kind--fixed .chgtool-kind__h    { color: #2563eb; }",
      ".chgtool-kind--security .chgtool-kind__h { color: #dc2626; }",
      ".chgtool-dlg__more { margin: 18px 0 0; padding-top: 14px; border-top: 1px solid #e2e8f0; font-size: 13px; }",
      ".chgtool-dlg__more a { color: #0369a1; text-decoration: none; }",
      ".chgtool-dlg__more a:hover { text-decoration: underline; }",
      ".chgtool-dlg__close { position: absolute; top: 10px; right: 14px; background: transparent; border: 0; font-size: 18px; cursor: pointer; color: #64748b; }"
    ].join("\n");

    function ensureHostElement() {
      if (hostElement && hostElement.isConnected) return;
      hostElement = document.createElement("div");
      hostElement.id = HOST_ID;
      hostElement.setAttribute("data-slug", slug);
      var parent = mountTarget || document.body;
      if (mountTarget) {
        hostElement.setAttribute("data-mount", "inline");
        // Collapse the host around the 8px pill instead of inheriting the
        // mount target's line-height (which made the host 21.7px tall inside
        // daisyUI's .badge and pushed the dot above the baseline).
        hostElement.style.cssText =
          "display: inline-flex; align-items: center; vertical-align: middle; line-height: 0;";
      }
      parent.appendChild(hostElement);
      shadowRoot = hostElement.attachShadow({ mode: "closed" });
      var style = document.createElement("style");
      style.textContent = STYLESHEET;
      shadowRoot.appendChild(style);
    }

    function ensureModalHost() {
      // Used only in inline-mount mode. Modal lives on document.body so that
      // it can use position:fixed/inset:0 regardless of whatever the mount
      // target's ancestors are doing (transforms, contain, etc.).
      if (modalHostElement && modalHostElement.isConnected) return;
      modalHostElement = document.createElement("div");
      modalHostElement.id = HOST_ID + "-modal";
      modalHostElement.setAttribute("data-slug", slug);
      document.body.appendChild(modalHostElement);
      modalShadowRoot = modalHostElement.attachShadow({ mode: "closed" });
      var style = document.createElement("style");
      style.textContent = STYLESHEET;
      modalShadowRoot.appendChild(style);
    }

    function destroy() {
      if (hostElement && hostElement.parentNode) {
        hostElement.parentNode.removeChild(hostElement);
      }
      if (modalHostElement && modalHostElement.parentNode) {
        modalHostElement.parentNode.removeChild(modalHostElement);
      }
      hostElement      = null;
      shadowRoot       = null;
      pillElement      = null;
      modalHostElement = null;
      modalShadowRoot  = null;
    }

    // ---- UI -----------------------------------------------------------------

    function render(data) {
      if (!data || !data.project) { log("warn", "render skipped — empty payload"); return; }
      var count = (typeof data.total_entries === "number") ? data.total_entries : 0;
      if (count === 0 && data.update_available !== true) return;

      var seen = hasSeen(data);
      // Floating mode hides the whole pill once acknowledged (the pill is
      // attention-grabbing on its own). Inline mode keeps a calm static dot
      // so the user still sees "an update exists" without the pulse.
      if (seen && !mountTarget) return;

      ensureHostElement();

      var btn = document.createElement("button");
      btn.type = "button";
      var classes = mountTarget ? "chgtool-pill chgtool-pill--inline" : "chgtool-pill";
      if (mountTarget && seen) classes += " chgtool-pill--seen";
      btn.className = classes;
      btn.setAttribute("aria-label", "Show changelog");
      btn.setAttribute("data-chgtool", "pill");

      if (mountTarget) {
        // Inline mode: a pulsing green dot, no text. The dot itself is the
        // entire signal — visible only when the render guard above passed
        // (count > 0 or update_available === true). aria-label keeps it
        // discoverable for assistive tech and the click still opens the modal.
        // textContent stays empty.
      } else {
        // Floating mode: full "What's New" pill with optional count chip.
        btn.appendChild(document.createTextNode("What's New"));
        if (count > 0) {
          var chip = document.createElement("span");
          chip.className = "chgtool-pill__count";
          chip.textContent = "(" + count + ")";
          btn.appendChild(chip);
        }
      }

      btn.addEventListener("click", safe(function () {
        markSeen(data);
        openModal(data);
      }, "pill-click"));
      shadowRoot.appendChild(btn);
      pillElement = btn;
    }

    function openModal(data) {
      var mask = document.createElement("div");
      mask.className = "chgtool-mask";
      mask.setAttribute("data-chgtool", "modal");
      mask.addEventListener("click", safe(function (e) {
        if (e.target === mask && mask.parentNode) mask.parentNode.removeChild(mask);
      }, "mask-click"));

      var dlg = document.createElement("div");
      dlg.className = "chgtool-dlg";

      var close = document.createElement("button");
      close.type = "button";
      close.className = "chgtool-dlg__close";
      close.setAttribute("aria-label", "Close");
      close.textContent = "×";
      close.addEventListener("click", safe(function () { if (mask.parentNode) mask.parentNode.removeChild(mask); }, "close-click"));
      dlg.appendChild(close);

      var h = document.createElement("h2");
      h.className = "chgtool-dlg__h";
      h.textContent = (data.project.name || data.project.slug) + " — What's New";
      dlg.appendChild(h);

      if (data.update_available === true && data.latest_version) {
        var upd = document.createElement("p");
        upd.className = "chgtool-dlg__meta chgtool-dlg__meta--update";
        upd.textContent = "Update available: " + data.latest_version;
        dlg.appendChild(upd);
      } else if (data.latest_version) {
        var meta = document.createElement("p");
        meta.className = "chgtool-dlg__meta";
        meta.textContent = "Latest: " + data.latest_version + (data.latest_released_at ? " (" + data.latest_released_at + ")" : "");
        dlg.appendChild(meta);
      }

      var section = document.createElement("section");
      section.className = "chgtool-dlg__section";
      var versions = Array.isArray(data.versions) ? data.versions : [];
      if (versions.length === 0) {
        var empty = document.createElement("p");
        empty.textContent = "Nothing new since your version.";
        section.appendChild(empty);
      } else {
        renderVersions(versions, section);
      }
      dlg.appendChild(section);

      // "View N more releases →" link when the server truncated the payload.
      // Derives the public-changelog URL from the script src origin so it
      // works under any host (cloud, self-hosted, local dev).
      var moreCount = (typeof data.more_versions_count === "number") ? data.more_versions_count : 0;
      if (moreCount > 0) {
        var href = null;
        try {
          var u = new URL(script.src);
          href = u.origin + "/c/" + encodeURIComponent(slug);
        } catch (e) { /* leave href null, footer falls back to text */ }

        var footer = document.createElement("p");
        footer.className = "chgtool-dlg__more";
        var label = "View " + moreCount + " older " + (moreCount === 1 ? "release" : "releases") + " →";
        if (href) {
          var a = document.createElement("a");
          a.href = href;
          a.target = "_blank";
          a.rel = "noopener noreferrer";
          a.textContent = label;
          footer.appendChild(a);
        } else {
          footer.textContent = label;
        }
        dlg.appendChild(footer);
      }

      mask.appendChild(dlg);
      if (mountTarget) {
        ensureModalHost();
        modalShadowRoot.appendChild(mask);
      } else {
        shadowRoot.appendChild(mask);
      }
    }

    // ---- run ----------------------------------------------------------------

    function run() {
      var cached = loadCache();
      var stale = !cached || (Date.now() - (cached.fetched_at || 0) > TTL_MS);

      if (!stale) { render(cached); return; }

      fetchPayload().then(function (data) {
        saveCache(data);
        render(data);
      }).catch(function (err) {
        if (err && err.status === 404) {
          clearCache();
          log("warn", "slug '" + slug + "' not found");
          return;
        }
        if (err && err.status === 429) {
          log("warn", "rate limited; respecting Retry-After=" + err.retryAfter);
          if (cached) render(cached);
          return;
        }
        log("warn", "beacon fetch failed", err);
        if (cached) render(cached);
      });
    }

    // Register the instance with debug-hook stubs.
    // pillElement() and destroy() are STABLE TEST API — do not rename. The widget
    // safety specs depend on these names to introspect the closed shadow root.
    window.__chgtool.instances[slug] = {
      pillElement: function () { return pillElement; },
      destroy: destroy
    };

    // ---- Turbo lifecycle -------------------------------------

    function hasTurbo() {
      return typeof window.Turbo !== "undefined";
    }

    function onTurboBeforeCache() {
      destroy();
    }

    function onTurboLoad() {
      // Re-init: but only if no instance is currently mounted. Since destroy()
      // clears local references, calling run() here re-fetches (or uses cache).
      if (!hostElement) run();
    }

    if (hasTurbo()) {
      document.addEventListener("turbo:before-cache", safe(onTurboBeforeCache, "turbo-before-cache"));
      document.addEventListener("turbo:load", safe(onTurboLoad, "turbo-load"));
    }

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", run);
    } else {
      run();
    }
  } catch (bootErr) {
    if (typeof console !== "undefined" && console.error) {
      console.error("[changelog-tool] boot failed", bootErr);
    }
  }
})();
