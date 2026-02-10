import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { Terminal } from "@xterm/xterm"
import { WebLinksAddon } from "@xterm/addon-web-links"

const Hooks = {}

Hooks.Terminal = {
  mounted() {
    const paneId = this.el.dataset.paneId
    const cols = parseInt(this.el.dataset.cols) || 80
    const rows = parseInt(this.el.dataset.rows) || 24

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
      cols,
      rows,
      theme: {
        background: "#1a1a2e",
        foreground: "#e0e0e0",
        cursor: "#64b5f6",
      },
    })

    term.loadAddon(new WebLinksAddon())
    term.open(this.el)

    // Connect to terminal channel
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

    // Forward input to tmux
    term.onData((data) => {
      channel.push("input", { data })
    })

    this._term = term
    this._channel = channel
    this._socket = socket
  },

  destroyed() {
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
