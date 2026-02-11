import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"

const Hooks = {}

Hooks.Terminal = {
  mounted() {
    const paneId = this.el.dataset.paneId

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
      scrollback: 10000,
      theme: {
        background: "#1a1a2e",
        foreground: "#e0e0e0",
        cursor: "#64b5f6",
      },
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.loadAddon(new WebLinksAddon())

    // Wait for fonts to load so xterm.js measures character width correctly
    document.fonts.ready.then(() => {
      term.open(this.el)
      fitAddon.fit()
      this._connectChannel(term, paneId)
    })

    this._term = term
    this._fitAddon = fitAddon
    this._breakpointMap = null
    this._debugAnchors = null
    this._lastSyncedId = null
    this._showDebug = false

    this._onResize = () => fitAddon.fit()
    window.addEventListener("resize", this._onResize)

    this._onKeyDown = (e) => {
      if (e.ctrlKey && e.shiftKey && e.key === "D") {
        e.preventDefault()
        this._showDebug = !this._showDebug
        this._renderDebugOverlay()
        this.pushEvent("toggle_debug", {})
      }
    }
    window.addEventListener("keydown", this._onKeyDown)
  },

  _connectChannel(term, paneId) {
    const socket = new Socket("/socket", {})
    socket.connect()

    const channel = socket.channel(`terminal:${paneId}`, {})

    channel.on("output", ({ data }) => {
      term.write(data)
    })

    channel.join()
      .receive("ok", ({ initial_content }) => {
        if (initial_content) {
          term.write(initial_content)
        }
      })
      .receive("error", (resp) => {
        term.write(`\r\n\x1b[31mError connecting to pane: ${JSON.stringify(resp)}\x1b[0m\r\n`)
      })

    term.onData((data) => {
      channel.push("input", { data })
    })

    // Selection handling for annotations
    term.onSelectionChange(() => {
      const sel = term.getSelection()
      if (sel) {
        const pos = term.getSelectionPosition()
        if (pos) {
          this.pushEvent("text_selected", {
            text: sel,
            start_row: pos.start.y,
            start_col: pos.start.x,
            end_row: pos.end.y,
            end_col: pos.end.x,
          })
        }
      }
    })

    // Listen for highlight events from LiveView
    this.handleEvent("highlight_annotation", ({ start_row, start_col, end_row, end_col }) => {
      try {
        const length = start_row === end_row
          ? end_col - start_col
          : (term.cols - start_col) + end_col + (end_row - start_row - 1) * term.cols
        term.select(start_col, start_row, length)
        setTimeout(() => { term.clearSelection() }, 2000)
      } catch (_e) {
        // Graceful fallback if API unavailable
      }
    })

    // Breakpoint map from server (precomputed sync data)
    this.handleEvent("breakpoint_map", ({ entries }) => {
      this._breakpointMap = entries
    })

    // Debug anchor data from server
    this.handleEvent("debug_anchors", ({ anchors }) => {
      this._debugAnchors = anchors
      if (this._showDebug) this._renderDebugOverlay()
    })

    // Scroll sync: use breakpoint map for instant local lookup, fallback to server roundtrip
    let scrollTimeout = null
    term.onScroll(() => {
      clearTimeout(scrollTimeout)
      scrollTimeout = setTimeout(() => {
        const topLine = term.buffer.active.viewportY
        if (this._breakpointMap && this._breakpointMap.length > 0) {
          const messageId = this._lookupMessage(topLine)
          if (messageId && messageId !== this._lastSyncedId) {
            this._lastSyncedId = messageId
            const el = document.querySelector(`[data-message-id="${messageId}"]`)
            if (el) el.scrollIntoView({ behavior: "smooth", block: "center" })
          }
        } else {
          // Legacy fallback: send visible text to server
          const buffer = term.buffer.active
          const lines = []
          for (let i = buffer.viewportY; i < buffer.viewportY + term.rows; i++) {
            const line = buffer.getLine(i)
            if (line) lines.push(line.translateToString(true))
          }
          this.pushEvent("terminal_scrolled", { visible_text: lines.join("\n") })
        }
      }, 150)
    })

    // Listen for scroll_to_message events from LiveView
    this.handleEvent("scroll_to_message", ({ id }) => {
      const el = document.querySelector(`[data-message-id="${id}"]`)
      if (el) el.scrollIntoView({ behavior: "smooth", block: "center" })
    })

    this._channel = channel
    this._socket = socket
  },

  _lookupMessage(terminalLine) {
    const map = this._breakpointMap
    if (!map || map.length === 0) return null
    let lo = 0, hi = map.length - 1, result = map[0].id
    while (lo <= hi) {
      const mid = (lo + hi) >>> 1
      if (map[mid].t <= terminalLine) { result = map[mid].id; lo = mid + 1 }
      else { hi = mid - 1 }
    }
    return result
  },

  _renderDebugOverlay() {
    const existing = this.el.querySelector(".debug-anchor-overlay")
    if (existing) existing.remove()

    if (!this._showDebug) return

    const anchors = this._debugAnchors
    if (!anchors) return

    const overlay = document.createElement("div")
    overlay.className = "debug-anchor-overlay"
    overlay.style.cssText = "position:absolute;top:0;right:0;z-index:100;background:rgba(0,0,0,0.85);color:#e0e0e0;padding:8px;border-radius:0 0 0 6px;font-size:0.7em;max-height:200px;overflow-y:auto;"

    const typeColors = {
      tool_use: "#f0c674",
      user: "#7ec8e3",
      result: "#81c784",
      text: "#ce93d8",
    }

    const counts = {}
    for (const a of anchors) {
      counts[a.type] = (counts[a.type] || 0) + 1
    }

    let legend = `<div style="margin-bottom:4px;font-weight:bold;">Anchors: ${anchors.length} found</div>`
    for (const [type, count] of Object.entries(counts)) {
      const color = typeColors[type] || "#888"
      legend += `<span style="color:${color};margin-right:8px;">● ${type}: ${count}</span>`
    }
    overlay.innerHTML = legend

    this.el.style.position = "relative"
    this.el.appendChild(overlay)
  },

  destroyed() {
    window.removeEventListener("resize", this._onResize)
    window.removeEventListener("keydown", this._onKeyDown)
    if (this._channel) this._channel.leave()
    if (this._socket) this._socket.disconnect()
    if (this._term) this._term.dispose()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
