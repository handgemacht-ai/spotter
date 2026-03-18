import hljs from "highlight.js/lib/core"

const FolderContentHook = {
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

        if (
          anchor?.closest("[data-mermaid-rendered]") ||
          focus?.closest("[data-mermaid-rendered]")
        ) {
          return
        }

        const range = sel.getRangeAt(0)
        if (
          !this.el.contains(range.startContainer) &&
          !this.el.contains(range.endContainer)
        ) {
          this.pushEvent("clear_selection", {})
          return
        }

        const section =
          range.startContainer.closest
            ? range.startContainer.closest("[data-file-path]")
            : range.startContainer.parentElement?.closest("[data-file-path]")

        if (!section) return

        const filePath = section.dataset.filePath
        const text = sel.toString().trim()
        if (!text) return

        const preRange = document.createRange()
        preRange.setStart(section, 0)
        preRange.setEnd(range.startContainer, range.startOffset)
        const lineStart =
          (preRange.toString().match(/\n/g) || []).length + 1

        const fullRange = document.createRange()
        fullRange.setStart(section, 0)
        fullRange.setEnd(range.endContainer, range.endOffset)
        const lineEnd =
          (fullRange.toString().match(/\n/g) || []).length + 1

        this.pushEvent("folder_text_selected", {
          file_path: filePath,
          selected_text: text,
          line_start: lineStart,
          line_end: lineEnd,
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

export default FolderContentHook
