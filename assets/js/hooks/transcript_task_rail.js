const VALID_STATUSES = new Set(["pending", "in_progress", "completed"])
const ENTER_ANIMATION_MS = 280
const STATUS_ANIMATION_MS = 420
const LEAVE_ANIMATION_MS = 220
const JUMP_HIGHLIGHT_MS = 2000

function contractError(message) {
  return new Error(`[TranscriptTaskRail] ${message}`)
}

function assertContract(condition, message) {
  if (!condition) {
    throw contractError(message)
  }
}

export function parseTaskActions(rawValue) {
  const parsed = rawValue ? JSON.parse(rawValue) : []
  assertContract(Array.isArray(parsed), "data-task-actions must be a JSON array")

  return parsed.map((action, actionIndex) => {
    assertContract(action && typeof action === "object", `action ${actionIndex} must be an object`)

    const markerId = action.marker_id
    const toolUseId = action.tool_use_id
    const actionType = action.action_type
    const todos = action.todos

    assertContract(typeof markerId === "string" && markerId.length > 0, `action ${actionIndex} missing marker_id`)
    assertContract(typeof toolUseId === "string" && toolUseId.length > 0, `action ${actionIndex} missing tool_use_id`)
    assertContract(actionType === "replace", `action ${actionIndex} must use action_type=replace`)
    assertContract(Array.isArray(todos), `action ${actionIndex} todos must be an array`)

    return {
      marker_id: markerId,
      tool_use_id: toolUseId,
      action_type: actionType,
      todos: todos.map((todo, todoIndex) => normalizeTodo(todo, actionIndex, todoIndex)),
    }
  })
}

function normalizeTodo(todo, actionIndex, todoIndex) {
  assertContract(todo && typeof todo === "object", `action ${actionIndex} todo ${todoIndex} must be an object`)

  const id = todo.id
  const content = todo.content
  const status = todo.status

  assertContract(typeof id === "string" && id.length > 0, `action ${actionIndex} todo ${todoIndex} missing id`)
  assertContract(
    typeof content === "string" && content.length > 0,
    `action ${actionIndex} todo ${todoIndex} missing content`,
  )
  assertContract(
    typeof status === "string" && VALID_STATUSES.has(status),
    `action ${actionIndex} todo ${todoIndex} has invalid status`,
  )

  return { id, content, status }
}

export function deriveTaskState(actions, activeActionIndex) {
  if (!Array.isArray(actions) || actions.length === 0 || activeActionIndex < 0) {
    return { todos: [], updateIndex: 0, totalUpdates: Array.isArray(actions) ? actions.length : 0 }
  }

  const boundedIndex = Math.min(activeActionIndex, actions.length - 1)
  const action = actions[boundedIndex]

  return {
    todos: action.todos,
    updateIndex: boundedIndex + 1,
    totalUpdates: actions.length,
  }
}

function createTaskItemElement(todo) {
  const row = document.createElement("li")
  row.className = "task-rail-item"
  row.dataset.taskId = todo.id

  const dot = document.createElement("span")
  dot.className = "task-rail-status-dot"
  dot.setAttribute("aria-hidden", "true")

  const content = document.createElement("span")
  content.className = "task-rail-content"

  row.append(dot, content)
  updateTaskItemElement(row, todo)

  return row
}

function updateTaskItemElement(row, todo) {
  const previousStatus = row.dataset.status
  row.dataset.status = todo.status
  row.querySelector(".task-rail-content").textContent = todo.content
  row.setAttribute("aria-label", `${todo.status}: ${todo.content}`)

  if (previousStatus && previousStatus !== todo.status) {
    row.classList.remove("is-status-updated")
    void row.offsetWidth
    row.classList.add("is-status-updated")

    window.setTimeout(() => {
      row.classList.remove("is-status-updated")
    }, STATUS_ANIMATION_MS)
  }
}

