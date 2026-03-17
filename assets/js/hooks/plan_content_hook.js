import hljs from "highlight.js/lib/core"

const PlanContentHook = {
  mounted() {
    this._highlightCode()
    this._setupSelection()
  },
  updated() {
    this._highlightCode()
  },
  destroyed() {
    if (this._selectionHandler) {
      document.removeEventListener("mouseup", this._selectionHandler)
    }
  },

  _highlightCode() {
    this.el.querySelectorAll('pre code[class*="language-"]').forEach((block) => {
      if (block.dataset.hljs === "done") return
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    })
  },

  _setupSelection() {
    this._selectionHandler = () => {
      try {
        const sel = window.getSelection()
        if (!sel || sel.isCollapsed || !sel.toString().trim()) {
          this.pushEvent("plan_text_selected", { selected_text: "", section: "" })
          return
        }

        const anchor = sel.anchorNode?.parentElement
        if (anchor?.closest("[data-mermaid-rendered]")) return

        const range = sel.getRangeAt(0)
        if (!this.el.contains(range.startContainer) && !this.el.contains(range.endContainer)) {
          this.pushEvent("clear_selection", {})
          return
        }

        const section = anchor?.closest("[data-plan-section]")
        const sectionName = section?.dataset?.planSection || ""

        this.pushEvent("plan_text_selected", {
          selected_text: sel.toString().trim(),
          section: sectionName,
        })
      } catch (_e) {
        // Fail-safe: never throw from selection capture
      }
    }
    document.addEventListener("mouseup", this._selectionHandler)
  },
}

export default PlanContentHook
