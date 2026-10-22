/* Markdown -> DOM for the Quick Look preview and thumbnail extensions.
   Every URL on this page is served by the extension, from its own bundle or
   from the directory holding the previewed file. The page's content security
   policy names no http(s) source, so rendering never reaches the network. */
(function () {
  "use strict";

  var payload = window.MDQL_PAYLOAD || { markdown: "", mode: "preview", vendor: "vendor/" };
  var notices = [];
  var content = document.getElementById("content");

  function vendor(path) { return payload.vendor + path; }

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var el = document.createElement("script");
      // Scripts are allowed by nonce only, so an engine loaded on demand has to
      // carry the same one the page was served with.
      if (payload.nonce) el.setAttribute("nonce", payload.nonce);
      el.src = src;
      el.onload = function () { resolve(); };
      el.onerror = function () { reject(new Error("failed to load " + src)); };
      document.head.appendChild(el);
    });
  }

  function loadStyle(href) {
    return new Promise(function (resolve) {
      var el = document.createElement("link");
      el.rel = "stylesheet";
      el.href = href;
      el.onload = el.onerror = function () { resolve(); };
      document.head.appendChild(el);
    });
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  /* ---------- front matter ---------- */

  function splitFrontMatter(text) {
    var m = /^﻿?(?:---|\+\+\+)\r?\n([\s\S]*?)\r?\n(?:---|\+\+\+)[ \t]*(?:\r?\n|$)/.exec(text);
    if (!m) return { meta: null, body: text };
    return { meta: parseSimpleYaml(m[1]), body: text.slice(m[0].length) };
  }

  // Deliberately not a YAML parser: top-level scalars and lists are what front
  // matter in a note actually uses, and anything deeper is shown verbatim.
  function parseSimpleYaml(src) {
    var out = [];
    var lines = src.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line.trim() || /^\s*#/.test(line)) continue;
      var kv = /^([A-Za-z0-9_.\- ]+):\s*(.*)$/.exec(line);
      if (!kv) continue;
      var key = kv[1].trim();
      var value = kv[2].trim();
      if (!value) {
        var items = [];
        while (i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1])) {
          items.push(lines[++i].replace(/^\s*-\s+/, "").trim());
        }
        value = items.length ? items : "";
      } else if (/^\[.*\]$/.test(value)) {
        value = value.slice(1, -1).split(",").map(function (s) { return s.trim(); }).filter(Boolean);
      } else {
        value = value.replace(/^["'](.*)["']$/, "$1");
      }
      out.push([key, value]);
    }
    return out.length ? out : null;
  }

  function renderFrontMatter(meta) {
    if (!meta) return "";
    var rows = meta.map(function (pair) {
      var key = escapeHtml(pair[0]);
      var val = pair[1];
      var html = Array.isArray(val)
        ? val.map(function (v) { return '<span class="mdql-tag">' + escapeHtml(v) + "</span>"; }).join("")
        : escapeHtml(val);
      return "<dt>" + key + "</dt><dd>" + html + "</dd>";
    }).join("");
    return '<div class="mdql-frontmatter"><summary>front matter</summary><dl>' + rows + "</dl></div>";
  }

  /* ---------- markdown-it ---------- */

  function wikiLinkRule(state, silent) {
    var pos = state.pos;
    var src = state.src;
    var embed = src.charCodeAt(pos) === 0x21; /* ! */
    var start = embed ? pos + 1 : pos;
    if (src.charCodeAt(start) !== 0x5b || src.charCodeAt(start + 1) !== 0x5b) return false;
    // Bounded, so a document full of unclosed "[[" cannot turn the parse
    // quadratic by scanning to the end of the file each time.
    var window = src.slice(start + 2, start + 2 + 256);
    var offset = window.indexOf("]]");
    if (offset < 0) return false;
    var end = start + 2 + offset;
    var inner = window.slice(0, offset);
    if (inner.indexOf("\n") >= 0 || !inner.trim()) return false;

    if (!silent) {
      var parts = inner.split("|");
      var target = parts[0].trim();
      var label = (parts[1] || parts[0]).trim();
      var token;
      if (embed && /\.(png|jpe?g|gif|svg|webp|avif|heic|bmp)$/i.test(target)) {
        token = state.push("image", "img", 0);
        token.attrs = [["src", target], ["alt", ""]];
        token.content = label;
        token.children = [];
      } else {
        token = state.push("link_open", "a", 1);
        token.attrs = [["href", "#"], ["class", "mdql-wikilink"], ["data-wikilink", target]];
        state.push("text", "", 0).content = label;
        state.push("link_close", "a", -1);
      }
    }
    state.pos = end + 2;
    return true;
  }

  function slugify(text) {
    var slug = text.toLowerCase().trim().replace(/\s+/g, "-");
    try {
      // Keeps headings in any script addressable; \w alone would erase them.
      slug = slug.replace(/[^\p{L}\p{N}_-]+/gu, "");
    } catch (e) {
      slug = slug.replace(/[^\w-]+/g, "");
    }
    return slug;
  }

  function buildMarkdownIt(opts) {
    var md = window.markdownit({
      html: true,
      linkify: true,
      breaks: false,
      typographer: false
    });

    // Not markdown-it's `highlight` option: that keeps the <pre><code> wrapper
    // around whatever it returns, and a diagram needs its own container.
    md.renderer.rules.fence = function (tokens, idx) {
      var token = tokens[idx];
      var language = (token.info || "").trim().split(/\s+/)[0].toLowerCase();
      var code = token.content;

      if (language === "mermaid") {
        return '<div class="mdql-diagram" data-mermaid="pending"><pre class="mermaid">' +
          escapeHtml(code) + "</pre></div>\n";
      }
      if (opts.hljs && window.hljs) {
        try {
          var result = language && window.hljs.getLanguage(language)
            ? window.hljs.highlight(code, { language: language, ignoreIllegals: true })
            : window.hljs.highlightAuto(code);
          return '<pre><code class="hljs language-' + escapeHtml(result.language || language || "") +
            '">' + result.value + "</code></pre>\n";
        } catch (e) { /* fall through to plain */ }
      }
      return "<pre><code>" + escapeHtml(code) + "</code></pre>\n";
    };

    [
      "markdownitFootnote", "markdownitDeflist", "markdownitMark",
      "markdownitSub", "markdownitSup", "markdownitAbbr"
    ].forEach(function (name) {
      if (window[name]) md.use(window[name]);
    });
    if (window.markdownitTaskLists) {
      md.use(window.markdownitTaskLists, { enabled: true, label: true });
    }
    // Math has to be claimed during parsing. Left to a pass over the finished
    // DOM, the superscript and subscript plugins get to "x^2^" first and the
    // formula is already in pieces by then.
    if (opts.math && window.texmath && window.katex) {
      md.use(window.texmath, {
        engine: window.katex,
        delimiters: ["dollars", "brackets"],
        katexOptions: { throwOnError: false, output: "html", strict: false }
      });
    }

    md.inline.ruler.before("link", "mdql_wikilink", wikiLinkRule);

    var usedSlugs = {};
    md.renderer.rules.heading_open = function (tokens, idx, options, env, self) {
      var inline = tokens[idx + 1];
      var slug = slugify(inline && inline.content ? inline.content : "");
      if (slug) {
        usedSlugs[slug] = (usedSlugs[slug] || 0) + 1;
        tokens[idx].attrSet("id", usedSlugs[slug] > 1 ? slug + "-" + usedSlugs[slug] : slug);
      }
      return self.renderToken(tokens, idx, options);
    };

    return md;
  }

  /* ---------- DOM post-processing ---------- */

  // Raw HTML in the markdown is parsed into an inert document, where nothing
  // loads, and stripped before it is adopted into the page. Some of it would
  // otherwise reach the network before the content security policy gets a say:
  // <link rel="dns-prefetch"> leaks a lookup whatever the policy says.
  var FORBIDDEN_TAGS = "script, link, meta, base, iframe, frame, frameset, object, embed, applet, portal";
  var URL_ATTRIBUTES = ["href", "src", "xlink:href", "action", "formaction", "ping", "srcset", "data"];

  function toInertBody(html) {
    var parsed = new DOMParser().parseFromString("<!doctype html><body>" + html, "text/html");
    var forbidden = parsed.body.querySelectorAll(FORBIDDEN_TAGS);
    for (var i = 0; i < forbidden.length; i++) forbidden[i].remove();

    var elements = parsed.body.querySelectorAll("*");
    for (var j = 0; j < elements.length; j++) {
      var element = elements[j];
      var attributes = Array.prototype.slice.call(element.attributes);
      for (var k = 0; k < attributes.length; k++) {
        var name = attributes[k].name;
        var value = attributes[k].value || "";
        if (/^on/i.test(name)) {
          element.removeAttribute(name);
        } else if (URL_ATTRIBUTES.indexOf(name.toLowerCase()) >= 0 &&
                   /^\s*(javascript|vbscript|data):/i.test(value) &&
                   !/^\s*data:image\//i.test(value)) {
          element.removeAttribute(name);
        }
      }
    }
    return parsed.body;
  }



  var CALLOUT_ICONS = {
    note: '<svg width="14" height="14" viewBox="0 0 16 16"><path d="M0 8a8 8 0 1116 0A8 8 0 010 8zm8-6.5a6.5 6.5 0 100 13 6.5 6.5 0 000-13zM6.5 7.75A.75.75 0 017.25 7h1a.75.75 0 01.75.75v2.75h.25a.75.75 0 010 1.5h-2a.75.75 0 010-1.5h.25v-2h-.25a.75.75 0 01-.75-.75zM8 6a1 1 0 110-2 1 1 0 010 2z"/></svg>',
    tip: '<svg width="14" height="14" viewBox="0 0 16 16"><path d="M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 01-1.484.211c-.04-.282-.163-.547-.37-.847a8.69 8.69 0 00-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.197.232-.374.44-.542.681-.207.3-.33.565-.37.847a.75.75 0 11-1.484-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75zM6 15.25a.75.75 0 01.75-.75h2.5a.75.75 0 010 1.5h-2.5a.75.75 0 01-.75-.75zM5.75 12a.75.75 0 000 1.5h4.5a.75.75 0 000-1.5h-4.5z"/></svg>',
    important: '<svg width="14" height="14" viewBox="0 0 16 16"><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0114.25 13H8.06l-2.573 2.573A1.458 1.458 0 013 14.543V13H1.75A1.75 1.75 0 010 11.25zM9 9V4H7v5zm-1 3a1 1 0 100-2 1 1 0 000 2z"/></svg>',
    warning: '<svg width="14" height="14" viewBox="0 0 16 16"><path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0114.082 15H1.918a1.75 1.75 0 01-1.543-2.575zM9 11a1 1 0 10-2 0 1 1 0 002 0zm-.25-5.25a.75.75 0 00-1.5 0v2.5a.75.75 0 001.5 0z"/></svg>',
    caution: '<svg width="14" height="14" viewBox="0 0 16 16"><path d="M4.47.22A.75.75 0 015 0h6a.75.75 0 01.53.22l4.25 4.25c.141.14.22.331.22.53v6a.75.75 0 01-.22.53l-4.25 4.25A.75.75 0 0111 16H5a.75.75 0 01-.53-.22L.22 11.53A.75.75 0 010 11V5a.75.75 0 01.22-.53zM8 4a.75.75 0 00-.75.75v3.5a.75.75 0 001.5 0v-3.5A.75.75 0 008 4zm0 8a1 1 0 100-2 1 1 0 000 2z"/></svg>'
  };
  var CALLOUT_ALIASES = {
    info: "note", abstract: "note", summary: "note", todo: "note", question: "tip",
    help: "tip", hint: "tip", success: "tip", check: "tip", done: "tip",
    attention: "warning", failure: "caution", danger: "caution", error: "caution",
    bug: "caution", example: "important", quote: "note", cite: "note"
  };

  function upgradeCallouts(root) {
    var quotes = root.querySelectorAll("blockquote");
    for (var i = 0; i < quotes.length; i++) {
      var bq = quotes[i];
      var first = bq.firstElementChild;
      if (!first || first.tagName !== "P") continue;
      // The marker has to open the paragraph as plain text, and only that text
      // is consumed: markup following it on the same line stays in the body.
      var marker = first.firstChild;
      if (!marker || marker.nodeType !== 3) continue;
      var m = /^\s*\[!([A-Za-z]+)\]([+-])?[ \t]*([^\n]*)/.exec(marker.nodeValue);
      if (!m) continue;
      var raw = m[1].toLowerCase();
      var kind = CALLOUT_ICONS[raw] ? raw : (CALLOUT_ALIASES[raw] || "note");
      var title = m[3].trim() || m[1].charAt(0).toUpperCase() + m[1].slice(1).toLowerCase();

      marker.nodeValue = marker.nodeValue.slice(m[0].length).replace(/^\n/, "");
      if (!first.textContent.trim() && !first.children.length) first.remove();

      var box = document.createElement("div");
      box.className = "mdql-callout";
      box.setAttribute("data-kind", kind);
      box.innerHTML = '<div class="mdql-callout-title">' + CALLOUT_ICONS[kind] +
        "<span>" + escapeHtml(title) + "</span></div>";
      while (bq.firstChild) box.appendChild(bq.firstChild);
      bq.parentNode.replaceChild(box, bq);
    }
  }

  function neutraliseLinks(root) {
    root.addEventListener("click", function (event) {
      var anchor = event.target.closest ? event.target.closest("a") : null;
      if (!anchor) return;
      event.preventDefault();
      var href = anchor.getAttribute("href") || "";
      if (href.length > 1 && href.charAt(0) === "#") {
        var target = document.getElementById(href.slice(1));
        if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
        return;
      }
      // The preview itself never navigates; a real link is handed to the
      // default browser instead.
      if (/^(https?|mailto):/i.test(href) &&
          window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdqlOpen) {
        window.webkit.messageHandlers.mdqlOpen.postMessage(href);
      }
    });
  }

  function markMissingImages(root) {
    var images = root.querySelectorAll("img");
    return Promise.all(Array.prototype.map.call(images, function (img) {
      return new Promise(function (resolve) {
        function fail() {
          var note = document.createElement("span");
          note.className = "mdql-missing-asset";
          note.textContent = "missing image: " + (img.getAttribute("src") || "");
          if (img.parentNode) img.parentNode.replaceChild(note, img);
          resolve();
        }
        if (img.complete) { img.naturalWidth === 0 ? fail() : resolve(); return; }
        img.addEventListener("load", function () { resolve(); });
        img.addEventListener("error", fail);
      });
    }));
  }

  function renderDiagrams(root) {
    var blocks = root.querySelectorAll('.mdql-diagram[data-mermaid="pending"]');
    if (!blocks.length || !window.mermaid) return Promise.resolve();
    var dark = !!payload.dark;
    try {
      window.mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: dark ? "dark" : "default",
        fontFamily: 'ui-sans-serif, -apple-system, "SF Pro Text", sans-serif',
        flowchart: { htmlLabels: true, useMaxWidth: true },
        sequence: { useMaxWidth: true },
        gantt: { useMaxWidth: true }
      });
    } catch (e) { /* initialize is idempotent enough to ignore */ }

    var nodes = Array.prototype.map.call(blocks, function (b) { return b.querySelector("pre.mermaid"); });
    return window.mermaid.run({ nodes: nodes, suppressErrors: true })
      .catch(function () { /* per-node failures handled below */ })
      .then(function () {
        Array.prototype.forEach.call(blocks, function (block) {
          block.setAttribute("data-mermaid", "done");
          if (!block.querySelector("svg")) {
            var source = block.querySelector("pre.mermaid");
            var code = source ? source.textContent : "";
            block.classList.add("mdql-diagram-error");
            block.innerHTML = '<div class="reason">diagram could not be rendered</div><pre><code>' +
              escapeHtml(code) + "</code></pre>";
          }
        });
      });
  }

  /* ---------- entry point ---------- */

  function needs(source) {
    return {
      hljs: /(^|\n)\s*(```|~~~)/.test(source),
      mermaid: /(^|\n)\s*(```|~~~)\s*mermaid\b/i.test(source),
      katex: /\$\$[\s\S]+?\$\$|(^|[^\\$])\$[^$\n]+\$|\\\(|\\\[/.test(source)
    };
  }

  function ready(status) {
    document.documentElement.setAttribute("data-mdql-ready", status || "ok");
    var notice = document.getElementById("mdql-notice");
    if (notice && notices.length) notice.textContent = notices.join(" · ");
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdqlReady) {
      window.webkit.messageHandlers.mdqlReady.postMessage({
        status: status || "ok",
        height: document.body.scrollHeight,
        notices: notices
      });
    }
  }

  // Web fonts can stay pending indefinitely in an offscreen window, so give
  // them a short grace period rather than making the preview wait on them.
  function settled() {
    if (!document.fonts || !document.fonts.ready) return Promise.resolve();
    return Promise.race([
      document.fonts.ready.catch(function () {}),
      new Promise(function (resolve) { setTimeout(resolve, 600); })
    ]);
  }

  function run() {
    var split = splitFrontMatter(payload.markdown || "");
    var want = needs(split.body);
    var jobs = [];

    if (want.hljs) {
      jobs.push(
        loadStyle(vendor(payload.dark ? "highlight-github-dark.min.css" : "highlight-github.min.css"))
          .then(function () { return loadScript(vendor("highlight.min.js")); })
          .catch(function () { notices.push("syntax highlighting unavailable"); })
      );
    }
    if (want.katex) {
      jobs.push(
        Promise.all([loadStyle(vendor("katex/katex.min.css")), loadStyle(vendor("texmath.css"))])
          .then(function () { return loadScript(vendor("katex/katex.min.js")); })
          .then(function () { return loadScript(vendor("markdown-it-texmath.js")); })
          .catch(function () { notices.push("math unavailable"); })
      );
    }
    if (want.mermaid) {
      jobs.push(
        loadScript(vendor("mermaid/mermaid.min.js"))
          .catch(function () { notices.push("diagrams unavailable"); })
      );
    }

    Promise.all(jobs).then(function () {
      var md = buildMarkdownIt({ hljs: want.hljs, math: want.katex });
      content.innerHTML = renderFrontMatter(split.meta);
      var body = toInertBody(md.render(split.body));
      while (body.firstChild) content.appendChild(document.adoptNode(body.firstChild));
      upgradeCallouts(content);
      neutraliseLinks(content);
      Array.prototype.forEach.call(
        content.querySelectorAll('input[type="checkbox"]'),
        function (box) { box.setAttribute("disabled", "disabled"); }
      );
      return Promise.all([renderDiagrams(content), markMissingImages(content)]);
    }).then(function () {
      return settled();
    }).then(function () {
      // Not requestAnimationFrame: the thumbnail extension renders in a window
      // that was never ordered on screen, and frame callbacks never fire there.
      setTimeout(function () { ready("ok"); }, 0);
    }).catch(function (error) {
      content.innerHTML = '<div class="mdql-callout" data-kind="caution">' +
        '<div class="mdql-callout-title"><span>Could not render this file</span></div><pre><code>' +
        escapeHtml(String(error && error.message ? error.message : error)) + "</code></pre></div>";
      ready("error");
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
})();
