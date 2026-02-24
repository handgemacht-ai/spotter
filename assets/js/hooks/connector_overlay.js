/**
 * ConnectorOverlay — Phoenix LiveView hook for SVG connector lines and message drawer.
 *
 * Hover: draws a horizontal SVG line from sender badge to receiver cell.
 * Click: opens a compact drawer with message preview and "Jump to response" link.
 *
 * Listens on `.lanes-msg-link-badge` elements inside the grid.
 */

const DEBOUNCE_MS = 100

const ConnectorOverlay = {
  mounted() {
    this._hoverTimeout = null
    this._activeDrawerBadge = null

    this._onBadgeEnter = this._onBadgeEnter.bind(this)
    this._onBadgeLeave = this._onBadgeLeave.bind(this)
    this._onBadgeClick = this._onBadgeClick.bind(this)
    this._onDrawerClose = this._onDrawerClose.bind(this)
    this._onDrawerJump = this._onDrawerJump.bind(this)
    this._onClickOutside = this._onClickOutside.bind(this)
    this._onResize = this._onResize.bind(this)

    this._attachListeners()
    window.addEventListener("resize", this._onResize)
  },

  updated() {
    // Re-attach after LiveView patch
    this._attachListeners()
  },

  destroyed() {
    this._detachListeners()
    window.removeEventListener("resize", this._onResize)
    this._clearOverlay()
    this._hideDrawer()
  },

  _attachListeners() {
    // Detach first to avoid duplicates
    this._detachListeners()

    const grid = this._grid()
    if (!grid) return

    grid.addEventListener("mouseenter", this._onBadgeEnter, true)
    grid.addEventListener("mouseleave", this._onBadgeLeave, true)
    grid.addEventListener("click", this._onBadgeClick, true)

    const drawer = this._drawer()
    if (drawer) {
      const closeBtn = drawer.querySelector("[data-drawer-close]")
      if (closeBtn) closeBtn.addEventListener("click", this._onDrawerClose)

      const jumpBtn = drawer.querySelector("[data-drawer-jump]")
      if (jumpBtn) jumpBtn.addEventListener("click", this._onDrawerJump)
    }

    document.addEventListener("click", this._onClickOutside)
  },

  _detachListeners() {
    const grid = this._grid()
    if (grid) {
      grid.removeEventListener("mouseenter", this._onBadgeEnter, true)
      grid.removeEventListener("mouseleave", this._onBadgeLeave, true)
      grid.removeEventListener("click", this._onBadgeClick, true)
    }
    document.removeEventListener("click", this._onClickOutside)
  },

  _grid() {
    return document.querySelector("[data-testid='lanes-grid']")
  },

  _drawer() {
    return document.getElementById("lanes-message-drawer")
  },

  // --- Hover connector ---

  _onBadgeEnter(e) {
    const badge = e.target.closest(".lanes-msg-link-badge")
    if (!badge) return

    clearTimeout(this._hoverTimeout)
    this._hoverTimeout = setTimeout(() => {
      this._drawConnector(badge)
    }, DEBOUNCE_MS)
  },

  _onBadgeLeave(e) {
    const badge = e.target.closest(".lanes-msg-link-badge")
    if (!badge) return

    clearTimeout(this._hoverTimeout)
    this._clearOverlay()
    this._unhighlightAll()
  },

  _drawConnector(badge) {
    this._clearOverlay()

    const senderCell = badge.closest(".lanes-cell")
    if (!senderCell) return

    const direction = badge.dataset.linkDirection
    const peer = badge.dataset.linkPeer
    if (!peer) return

    // Find receiver cell: for sent links, find the peer agent's nearest cell
    // For received links, find the sender's message by UUID
    let receiverCell
    if (direction === "sent") {
      receiverCell = this._findPeerCell(senderCell, peer)
    } else {
      const senderUuid = badge.dataset.linkSenderUuid
      if (senderUuid) {
        receiverCell = document.querySelector(
          `.lanes-cell[data-msg-uuid="${CSS.escape(senderUuid)}"]`,
        )
      }
    }

    if (!receiverCell) return

    // Highlight receiver
    receiverCell.classList.add("lanes-cell-highlighted")

    // Draw SVG line
    const svg = this.el
    const gridRect = this._grid().getBoundingClientRect()
    const svgRect = svg.getBoundingClientRect()

    const senderRect = senderCell.getBoundingClientRect()
    const receiverRect = receiverCell.getBoundingClientRect()

    // Coordinates relative to SVG
    const x1 = senderRect.right - svgRect.left
    const y1 = senderRect.top + senderRect.height / 2 - svgRect.top
    const x2 = receiverRect.left - svgRect.left
    const y2 = receiverRect.top + receiverRect.height / 2 - svgRect.top

    // Size SVG to cover grid
    svg.style.width = `${gridRect.width}px`
    svg.style.height = `${gridRect.height}px`

    // Create line with arrowhead
    const ns = "http://www.w3.org/2000/svg"

    // Arrowhead marker
    const defs = document.createElementNS(ns, "defs")
    const marker = document.createElementNS(ns, "marker")
    marker.setAttribute("id", "connector-arrow")
    marker.setAttribute("viewBox", "0 0 10 10")
    marker.setAttribute("refX", "10")
    marker.setAttribute("refY", "5")
    marker.setAttribute("markerWidth", "8")
    marker.setAttribute("markerHeight", "8")
    marker.setAttribute("orient", "auto-start-reverse")
    const path = document.createElementNS(ns, "path")
    path.setAttribute("d", "M 0 0 L 10 5 L 0 10 z")
    path.setAttribute("fill", "var(--accent)")
    marker.appendChild(path)
    defs.appendChild(marker)
    svg.appendChild(defs)

    const line = document.createElementNS(ns, "line")
    line.setAttribute("x1", x1)
    line.setAttribute("y1", y1)
    line.setAttribute("x2", x2)
    line.setAttribute("y2", y2)
    line.setAttribute("class", "lanes-connector-line")
    line.setAttribute("marker-end", "url(#connector-arrow)")
    svg.appendChild(line)
  },

  _findPeerCell(senderCell, peerAgentName) {
    // Find the closest cell (in the same row or nearby) for the peer agent
    const row = senderCell.parentElement
    if (!row) return null

    // Look in sibling cells of the same row context
    const grid = this._grid()
    if (!grid) return null

    // Find all cells for the peer agent
    const peerCells = grid.querySelectorAll(
      `.lanes-cell[data-agent-name="${CSS.escape(peerAgentName)}"]`,
    )
    if (!peerCells.length) return null

    // Find the one closest vertically to the sender
    const senderRect = senderCell.getBoundingClientRect()
    let closest = null
    let closestDist = Infinity

    peerCells.forEach((cell) => {
      const rect = cell.getBoundingClientRect()
      const dist = Math.abs(
        rect.top + rect.height / 2 - (senderRect.top + senderRect.height / 2),
      )
      if (dist < closestDist) {
        closestDist = dist
        closest = cell
      }
    })

    return closest
  },

  _clearOverlay() {
    while (this.el.firstChild) {
      this.el.removeChild(this.el.firstChild)
    }
  },

  _unhighlightAll() {
    document
      .querySelectorAll(".lanes-cell-highlighted")
      .forEach((el) => el.classList.remove("lanes-cell-highlighted"))
  },

  // --- Click drawer ---

  _onBadgeClick(e) {
    const badge = e.target.closest(".lanes-msg-link-badge")
    if (!badge) return

    e.stopPropagation()

    const drawer = this._drawer()
    if (!drawer) return

    const direction = badge.dataset.linkDirection
    const peer = badge.dataset.linkPeer
    const preview = badge.dataset.linkPreview || ""

    // Store context for jump
    this._activeDrawerBadge = badge

    // Populate drawer
    drawer.querySelector("[data-drawer-direction]").textContent =
      direction === "sent" ? "Sent to" : "Received from"
    drawer.querySelector("[data-drawer-peer]").textContent = peer || ""
    drawer.querySelector("[data-drawer-preview]").textContent =
      preview || "(no preview)"

    // Show jump button only for sent links
    const jumpBtn = drawer.querySelector("[data-drawer-jump]")
    if (jumpBtn) {
      jumpBtn.style.display = direction === "sent" ? "block" : "none"
    }

    // Position drawer below the badge
    const badgeRect = badge.getBoundingClientRect()
    const containerRect = this.el
      .closest(".lanes-container")
      .getBoundingClientRect()

    drawer.style.display = "block"
    drawer.style.top = `${badgeRect.bottom - containerRect.top + 4}px`
    drawer.style.left = `${Math.max(badgeRect.left - containerRect.left, 8)}px`
  },

  _onDrawerClose() {
    this._hideDrawer()
  },

  _onDrawerJump() {
    if (!this._activeDrawerBadge) return

    const peer = this._activeDrawerBadge.dataset.linkPeer
    const senderUuid = this._activeDrawerBadge.dataset.linkSenderUuid
    const direction = this._activeDrawerBadge.dataset.linkDirection

    let targetCell
    if (direction === "sent" && peer) {
      const senderCell = this._activeDrawerBadge.closest(".lanes-cell")
      targetCell = this._findPeerCell(senderCell, peer)
    } else if (senderUuid) {
      targetCell = document.querySelector(
        `.lanes-cell[data-msg-uuid="${CSS.escape(senderUuid)}"]`,
      )
    }

    if (targetCell) {
      targetCell.scrollIntoView({ behavior: "smooth", block: "center" })
      targetCell.classList.add("lanes-cell-highlighted")
      setTimeout(
        () => targetCell.classList.remove("lanes-cell-highlighted"),
        2000,
      )
    }

    this._hideDrawer()
  },

  _onClickOutside(e) {
    const drawer = this._drawer()
    if (!drawer || drawer.style.display === "none") return

    if (!drawer.contains(e.target) && !e.target.closest(".lanes-msg-link-badge")) {
      this._hideDrawer()
    }
  },

  _hideDrawer() {
    const drawer = this._drawer()
    if (drawer) drawer.style.display = "none"
    this._activeDrawerBadge = null
  },

  _onResize() {
    this._clearOverlay()
    this._hideDrawer()
  },
}

export default ConnectorOverlay
