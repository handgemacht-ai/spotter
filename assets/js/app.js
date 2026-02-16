import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import hljs from "highlight.js/lib/core"
import elixir from "highlight.js/lib/languages/elixir"
import javascript from "highlight.js/lib/languages/javascript"
import bash from "highlight.js/lib/languages/bash"
import json from "highlight.js/lib/languages/json"
import diff from "highlight.js/lib/languages/diff"
import plaintext from "highlight.js/lib/languages/plaintext"
import { marked } from "marked"
import DOMPurify from "dompurify"
import { createFlowGraphHook } from "./flow_graph"
import { initGlobalSearchPalette } from "./global_search_palette"

hljs.registerLanguage("elixir", elixir)
hljs.registerLanguage("javascript", javascript)
hljs.registerLanguage("bash", bash)
hljs.registerLanguage("json", json)
hljs.registerLanguage("diff", diff)
hljs.registerLanguage("plaintext", plaintext)

function highlightTranscriptCode(rootEl) {
  const blocks = rootEl.querySelectorAll('[data-render-mode="code"] code')
  for (const block of blocks) {
    if (block.dataset.hljs === "done") continue
    hljs.highlightElement(block)
    block.dataset.hljs = "done"
  }
}

function renderTranscriptMarkdown(rootEl) {
  const rows = rootEl.querySelectorAll('[data-render-markdown="true"]')
  for (const row of rows) {
    if (row.dataset.mdSource === undefined) {
      row.dataset.mdSource = row.textContent || ""
    }

    if (row.dataset.mdRendered === "done") continue

    const markdownSource = row.dataset.mdSource
    const rendered = marked.parseInline(markdownSource, { gfm: true, breaks: true })
    row.innerHTML = DOMPurify.sanitize(rendered)
    row.dataset.mdRendered = "done"
  }
}

function pulseClass(el, className, durationMs = 650) {
  if (!el) return

  // Remove + force reflow so CSS animation reliably restarts.
  el.classList.remove(className)
  void el.offsetWidth

  el.classList.add(className)
  window.setTimeout(() => el.classList.remove(className), durationMs)
}

// Shared socket instance for all channel connections
let sharedSocket = null
function getSharedSocket() {
  if (!sharedSocket) {
    sharedSocket = new Socket("/socket", {})
    sharedSocket.connect()
  }
  return sharedSocket
}

// Live review badge updates via reviews:counts channel
function initReviewsBadge() {
  const badge = document.querySelector("[data-reviews-badge]")
  if (!badge) return

  const socket = getSharedSocket()
  const channel = socket.channel("reviews:counts", {})

  function updateBadge(totalOpenCount) {
    if (totalOpenCount > 0) {
      badge.textContent = totalOpenCount
      badge.style.display = ""
    } else {
      badge.textContent = "0"
      badge.style.display = "none"
    }
  }

  channel.on("counts_updated", ({ total_open_count }) => {
    updateBadge(total_open_count)
  })

  channel.join()
    .receive("ok", ({ total_open_count }) => {
      updateBadge(total_open_count)
    })
}

initReviewsBadge()
initGlobalSearchPalette()

const Hooks = {}

Hooks.FlowGraph = createFlowGraphHook()

Hooks.BrowserTimezone = {
  mounted() {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
    this.pushEvent("browser_timezone", { timezone: tz })
  },
}

Hooks.StudyCard = {
  mounted() {
    this._currentCardId = this._getCardId()
    this._animateEntrance()
    this._highlightCode()
  },

  beforeUpdate() {
    this._previousCardId = this._getCardId()
  },

  updated() {
    const newCardId = this._getCardId()
    if (newCardId && newCardId !== this._previousCardId) {
      this._currentCardId = newCardId
      this._animateEntrance()
    }
    this._highlightCode()
  },

  _highlightCode() {
    const blocks = this.el.querySelectorAll("pre code[class*='language-']")
    for (const block of blocks) {
      if (block.dataset.hljs === "done") continue
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    }
  },

  _getCardId() {
    const card = this.el.querySelector('[data-card-id]')
    return card ? card.dataset.cardId : null
  },

  _animateEntrance() {
    const card = this.el.querySelector('.study-card')
    if (!card) return

    card.classList.remove('study-card-enter-active', 'is-exiting')
    card.classList.add('study-card-enter')

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        card.classList.add('study-card-enter-active')
      })
    })

    card.addEventListener('transitionend', () => {
      card.classList.remove('study-card-enter', 'study-card-enter-active')
    }, { once: true })
  },
}

