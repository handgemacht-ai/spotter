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

    this._onResize = () => fitAddon.fit()
    window.addEventListener("resize", this._onResize)
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
    // Scroll sync: debounced terminal scroll → push visible text to LiveView
    let scrollTimeout = null
    term.onScroll(() => {
      clearTimeout(scrollTimeout)
      scrollTimeout = setTimeout(() => {
        const buffer = term.buffer.active
        const lines = []
        for (let i = buffer.viewportY; i < buffer.viewportY + term.rows; i++) {
          const line = buffer.getLine(i)
          if (line) lines.push(line.translateToString(true))
        }
        this.pushEvent("terminal_scrolled", { visible_text: lines.join("\n") })
      }, 300)
    })

    // Listen for scroll_to_message events from LiveView
    this.handleEvent("scroll_to_message", ({ id }) => {
      const el = document.querySelector(`[data-message-id="${id}"]`)
      if (el) el.scrollIntoView({ behavior: "smooth", block: "center" })
    })

    this._channel = channel
    this._socket = socket
  },

  destroyed() {
    window.removeEventListener("resize", this._onResize)
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
