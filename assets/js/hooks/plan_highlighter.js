/**
 * PlanHighlighter — Phoenix LiveView hook for text selection on plan content.
 *
 * Detects text selection within the plan sections container and pushes
 * the selected text + section context to the LiveView for annotation creation.
 */

const PlanHighlighter = {
  mounted() {
    this._onMouseUp = () => this._pushSelection()
    this._onKeyUp = (e) => {
      if (e.shiftKey) this._pushSelection()
    }
    this.el.addEventListener("mouseup", this._onMouseUp)
    this.el.addEventListener("keyup", this._onKeyUp)
  },

  destroyed() {
    if (this._onMouseUp) this.el.removeEventListener("mouseup", this._onMouseUp)
    if (this._onKeyUp) this.el.removeEventListener("keyup", this._onKeyUp)
  },

  _pushSelection() {
    try {
      const selection = window.getSelection()
      if (!selection || selection.isCollapsed) {
        this.pushEvent("clear_selection", {})
        return
      }

      const text = selection.toString().trim()
      if (!text) {
        this.pushEvent("clear_selection", {})
        return
      }

      const range = selection.getRangeAt(0)
      if (
        !this.el.contains(range.startContainer) &&
        !this.el.contains(range.endContainer)
      ) {
        this.pushEvent("clear_selection", {})
        return
      }

      const section =
        range.startContainer.parentElement?.closest("[data-plan-section]")
      const sectionName = section?.dataset?.planSection || null

      this.pushEvent("plan_text_selected", {
        selected_text: text,
        section: sectionName,
      })
    } catch (_e) {
      // Fail-safe: never throw from selection capture
    }
  },
}

export default PlanHighlighter