const TranscriptTaskRail = {
  mounted() {
    this._scrollContainer = this.el.closest(".session-transcript")
    assertContract(this._scrollContainer, "hook root must be inside .session-transcript")

    this._listEl = this.el.querySelector("[data-task-rail-list]")
    this._countEl = this.el.querySelector("[data-task-rail-count]")
    this._subtitleEl = this.el.querySelector("[data-task-rail-subtitle]")

    assertContract(this._listEl, "missing [data-task-rail-list] element")
    assertContract(this._countEl, "missing [data-task-rail-count] element")
    assertContract(this._subtitleEl, "missing [data-task-rail-subtitle] element")

    this._taskRows = new Map()
    this._removalTimers = new Map()
    this._actions = []
    this._markerElements = new Map()
    this._activeActionIndex = Number.NaN
    this._rafId = null

    this._activeMarkerId = null

    this._onScroll = () => this._scheduleSyncFromScroll()
    this._scrollContainer.addEventListener("scroll", this._onScroll, { passive: true })
    window.addEventListener("resize", this._onScroll)

    this._onRailClick = (event) => this._handleRailClick(event)
    this._listEl.addEventListener("click", this._onRailClick)

    this._refreshActionsAndMarkers()
    this._syncFromScroll()
  },

  updated() {
    this._listEl = this.el.querySelector("[data-task-rail-list]")
    this._countEl = this.el.querySelector("[data-task-rail-count]")
    this._subtitleEl = this.el.querySelector("[data-task-rail-subtitle]")

    assertContract(this._listEl, "missing [data-task-rail-list] element after update")
    assertContract(this._countEl, "missing [data-task-rail-count] element after update")
    assertContract(this._subtitleEl, "missing [data-task-rail-subtitle] element after update")

    this._refreshActionsAndMarkers()
    this._activeActionIndex = Number.NaN
    this._scheduleSyncFromScroll()
  },

  destroyed() {
    if (this._rafId !== null) {
      window.cancelAnimationFrame(this._rafId)
    }

    if (this._onScroll) {
      this._scrollContainer.removeEventListener("scroll", this._onScroll)
      window.removeEventListener("resize", this._onScroll)
    }

    if (this._onRailClick && this._listEl) {
      this._listEl.removeEventListener("click", this._onRailClick)
    }

    for (const timerId of this._removalTimers.values()) {
      window.clearTimeout(timerId)
    }

    this._removalTimers.clear()
    this._taskRows.clear()
  },

  _refreshActionsAndMarkers() {
    this._actions = parseTaskActions(this.el.dataset.taskActions)
    this._markerElements = this._collectMarkerElements()

    for (let idx = 0; idx < this._actions.length; idx += 1) {
      const action = this._actions[idx]
      assertContract(
        this._markerElements.has(action.marker_id),
        `action ${idx} references missing marker ${action.marker_id}`,
      )
    }
  },

  _collectMarkerElements() {
    const markerElements = new Map()
    const markerRows = this.el.querySelectorAll("[data-marker-id]")

    for (const row of markerRows) {
      const markerId = row.dataset.markerId
      assertContract(typeof markerId === "string" && markerId.length > 0, "encountered invalid marker id")
      assertContract(!markerElements.has(markerId), `duplicate marker id detected: ${markerId}`)
      markerElements.set(markerId, row)
    }

    return markerElements
  },

  _scheduleSyncFromScroll() {
    if (this._rafId !== null) {
      return
    }

    this._rafId = window.requestAnimationFrame(() => this._syncFromScroll())
  },

  _syncFromScroll() {
    this._rafId = null

    if (this._actions.length === 0) {
      this._renderState({ todos: [], updateIndex: 0, totalUpdates: 0 })
      this._activeActionIndex = -1
      return
    }

    const railTop = this._scrollContainer.getBoundingClientRect().top
    const anchorY = railTop + Math.min(this._scrollContainer.clientHeight * 0.35, 220)

    let nextActionIndex = -1

    for (let idx = 0; idx < this._actions.length; idx += 1) {
      const markerEl = this._markerElements.get(this._actions[idx].marker_id)
      assertContract(markerEl, `missing marker element for action ${idx}`)

      if (markerEl.getBoundingClientRect().top <= anchorY) {
        nextActionIndex = idx
      } else {
        break
      }
    }

    if (nextActionIndex === this._activeActionIndex) {
      return
    }

    this._activeActionIndex = nextActionIndex
    this._activeMarkerId = nextActionIndex >= 0 ? this._actions[nextActionIndex].marker_id : null
    this._renderState(deriveTaskState(this._actions, nextActionIndex))
  },

  _renderState(state) {
    this._countEl.textContent = String(state.todos.length)

    if (state.totalUpdates === 0) {
      this._subtitleEl.textContent = "No task updates found in this transcript."
    } else if (state.updateIndex === 0) {
      this._subtitleEl.textContent = "Scroll down to reach the first task update."
    } else {
      this._subtitleEl.textContent = `Update ${state.updateIndex} of ${state.totalUpdates}`
    }

    this._syncTaskRows(state.todos)
  },

  _handleRailClick(event) {
    const item = event.target.closest(".task-rail-item")
    if (!item || !this._activeMarkerId) return

    const markerEl = this._markerElements.get(this._activeMarkerId)
    if (!markerEl) return

    markerEl.scrollIntoView({ behavior: "smooth", block: "center" })
    markerEl.classList.add("is-jump-highlight")
    window.setTimeout(() => markerEl.classList.remove("is-jump-highlight"), JUMP_HIGHLIGHT_MS)
  },

  _syncTaskRows(nextTodos) {
    const nextIds = new Set(nextTodos.map((todo) => todo.id))
    const fragment = document.createDocumentFragment()

    for (const todo of nextTodos) {
      const existingRemovalTimer = this._removalTimers.get(todo.id)
      if (existingRemovalTimer) {
        window.clearTimeout(existingRemovalTimer)
        this._removalTimers.delete(todo.id)
      }

      let row = this._taskRows.get(todo.id)

      if (!row) {
        row = createTaskItemElement(todo)
        row.classList.add("is-entering")

        window.setTimeout(() => {
          row.classList.remove("is-entering")
        }, ENTER_ANIMATION_MS)

        this._taskRows.set(todo.id, row)
      } else {
        updateTaskItemElement(row, todo)
      }

      fragment.appendChild(row)
    }

    this._listEl.appendChild(fragment)

    for (const [taskId, row] of this._taskRows.entries()) {
      if (nextIds.has(taskId)) {
        continue
      }

      row.classList.add("is-leaving")

      const timerId = window.setTimeout(() => {
        if (row.parentNode) {
          row.remove()
        }

        this._taskRows.delete(taskId)
        this._removalTimers.delete(taskId)
      }, LEAVE_ANIMATION_MS)

      this._removalTimers.set(taskId, timerId)
    }
  },
}

export default TranscriptTaskRail
