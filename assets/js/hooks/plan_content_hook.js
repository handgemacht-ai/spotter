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
      this.el.removeEventListener("mouseup", this._selectionHandler)
    }
    if (this._keyupHandler) {
      this.el.removeEventListener("keyup", this._keyupHandler)
    }
  },

  _highlightCode() {
    const blocks = this.el.querySelectorAll('pre code[class*="language-"]')
    for (const block of blocks) {
      if (block.dataset.hljs === "done") continue
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    }
  },

  _setupSelection() {
    this._selectionHandler = () => {
      try {
        const sel = window.getSelection()
        if (!sel || sel.isCollapsed || !sel.toString().trim()) {
          this.pushEvent("clear_selection", {})
          return
        }

        const anchor = sel.anchorNode?.parentElement
        const focus = sel.focusNode?.parentElement
        if (anchor?.closest("[data-mermaid-rendered]") || focus?.closest("[data-mermaid-rendered]")) return

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
    this.el.addEventListener("mouseup", this._selectionHandler)
    this._keyupHandler = (e) => {
      if (e.shiftKey) this._selectionHandler()
    }
    this.el.addEventListener("keyup", this._keyupHandler)
  },
}

export default PlanContentHook
