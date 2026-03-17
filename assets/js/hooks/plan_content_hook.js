import hljs from "highlight.js/lib/core"

/**
 * Convert a position in the whitespace-normalized string back to the
 * corresponding raw offset in `text`. Whitespace runs in `text` collapse
 * to single characters in normalized space (matching `str.replace(/\s+/g, " ")`).
 */
function normalizedToRaw(text, normalizedPos) {
  let raw = 0
  let norm = 0
  while (norm < normalizedPos && raw < text.length) {
    if (/\s/.test(text[raw])) {
      while (raw + 1 < text.length && /\s/.test(text[raw + 1])) {
        raw++
      }
    }
    raw++
    norm++
  }
  return raw
}

const PlanContentHook = {
  mounted() {
    this._highlightCode()
    this._applyAnnotations()
    this._setupSelection()
  },
  updated() {
    this._highlightCode()
    const raw = this.el.dataset.annotations
    if (raw !== this._lastAnnotationsRaw) {
      this._applyAnnotations()
    }
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

  _applyAnnotations() {
    const raw = this.el.dataset.annotations
    this._lastAnnotationsRaw = raw
    if (!raw) return

    const annotations = JSON.parse(raw)
    if (!annotations.length) return

    this.el.querySelectorAll(".bead-annotation-highlight").forEach((m) => m.replaceWith(...m.childNodes))

    const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null, false)

    for (const ann of annotations) {
      const needle = ann.selected_text.replace(/\s+/g, " ").trim()
      if (!needle) continue

      walker.currentNode = this.el
      let node
      while ((node = walker.nextNode())) {
        if (node.parentElement.closest(".bead-annotation-highlight")) continue

        const normalized = node.textContent.replace(/\s+/g, " ")
        const matchIndex = normalized.indexOf(needle)
        if (matchIndex === -1) continue

        const startOffset = normalizedToRaw(node.textContent, matchIndex)
        const endOffset = normalizedToRaw(node.textContent, matchIndex + needle.length)

        const range = document.createRange()
        range.setStart(node, startOffset)
        range.setEnd(node, endOffset)

        const mark = document.createElement("mark")
        mark.className = "bead-annotation-highlight"
        mark.dataset.annotationId = ann.id
        mark.title = ann.comment || ""
        mark.addEventListener("click", () => {
          mark.classList.add("bead-annotation-pulse")
          setTimeout(() => mark.classList.remove("bead-annotation-pulse"), 1500)
          mark.scrollIntoView({ behavior: "smooth", block: "center" })
          this.pushEvent("highlight_annotation", { id: ann.id })
        })

        try {
          range.surroundContents(mark)
        } catch (_e) {
          // Range spans multiple elements — skip gracefully
        }
        break
      }
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
