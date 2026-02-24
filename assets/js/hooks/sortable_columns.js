import Sortable from "sortablejs"

/**
 * SortableColumns — Phoenix LiveView hook for drag-and-drop lane column reordering.
 *
 * Attaches SortableJS to a wrapper around the agent header cells in the lanes grid.
 * On drop: pushes `reorder_lanes` event with new session_id order.
 * Persists column order to localStorage keyed by session ID.
 *
 * Expected DOM structure:
 *   <div id="lane-headers" phx-hook="SortableColumns" data-session-id="...">
 *     <div data-lane-session-id="sid1" data-lane-col-index="0">...</div>
 *     <div data-lane-session-id="sid2" data-lane-col-index="1">...</div>
 *   </div>
 */
const STORAGE_PREFIX = "spotter:lane-order:"

function storageKey(sessionId) {
  return `${STORAGE_PREFIX}${sessionId}`
}

function saveOrder(sessionId, order) {
  try {
    localStorage.setItem(storageKey(sessionId), JSON.stringify(order))
  } catch (_e) {
    // localStorage unavailable — silent fallback
  }
}

function loadOrder(sessionId) {
  try {
    const raw = localStorage.getItem(storageKey(sessionId))
    if (raw) return JSON.parse(raw)
  } catch (_e) {
    // localStorage unavailable or corrupt — silent fallback
  }
  return null
}

function clearOrder(sessionId) {
  try {
    localStorage.removeItem(storageKey(sessionId))
  } catch (_e) {
    // silent
  }
}

const SortableColumns = {
  mounted() {
    this._sessionId = this.el.dataset.sessionId
    this._initSortable()
    this._applySavedOrder()

    // Listen for reset event from server
    this.handleEvent("reset_column_order", () => {
      if (this._sessionId) clearOrder(this._sessionId)
    })
  },

  updated() {
    if (this._sortable) {
      const headers = this.el.querySelectorAll("[data-lane-session-id]")
      this._sortable.option("disabled", headers.length <= 1)
    }
  },

  destroyed() {
    if (this._sortable) {
      this._sortable.destroy()
      this._sortable = null
    }
  },

  _initSortable() {
    const headers = this.el.querySelectorAll("[data-lane-session-id]")

    this._sortable = Sortable.create(this.el, {
      animation: 200,
      easing: "cubic-bezier(0.25, 1, 0.5, 1)",
      ghostClass: "lanes-col-ghost",
      chosenClass: "lanes-col-chosen",
      dragClass: "lanes-col-drag",
      disabled: headers.length <= 1,
      direction: "horizontal",
      handle: ".lanes-drag-handle",
      onStart: () => {
        this.el.classList.add("lanes-dragging")
      },
      onEnd: () => {
        this.el.classList.remove("lanes-dragging")

        const ordered = Array.from(
          this.el.querySelectorAll("[data-lane-session-id]"),
        ).map((el) => el.dataset.laneSessionId)

        // Persist to localStorage
        if (this._sessionId) saveOrder(this._sessionId, ordered)

        // Push to server
        this.pushEvent("reorder_lanes", { order: ordered })
      },
    })
  },

  _applySavedOrder() {
    if (!this._sessionId) return

    const saved = loadOrder(this._sessionId)
    if (!saved || !Array.isArray(saved)) return

    // Check if saved order matches current headers
    const current = Array.from(
      this.el.querySelectorAll("[data-lane-session-id]"),
    ).map((el) => el.dataset.laneSessionId)

    // Only apply if same set of session IDs (order may differ)
    const savedSet = new Set(saved)
    const currentSet = new Set(current)
    if (
      savedSet.size !== currentSet.size ||
      ![...savedSet].every((id) => currentSet.has(id))
    ) {
      clearOrder(this._sessionId) // stale — clear it
      return
    }

    // If already in the right order, skip
    if (JSON.stringify(saved) === JSON.stringify(current)) return

    // Push reorder event to apply saved order
    this.pushEvent("reorder_lanes", { order: saved })
  },
}

export default SortableColumns