Hooks.StudyProgress = {
  mounted() {
    this._previousCount = this._getCurrentCount()
  },

  updated() {
    const currentCount = this._getCurrentCount()
    if (currentCount !== this._previousCount && this._previousCount !== null) {
      this._animateCount(this._previousCount, currentCount)
    }
    this._previousCount = currentCount
  },

  _getCurrentCount() {
    const el = this.el.querySelector('.study-progress-number')
    return el ? parseInt(el.textContent, 10) : null
  },

  _animateCount(from, to) {
    const el = this.el.querySelector('.study-progress-number')
    if (!el || from === to) return

    const duration = 400
    const startTime = performance.now()

    const animate = (currentTime) => {
      const elapsed = currentTime - startTime
      const progress = Math.min(elapsed / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      const current = Math.round(from + (to - from) * eased)

      el.textContent = current

      if (progress < 1) {
        requestAnimationFrame(animate)
      } else {
        el.textContent = to
      }
    }

    requestAnimationFrame(animate)
  },
}

Hooks.PreserveScroll = {
  mounted() {
    this._lastKey = this.el.dataset.scrollKey || ""
    this._scrollTop = this.el.scrollTop
    this._wasNearBottom = false
    this._onScroll = () => {
      const el = this.el
      this._scrollTop = el.scrollTop
      this._wasNearBottom =
        el.scrollTop + el.clientHeight >= el.scrollHeight - 24
    }
    this.el.addEventListener("scroll", this._onScroll)
  },
  updated() {
    const newKey = this.el.dataset.scrollKey || ""
    if (newKey !== this._lastKey) {
      this.el.scrollTop = 0
      this._lastKey = newKey
      return
    }
    if (this._wasNearBottom) {
      this.el.scrollTop = this.el.scrollHeight
    } else {
      this.el.scrollTop = this._scrollTop
    }
  },
  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
  },
}

Hooks.TranscriptHighlighter = {
  mounted() {
    renderTranscriptMarkdown(this.el)
    highlightTranscriptCode(this.el)
    this._highlightDebugJson()

    // Sidebar UX: when selection is made outside the annotations panel,
    // SessionLive auto-switches to the Annotations tab and emits an attention event.
    this.handleEvent("annotations_attention", () => {
      const tick = (remaining) => {
        pulseClass(document.getElementById("sidebar-tab-annotations"), "is-attention", 550)

        const sidebar = document.querySelector(".session-sidebar, .file-detail-sidebar")
        if (!sidebar) return

        const editor = sidebar.querySelector(".annotation-form")
        const panel = sidebar.querySelector(".sidebar-tab-content")

        if (editor || panel || remaining <= 0) {
          pulseClass(editor || panel, "is-attention", 700)
        } else {
          requestAnimationFrame(() => tick(remaining - 1))
        }
      }

      // Allow the LiveView DOM patch (tab switch + editor insertion) to land.
      requestAnimationFrame(() => tick(2))
    })

    // Scroll-to-line events
    this.handleEvent("scroll_to_transcript_line", ({ index }) => {
      const el = document.getElementById(`msg-${index + 1}`)
      if (!el) return
      el.scrollIntoView({ behavior: "smooth", block: "center" })
      el.classList.add("is-jump-highlight")
      setTimeout(() => el.classList.remove("is-jump-highlight"), 2000)
    })

    // Scroll-to-message events
    this.handleEvent("scroll_to_message", ({ id }) => {
      const el = this.el.querySelector(`[data-message-id="${id}"]`)
      if (el) el.scrollIntoView({ behavior: "smooth", block: "center" })
    })

    // Transcript annotation highlighting
    this.handleEvent("highlight_transcript_annotation", ({ message_ids }) => {
      const els = message_ids
        .map((id) => this.el.querySelector(`[data-message-id="${id}"]`))
        .filter(Boolean)

      els.forEach((el) => {
        el.style.background = "rgba(91, 156, 245, 0.15)"
        el.style.borderLeft = "2px solid var(--accent-amber)"
      })

      if (els.length > 0) {
        els[0].scrollIntoView({ behavior: "smooth", block: "center" })
      }

      setTimeout(() => {
        els.forEach((el) => {
          el.style.background = ""
          el.style.borderLeft = "2px solid transparent"
        })
      }, 2000)
    })

    // Text selection for annotations
    const pushSelection = () => {
      const selection = window.getSelection()
      if (!selection || selection.isCollapsed) {
        this.pushEvent("clear_selection", {})
        return
      }

      const text = selection.toString()
      if (!text || !text.trim()) {
        this.pushEvent("clear_selection", {})
        return
      }

      const range = selection.getRangeAt(0)
      const messageEls = this.el.querySelectorAll("[data-message-id]")
      const messageIds = []

      messageEls.forEach((el) => {
        if (range.intersectsNode(el)) {
          const id = el.getAttribute("data-message-id")
          if (id && !messageIds.includes(id)) {
            messageIds.push(id)
          }
        }
      })

      if (messageIds.length === 0) {
        this.pushEvent("clear_selection", {})
        return
      }

      this.pushEvent("transcript_text_selected", {
        source: "transcript",
        text: text,
        message_ids: messageIds,
        anchor_message_id: messageIds[0] || null,
        focus_message_id: messageIds[messageIds.length - 1] || null,
      })
    }

    this._onMouseUp = () => pushSelection()
    this._onKeyUp = (e) => { if (e.shiftKey) pushSelection() }
    this.el.addEventListener("mouseup", this._onMouseUp)
    this.el.addEventListener("keyup", this._onKeyUp)
  },

  updated() {
    renderTranscriptMarkdown(this.el)
    highlightTranscriptCode(this.el)
    this._highlightDebugJson()
  },

  destroyed() {
    if (this._onMouseUp) this.el.removeEventListener("mouseup", this._onMouseUp)
    if (this._onKeyUp) this.el.removeEventListener("keyup", this._onKeyUp)
  },

  _highlightDebugJson() {
    const blocks = this.el.querySelectorAll('.transcript-debug-sidecar code.language-json')
    for (const block of blocks) {
      if (block.dataset.hljs === "done") continue
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    }
  },
}

