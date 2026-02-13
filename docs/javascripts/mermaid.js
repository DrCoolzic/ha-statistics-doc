(function () {
  function getMermaidTheme() {
    // Detect MkDocs Material dark mode via the data-md-color-scheme attribute
    var scheme = document.body.getAttribute("data-md-color-scheme");
    if (scheme === "slate") return "dark";
    if (scheme === "default") return "default";
    // Fallback: check OS preference
    if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
      return "dark";
    }
    return "default";
  }

  function initMermaid() {
    if (typeof mermaid === "undefined") return;

    var theme = getMermaidTheme();

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: theme
    });

    // Reset processed diagrams so mermaid re-renders them
    var nodes = document.querySelectorAll(".mermaid");
    if (!nodes.length) return;

    nodes.forEach(function (node) {
      var original = node.getAttribute("data-original");
      if (original) {
        node.removeAttribute("data-processed");
        node.innerHTML = original;
      } else {
        node.setAttribute("data-original", node.textContent);
      }
    });

    mermaid.run({ nodes: Array.from(nodes) });
  }

  if (typeof document$ !== "undefined" && document$.subscribe) {
    document$.subscribe(function () {
      initMermaid();
    });
  } else {
    document.addEventListener("DOMContentLoaded", function () {
      initMermaid();
    });
  }

  // Re-render when the palette toggle is clicked
  var observer = new MutationObserver(function (mutations) {
    mutations.forEach(function (m) {
      if (m.attributeName === "data-md-color-scheme") {
        initMermaid();
      }
    });
  });
  // Observe body for scheme changes (Material toggles this attribute)
  if (document.body) {
    observer.observe(document.body, { attributes: true });
  } else {
    document.addEventListener("DOMContentLoaded", function () {
      observer.observe(document.body, { attributes: true });
    });
  }
})();
