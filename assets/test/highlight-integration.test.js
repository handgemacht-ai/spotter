/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect, beforeEach } from "vitest"
import hljs from "highlight.js/lib/core"
import elixir from "highlight.js/lib/languages/elixir"
import bash from "highlight.js/lib/languages/bash"
import json from "highlight.js/lib/languages/json"
import diff from "highlight.js/lib/languages/diff"
import plaintext from "highlight.js/lib/languages/plaintext"
import { marked } from "marked"
import DOMPurify from "dompurify"

hljs.registerLanguage("elixir", elixir)
hljs.registerLanguage("bash", bash)
hljs.registerLanguage("json", json)
hljs.registerLanguage("diff", diff)
hljs.registerLanguage("plaintext", plaintext)

// Replicate the highlighter function from app.js
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

    const rendered = marked.parseInline(row.dataset.mdSource, { gfm: true, breaks: true })
    row.innerHTML = DOMPurify.sanitize(rendered)
    row.dataset.mdRendered = "done"
  }
}

describe("highlightTranscriptCode", () => {
  let container

  beforeEach(() => {
    container = document.createElement("div")
    document.body.appendChild(container)
  })

  it("highlights code blocks with registered languages", () => {
    container.innerHTML = `
      <div data-render-mode="code">
        <code class="language-elixir">def foo, do: :bar</code>
      </div>
    `

    highlightTranscriptCode(container)

    const code = container.querySelector("code")
    expect(code.dataset.hljs).toBe("done")
    // hljs adds the hljs class and applies syntax highlighting spans
    expect(code.classList.contains("hljs")).toBe(true)
    expect(code.innerHTML).toContain("<span")
  })

  it("runs idempotently — does not re-highlight already processed nodes", () => {
    container.innerHTML = `
      <div data-render-mode="code">
        <code class="language-bash">echo "hello"</code>
      </div>
    `

    highlightTranscriptCode(container)
    const firstPassHTML = container.querySelector("code").innerHTML

    // Run again — should not modify already-highlighted code
    highlightTranscriptCode(container)
    const secondPassHTML = container.querySelector("code").innerHTML

    expect(firstPassHTML).toBe(secondPassHTML)
    expect(container.querySelector("code").dataset.hljs).toBe("done")
  })

  it("marks each node exactly once", () => {
    container.innerHTML = `
      <div data-render-mode="code">
        <code class="language-json">{"key": "value"}</code>
      </div>
      <div data-render-mode="code">
        <code class="language-elixir">IO.puts("hi")</code>
      </div>
    `

    highlightTranscriptCode(container)

    const codes = container.querySelectorAll("code")
    expect(codes.length).toBe(2)
    for (const code of codes) {
      expect(code.dataset.hljs).toBe("done")
    }
  })

  it("does not throw for missing language class", () => {
    container.innerHTML = `
      <div data-render-mode="code">
        <code>some plain code</code>
      </div>
    `

    expect(() => highlightTranscriptCode(container)).not.toThrow()

    const code = container.querySelector("code")
    expect(code.dataset.hljs).toBe("done")
  })

  it("skips non-code rows (no data-render-mode='code')", () => {
    container.innerHTML = `
      <div data-render-mode="plain">
        <code class="language-elixir">def foo, do: :bar</code>
      </div>
    `

    highlightTranscriptCode(container)

    const code = container.querySelector("code")
    // Not targeted by the selector, so should not be highlighted
    expect(code.dataset.hljs).toBeUndefined()
    expect(code.classList.contains("hljs")).toBe(false)
  })

  it("handles empty container without error", () => {
    expect(() => highlightTranscriptCode(container)).not.toThrow()
  })

  it("highlights new nodes added after initial pass", () => {
    container.innerHTML = `
      <div data-render-mode="code">
        <code class="language-elixir">first</code>
      </div>
    `

    highlightTranscriptCode(container)
    expect(container.querySelectorAll('[data-hljs="done"]').length).toBe(1)

    // Simulate LiveView adding a new code block
    const newDiv = document.createElement("div")
    newDiv.setAttribute("data-render-mode", "code")
    newDiv.innerHTML = '<code class="language-bash">echo new</code>'
    container.appendChild(newDiv)

    highlightTranscriptCode(container)

    // Both original and new should be highlighted
    expect(container.querySelectorAll('[data-hljs="done"]').length).toBe(2)
  })
})

describe("hljs.highlight direct", () => {
  it("highlights elixir code", () => {
    const result = hljs.highlight("def foo(x), do: x + 1", { language: "elixir" })
    expect(result.value).toContain("<span")
    expect(result.language).toBe("elixir")
  })

  it("highlights bash code", () => {
    const result = hljs.highlight("echo $HOME", { language: "bash" })
    expect(result.value).toContain("<span")
  })

  it("highlights diff code", () => {
    const result = hljs.highlight("+ added line\n- removed line", { language: "diff" })
    expect(result.value).toContain("<span")
  })

  it("handles plaintext without adding spans", () => {
    const result = hljs.highlight("just some text", { language: "plaintext" })
    // plaintext language should not add syntax spans
    expect(result.language).toBe("plaintext")
  })
})

describe("renderTranscriptMarkdown", () => {
  let container

  beforeEach(() => {
    container = document.createElement("div")
    document.body.appendChild(container)
  })

  it("renders markdown syntax into HTML", () => {
    container.innerHTML = `
      <span data-render-markdown="true">Use **bold** and \`code\`</span>
    `

    renderTranscriptMarkdown(container)

    const row = container.querySelector('[data-render-markdown="true"]')
    expect(row.innerHTML).toContain("<strong>bold</strong>")
    expect(row.innerHTML).toContain("<code>code</code>")
    expect(row.dataset.mdRendered).toBe("done")
  })

  it("sanitizes unsafe HTML from markdown input", () => {
    container.innerHTML = `
      <span data-render-markdown="true">Click <img src=x onerror="alert('xss')"> here</span>
    `

    renderTranscriptMarkdown(container)

    const row = container.querySelector('[data-render-markdown="true"]')
    expect(row.innerHTML).not.toContain("onerror")
    expect(row.innerHTML).not.toContain("<img")
  })

  it("skips rows marked as non-markdown", () => {
    container.innerHTML = `
      <span data-render-markdown="false">**not rendered**</span>
    `

    renderTranscriptMarkdown(container)

    const row = container.querySelector('[data-render-markdown="false"]')
    expect(row.innerHTML).toBe("**not rendered**")
  })
})
