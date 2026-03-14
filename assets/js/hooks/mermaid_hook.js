/**
 * MermaidHook — Phoenix LiveView hook for rendering Mermaid diagrams.
 *
 * Lazy-loads mermaid.js via dynamic import() to avoid bloating the main bundle.
 * Each hook instance is attached to a single element with [data-mermaid-source]
 * and renders it as SVG with a dark theme.
 */
import DOMPurify from "dompurify"

let mermaidInstance = null

async function getMermaid() {
  if (!mermaidInstance) {
    const { default: mermaid } = await import("mermaid")
    mermaid.initialize({
      startOnLoad: false,
      theme: "dark",
      themeVariables: {
        primaryColor: "#3b82f6",
        primaryTextColor: "#e2e8f0",
        primaryBorderColor: "#475569",
        lineColor: "#64748b",
        secondaryColor: "#1e293b",
        tertiaryColor: "#0f172a",
      },
    })
    mermaidInstance = mermaid
  }
  return mermaidInstance
}

const MermaidHook = {
  mounted() {
    this._render()
  },

  updated() {
    delete this.el.dataset.mermaidRendered
    this._render()
  },

  async _render() {
    const source = this.el.dataset.mermaidSource
    if (!source || this.el.dataset.mermaidRendered === "done") return

    try {
      const mermaid = await getMermaid()
      const id = `mermaid-${crypto.randomUUID()}`
      const { svg } = await mermaid.render(id, source)
      this.el.innerHTML = DOMPurify.sanitize(svg, {
        USE_PROFILES: { svg: true, svgFilters: true },
      })
      this.el.dataset.mermaidRendered = "done"
    } catch (err) {
      console.warn("[MermaidHook] Failed to render diagram:", err)
    }
  },
}

export default MermaidHook
