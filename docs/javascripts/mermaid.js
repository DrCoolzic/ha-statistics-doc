(function () {
  function initMermaid() {
    if (typeof mermaid === "undefined") return;

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "default"
    });

    const nodes = document.querySelectorAll(".mermaid");
    if (!nodes.length) return;

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
})();