Hooks.FileHighlighter = {
  mounted() {
    this._highlight()
    this._setupSelection()
    this._setupHighlightEvent()
  },
  updated() { this._highlight() },
  destroyed() {
    if (this._onMouseUp) this.el.removeEventListener("mouseup", this._onMouseUp)
    if (this._onKeyUp) this.el.removeEventListener("keyup", this._onKeyUp)
  },
  _highlight() {
    const blocks = this.el.querySelectorAll("pre code")
    for (const block of blocks) {
      if (block.dataset.hljs === "done") continue
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    }
  },
  _setupSelection() {
    const pushSelection = () => {
      try {
        const selection = window.getSelection()
        if (!selection || selection.isCollapsed || !selection.rangeCount) {
          this.pushEvent("clear_selection", {})
          return
        }

        const text = selection.toString()
        if (!text || !text.trim()) {
          this.pushEvent("clear_selection", {})
          return
        }

        const range = selection.getRangeAt(0)
        // Check selection is inside this hook element
        if (!this.el.contains(range.startContainer) && !this.el.contains(range.endContainer)) {
          this.pushEvent("clear_selection", {})
          return
        }

        let lineStart, lineEnd

        // Blame mode: use data-line-no on .blame-line elements
        const blameLines = this.el.querySelectorAll(".blame-line[data-line-no]")
        if (blameLines.length > 0) {
          const intersecting = []
          blameLines.forEach((el) => {
            if (range.intersectsNode(el)) {
              const n = parseInt(el.getAttribute("data-line-no"), 10)
              if (!isNaN(n)) intersecting.push(n)
            }
          })
          if (intersecting.length > 0) {
            lineStart = Math.min(...intersecting)
            lineEnd = Math.max(...intersecting)
          } else {
            lineStart = 1
            lineEnd = 1
          }
        } else {
          // Raw mode: compute line numbers from text offsets
          const codeEl = this.el.querySelector("pre code")
          if (codeEl) {
            const preRange = document.createRange()
            preRange.setStart(codeEl, 0)
            preRange.setEnd(range.startContainer, range.startOffset)
            const startLine = 1 + (preRange.toString().match(/\n/g) || []).length

            const endRange = document.createRange()
            endRange.setStart(codeEl, 0)
            endRange.setEnd(range.endContainer, range.endOffset)
            const endLine = 1 + (endRange.toString().match(/\n/g) || []).length

            lineStart = Math.min(startLine, endLine)
            lineEnd = Math.max(startLine, endLine)
          } else {
            lineStart = 1
            lineEnd = 1
          }
        }

        this.pushEvent("file_text_selected", {
          text: text.trim(),
          line_start: lineStart,
          line_end: lineEnd,
        })
      } catch (_e) {
        // Fail-safe: never throw from selection capture
      }
    }

    this._onMouseUp = () => pushSelection()
    this._onKeyUp = (e) => { if (e.shiftKey) pushSelection() }
    this.el.addEventListener("mouseup", this._onMouseUp)
    this.el.addEventListener("keyup", this._onKeyUp)
  },
  _setupHighlightEvent() {
    this.handleEvent("highlight_file_lines", ({ line_start, line_end }) => {
      try {
        // Blame mode: highlight matching .blame-line elements
        const blameLines = this.el.querySelectorAll(".blame-line[data-line-no]")
        if (blameLines.length > 0) {
          const targets = []
          blameLines.forEach((el) => {
            const n = parseInt(el.getAttribute("data-line-no"), 10)
            if (n >= line_start && n <= line_end) targets.push(el)
          })
          if (targets.length > 0) {
            targets[0].scrollIntoView({ behavior: "smooth", block: "center" })
            targets.forEach((el) => {
              el.classList.add("is-jump-highlight")
              setTimeout(() => el.classList.remove("is-jump-highlight"), 2000)
            })
          }
        } else {
          // Raw mode: best-effort proportional scroll
          const pre = this.el.querySelector("pre")
          if (pre) {
            const codeEl = pre.querySelector("code")
            const totalLines = codeEl ? (codeEl.textContent.match(/\n/g) || []).length + 1 : 1
            const ratio = Math.max(0, (line_start - 1)) / totalLines
            pre.scrollTop = ratio * pre.scrollHeight
          }
        }
      } catch (_e) {
        // Fail-safe
      }
    })
  },
}

