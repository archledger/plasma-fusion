// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Board render runtime for design/render/render.py.
//
// The boards (design/boards/*.dc.html) are design-canvas documents: their template language
// (x-dc, helmet, sc-for, sc-if, {{...}}, dc-import) and their scripts (a Component class with
// renderVals()) are meant for the authoring tool, whose runtime is not part of this repository.
// This file implements just enough of that language to render a board in a plain browser:
// render.py serves each board with this script in place of the tool's ./support.js, the runtime
// resolves the whole document once at DOMContentLoaded, and sets
// document.documentElement.dataset.boardRendered = "1" when it is done (the renderer waits on it).
//
// Supported, deliberately the features the boards use:
//   <helmet>            content moves into the document head
//   {{expr}}            interpolation in text nodes and attribute values; expressions see the
//                       board's renderVals() values, the enclosing sc-for item and the component
//                       props (evaluated with `with`, so any name is allowed)
//   <sc-for list="{{expr}}" as="name">   the inner content once per item
//   <sc-if value="{{expr}}">             the inner content, or nothing
//   <dc-import name="AppIcon" app=".." size="..">   another board as a component: its own
//                       renderVals() runs with the given props and its content is inserted
//   <script type="text/x-dc">           the Component class (extends DCLogic, renderVals())
(() => {
  "use strict";

  class DCLogic {
    constructor(props) {
      this.props = props || {};
    }
    renderVals() {
      return {};
    }
  }

  // A template expression that throws is a broken board, not an empty value: remember it so the
  // completion marker is never published (the renderer fails the board instead of writing a
  // partial preview).
  let evaluationFailed = false;

  function evalExpr(expr, scope) {
    try {
      return new Function("__scope", "with(__scope){ return (" + expr + "); }")(scope);
    } catch (e) {
      console.warn("render-runtime: cannot evaluate", JSON.stringify(expr), e.message);
      evaluationFailed = true;
      return "";
    }
  }

  function interp(text, scope) {
    if (text.indexOf("{{") === -1) {
      return text;
    }
    return text.replace(/\{\{([^}]*)\}\}/g, (_, expr) => {
      const v = evalExpr(expr.trim(), scope);
      return v === undefined || v === null ? "" : String(v);
    });
  }

  // A whole-attribute reference ("{{expr}}") keeps the expression's value (a list stays a list);
  // anything else interpolates to a string first.
  function resolveValue(text, scope) {
    const m = /^\s*\{\{([\s\S]*)\}\}\s*$/.exec(text || "");
    if (m) {
      return evalExpr(m[1].trim(), scope);
    }
    return evalExpr(interp(text || "", scope), scope);
  }

  function interpAttr(el, name, scope) {
    const v = el.getAttribute(name);
    return v === null ? v : interp(v, scope);
  }

  function renderVals(scriptEl, props) {
    if (!scriptEl) {
      return {};
    }
    try {
      const factory = new Function("DCLogic", scriptEl.textContent + "\nreturn Component;");
      return new (factory(DCLogic))(props).renderVals() || {};
    } catch (e) {
      console.warn("render-runtime: cannot run the component script", e);
      evaluationFailed = true;
      return {};
    }
  }

  function moveHelmet(container) {
    const helmet = container.querySelector("helmet");
    if (!helmet) {
      return;
    }
    const t = document.createElement("template");
    t.innerHTML = helmet.innerHTML;
    for (const n of Array.from(t.content.children)) {
      document.head.appendChild(n);
    }
    helmet.remove();
  }

  const importCache = new Map();

  async function expandImport(node, scope) {
    const name = node.getAttribute("name") || "";
    const props = {};
    for (const a of Array.from(node.attributes)) {
      if (a.name === "name" || a.name.startsWith("hint-")) {
        continue;
      }
      props[a.name] = interp(a.value, scope);
    }
    const file = "./" + name + ".dc.html";
    if (!importCache.has(file)) {
      importCache.set(file, fetch(file).then((r) => {
        if (!r.ok) {
          throw new Error(file + ": HTTP " + r.status);
        }
        return r.text();
      }));
    }
    const text = await importCache.get(file);
    const doc = new DOMParser().parseFromString(text, "text/html");
    moveHelmet(doc);
    const vals = renderVals(doc.querySelector('script[type="text/x-dc"]'), props);
    const content = doc.querySelector("x-dc");
    const holder = document.createElement("div");
    holder.innerHTML = content ? content.innerHTML : "";
    await processNode(holder, Object.assign(Object.create(null), vals, { props }));
    while (holder.firstChild) {
      node.parentNode.insertBefore(holder.firstChild, node);
    }
    node.remove();
  }

  async function expandFor(node, scope) {
    const list = resolveValue(node.getAttribute("list"), scope) || [];
    const asName = node.getAttribute("as") || "x";
    // Clone the original children: a sc-for may sit inside an <svg> (the AppIcon component's
    // extras layers), and reparsing innerHTML would put the clones in the HTML namespace, where
    // the browser does not draw them.
    const originals = Array.from(node.childNodes).map((n) => n.cloneNode(true));
    const parent = node.parentNode;
    for (const item of list) {
      const holder = document.createElement("div");
      for (const n of originals) {
        holder.appendChild(n.cloneNode(true));
      }
      await processNode(holder, Object.assign(Object.create(scope), { [asName]: item }));
      while (holder.firstChild) {
        parent.insertBefore(holder.firstChild, node);
      }
    }
    node.remove();
  }

  async function processNode(el, scope) {
    for (const a of Array.from(el.attributes || [])) {
      const v = interp(a.value, scope);
      if (v !== a.value) {
        el.setAttribute(a.name, v);
      }
    }
    let child = el.firstChild;
    while (child) {
      const next = child.nextSibling;
      if (child.nodeType === 3) {
        const s = interp(child.textContent, scope);
        if (s !== child.textContent) {
          child.textContent = s;
        }
      } else if (child.nodeType === 1) {
        const tag = child.tagName.toLowerCase();
        if (tag === "sc-for") {
          await expandFor(child, scope);
        } else if (tag === "sc-if") {
          const keep = !!resolveValue(child.getAttribute("value"), scope);
          if (keep) {
            await processNode(child, scope);
            const frag = document.createDocumentFragment();
            while (child.firstChild) {
              frag.appendChild(child.firstChild);
            }
            child.replaceWith(frag);
          } else {
            child.remove();
          }
        } else if (tag === "dc-import") {
          await expandImport(child, scope);
        } else {
          await processNode(child, scope);
        }
      }
      child = next;
    }
  }

  async function renderBoard() {
    const xdc = document.querySelector("x-dc");
    if (!xdc) {
      // A standalone board (plain HTML/CSS, like the tablet ones): nothing to resolve.
      document.documentElement.dataset.boardRendered = "1";
      return;
    }
    moveHelmet(document);
    const vals = renderVals(document.querySelector('script[type="text/x-dc"]'), {});
    await processNode(xdc, vals);
    if (evaluationFailed) {
      console.error("render-runtime: the board has expressions that did not evaluate");
      return;
    }
    document.documentElement.dataset.boardRendered = "1";
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => {
      renderBoard().catch((e) => console.error("render-runtime:", e));
    });
  } else {
    renderBoard().catch((e) => console.error("render-runtime:", e));
  }
})();
