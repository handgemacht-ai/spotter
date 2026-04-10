export function initProjectSelector() {
  const el = document.getElementById("project-selector")
  if (!el) return
  if (el.dataset.initialized) return
  el.dataset.initialized = "true"

  const button = el.querySelector(".project-selector")
  const dropdown = el.querySelector(".project-selector-dropdown")
  if (!button || !dropdown) return

  function toggle() {
    const expanded = button.getAttribute("aria-expanded") === "true"
    button.setAttribute("aria-expanded", !expanded)
    dropdown.hidden = expanded
  }

  function close() {
    button.setAttribute("aria-expanded", "false")
    dropdown.hidden = true
  }

  button.addEventListener("click", () => toggle())

  dropdown.addEventListener("click", (e) => {
    const item = e.target.closest(".project-selector-item")
    if (!item) return
    close()
    const url = new URL(window.location)
    url.searchParams.set("project", item.dataset.projectId)
    url.searchParams.delete("project_id")
    window.location.href = url.toString()
  })

  document.addEventListener("click", (e) => { if (!el.contains(e.target)) close() })
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") close() })
}
