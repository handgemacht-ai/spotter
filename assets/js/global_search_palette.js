/**
 * Global Cmd-K / Ctrl-K search palette.
 *
 * Queries /api/search with debounce + abort, renders results,
 * navigates on Enter/click.
 */

const DEBOUNCE_MS = 150
const DEFAULT_LIMIT = 20
const ENDPOINT = "/api/search"

let initialized = false

export function initGlobalSearchPalette() {
  if (initialized) return
  initialized = true

  const palette = document.getElementById("global-search-palette")
  const input = document.getElementById("global-search-palette-input")
  const results = document.getElementById("global-search-results")
  const trigger = document.getElementById("global-search-trigger")

  if (!palette || !input || !results) return

  let selectedIndex = -1
  let currentResults = []
  let debounceTimer = null
  let abortController = null

  function isOpen() {
    return palette.classList.contains("is-open")
  }

  function open() {
    palette.classList.add("is-open")
    input.value = ""
    results.innerHTML = ""
    selectedIndex = -1
    currentResults = []
    requestAnimationFrame(() => input.focus())
  }

  function close() {
    palette.classList.remove("is-open")
    input.blur()
    if (abortController) abortController.abort()
    clearTimeout(debounceTimer)
  }

  function shouldIgnoreShortcut() {
    const el = document.activeElement
    if (!el) return false
    const tag = el.tagName.toLowerCase()
    if (tag === "input" || tag === "textarea" || el.isContentEditable) return true
    return false
  }

  function detectProjectId() {
    const m = window.location.pathname.match(/\/projects\/([0-9a-f-]+)/)
    if (m) return m[1]
    const params = new URLSearchParams(window.location.search)
    return params.get("project_id")
  }

  function kindBadge(kind) {
    const labels = {
      file: "File",
      directory: "Dir",
      session: "Session",
      commit: "Commit",
      commit_hotspot: "Hotspot",
      annotation: "Note",
      product_domain: "Domain",
      product_feature: "Feature",
      product_requirement: "Req",
    }
    return labels[kind] || kind
  }

  function renderResults(items) {
    currentResults = items
    selectedIndex = items.length > 0 ? 0 : -1

    if (items.length === 0) {
      results.innerHTML = '<div class="search-palette-empty">No results</div>'
      return
    }

    results.innerHTML = items
      .map((r, i) => {
        const sel = i === 0 ? " is-selected" : ""
        const subtitle = r.subtitle ? `<span class="search-result-subtitle">${esc(r.subtitle)}</span>` : ""
        return `<div class="search-result-row${sel}" data-index="${i}">
          <span class="search-result-badge">${esc(kindBadge(r.kind))}</span>
          <span class="search-result-title">${esc(r.title)}</span>
          ${subtitle}
        </div>`
      })
      .join("")
  }

  function updateSelection() {
    const rows = results.querySelectorAll(".search-result-row")
    rows.forEach((row, i) => {
      row.classList.toggle("is-selected", i === selectedIndex)
      if (i === selectedIndex) row.scrollIntoView({ block: "nearest" })
    })
  }

  function navigate() {
    if (selectedIndex >= 0 && currentResults[selectedIndex]) {
      window.location.assign(currentResults[selectedIndex].url)
    }
  }

  async function doSearch(q) {
    if (abortController) abortController.abort()
    abortController = new AbortController()

    const params = new URLSearchParams({ q, limit: DEFAULT_LIMIT })
    const projectId = detectProjectId()
    if (projectId) params.set("project_id", projectId)

    results.innerHTML = '<div class="search-palette-loading">Searching\u2026</div>'

    try {
      const resp = await fetch(`${ENDPOINT}?${params}`, { signal: abortController.signal })
      const data = await resp.json()
      renderResults(data.results || [])
    } catch (err) {
      if (err.name !== "AbortError") {
        results.innerHTML = '<div class="search-palette-empty">Search unavailable</div>'
      }
    }
  }

  // --- Event listeners ---

  document.addEventListener("keydown", (e) => {
    const isMac = navigator.platform.toUpperCase().indexOf("MAC") >= 0
    const modKey = isMac ? e.metaKey : e.ctrlKey

    if (modKey && e.key === "k") {
      if (shouldIgnoreShortcut()) return
      e.preventDefault()
      isOpen() ? close() : open()
      return
    }

    if (!isOpen()) return

    if (e.key === "Escape") {
      e.preventDefault()
      close()
    } else if (e.key === "ArrowDown") {
      e.preventDefault()
      if (currentResults.length > 0) {
        selectedIndex = (selectedIndex + 1) % currentResults.length
        updateSelection()
      }
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      if (currentResults.length > 0) {
        selectedIndex = (selectedIndex - 1 + currentResults.length) % currentResults.length
        updateSelection()
      }
    } else if (e.key === "Enter") {
      e.preventDefault()
      navigate()
    }
  })

  input.addEventListener("input", () => {
    clearTimeout(debounceTimer)
    const q = input.value.trim()
    if (!q) {
      results.innerHTML = ""
      currentResults = []
      selectedIndex = -1
      return
    }
    debounceTimer = setTimeout(() => doSearch(q), DEBOUNCE_MS)
  })

  results.addEventListener("click", (e) => {
    const row = e.target.closest(".search-result-row")
    if (row) {
      selectedIndex = parseInt(row.dataset.index, 10)
      navigate()
    }
  })

  // Backdrop click closes
  palette.addEventListener("click", (e) => {
    if (e.target === palette) close()
  })

  if (trigger) {
    trigger.addEventListener("click", (e) => {
      e.preventDefault()
      open()
    })
  }
}

function esc(s) {
  const el = document.createElement("span")
  el.textContent = s || ""
  return el.innerHTML
}
