import Sortable from "sortablejs"

/**
 * LaneDrag — Phoenix LiveView hook for drag-and-drop lane tab reordering.
 *
 * Attaches SortableJS to the lane tab bar container. On drag end, pushes
 * a "reorder_lanes" event with the new session_id order to the server.
 *
 * Disabled when there is only one tab (nothing to reorder).
 */
const LaneDrag = {
  mounted() {
    this._initSortable()
  },

  updated() {
    // Re-check tab count after LiveView patches (lanes may have been added/removed)
    if (this._sortable) {
      const tabs = this.el.querySelectorAll("[data-lane-session-id]")
      this._sortable.option("disabled", tabs.length <= 1)
    }
  },

  destroyed() {
    if (this._sortable) {
      this._sortable.destroy()
      this._sortable = null
    }
  },

  _initSortable() {
    const tabs = this.el.querySelectorAll("[data-lane-session-id]")

    this._sortable = Sortable.create(this.el, {
      animation: 150,
      ghostClass: "lanes-tab-ghost",
      chosenClass: "lanes-tab-chosen",
      dragClass: "lanes-tab-drag",
      disabled: tabs.length <= 1,
      direction: "horizontal",
      onEnd: (_evt) => {
        const ordered = Array.from(
          this.el.querySelectorAll("[data-lane-session-id]"),
        ).map((el) => el.dataset.laneSessionId)

        this.pushEvent("reorder_lanes", { order: ordered })
      },
    })
  },
}

export default LaneDrag