Hooks.DiffHighlighter = {
  mounted() { this._highlight() },
  updated() { this._highlight() },
  _highlight() {
    const blocks = this.el.querySelectorAll("code.language-diff")
    for (const block of blocks) {
      if (block.dataset.hljs === "done") continue
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    }
  },
}

Hooks.SnippetHighlighter = {
  mounted() { this._highlight() },
  updated() { this._highlight() },
  _highlight() {
    const blocks = this.el.querySelectorAll("pre code[class*='language-']")
    for (const block of blocks) {
      if (block.dataset.hljs === "done") continue
      hljs.highlightElement(block)
      block.dataset.hljs = "done"
    }
  },
}

Hooks.Terminal = {
  mounted() {
    const paneId = this.el.dataset.paneId

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
      scrollback: 10000,
      theme: {
        background: "#0c0e14",
        foreground: "#e8eaf0",
        cursor: "#5b9cf5",
        selectionBackground: "rgba(91, 156, 245, 0.3)",
      },
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.loadAddon(new WebLinksAddon())

    this._term = term
    this._fitAddon = fitAddon
    this._breakpointMap = null
    this._debugAnchors = null
    this._lastSyncedId = null
    this._showDebug = false

    // Register LiveView event handlers synchronously so they're ready
    // before LiveView delivers push_event data
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

    this.handleEvent("breakpoint_map", ({ entries }) => {
      this._breakpointMap = entries
    })

    this.handleEvent("debug_anchors", ({ anchors }) => {
      this._debugAnchors = anchors
      if (this._showDebug) this._renderDebugOverlay()
    })

    this.handleEvent("scroll_to_message", ({ id }) => {
      const el = document.querySelector(`[data-message-id="${id}"]`)
      if (el) el.scrollIntoView({ behavior: "smooth", block: "center" })
    })

    // Scroll sync: use breakpoint map for instant local lookup
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
        }
      }, 150)
    })

    // Wait for fonts to load so xterm.js measures character width correctly
    document.fonts.ready.then(() => {
      term.open(this.el)
      fitAddon.fit()
      this._connectChannel(term, paneId)
    })

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
    const socket = getSharedSocket()
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

    this._channel = channel
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
    const overlay = document.createElement("div")
    overlay.className = "debug-anchor-overlay"
    overlay.style.cssText = "position:absolute;top:0;right:0;z-index:100;background:rgba(0,0,0,0.85);color:#e0e0e0;padding:8px;border-radius:0 0 0 6px;font-size:0.7em;max-height:200px;overflow-y:auto;"

    if (!anchors || anchors.length === 0) {
      overlay.innerHTML = '<div style="color:#888;">No anchor data available</div>'
      this.el.style.position = "relative"
      this.el.appendChild(overlay)
      return
    }

    const typeColors = {
      tool_use: "#e5a84b",
      user: "#5b9cf5",
      result: "#4ac89a",
      text: "#a78bfa",
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
