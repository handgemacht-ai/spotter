import cytoscape from "cytoscape"
import dagre from "cytoscape-dagre"

cytoscape.use(dagre)

const STATUS_COLORS = {
  open: "#22c55e",
  in_progress: "#5b9cf5",
  closed: "#555a6e",
}

const CURRENT_BORDER = "#f59e0b"
const CURRENT_BG = "#2a2520"

const EDGE_COLORS = {
  blocks: "#ef4444",
  "discovered-from": "#6b7280",
}

const style = [
  {
    selector: "node",
    style: {
      label: "data(label)",
      "text-valign": "center",
      "text-halign": "center",
      "font-size": "10px",
      "font-family": "var(--font-ui, system-ui)",
      color: "#e2e8f0",
      "text-outline-color": "#1e293b",
      "text-outline-width": 1,
      "background-color": "#1a1e2a",
      "border-width": 2,
      "border-color": "#475569",
      width: 130,
      height: 36,
      shape: "round-rectangle",
      "text-max-width": "110px",
      "text-wrap": "ellipsis",
      cursor: "pointer",
    },
  },
  {
    selector: "node[status='open']",
    style: { "border-color": STATUS_COLORS.open },
  },
  {
    selector: "node[status='in_progress']",
    style: { "border-color": STATUS_COLORS.in_progress },
  },
  {
    selector: "node[status='closed']",
    style: { "border-color": STATUS_COLORS.closed, opacity: 0.7 },
  },
  {
    selector: "node[?current]",
    style: {
      "border-color": CURRENT_BORDER,
      "border-width": 3,
      "background-color": CURRENT_BG,
    },
  },
  {
    selector: "edge",
    style: {
      width: 1.5,
      "line-color": EDGE_COLORS["discovered-from"],
      "target-arrow-color": EDGE_COLORS["discovered-from"],
      "target-arrow-shape": "triangle",
      "curve-style": "bezier",
      "arrow-scale": 0.8,
    },
  },
  {
    selector: "edge[dep_type='blocks']",
    style: {
      "line-color": EDGE_COLORS.blocks,
      "target-arrow-color": EDGE_COLORS.blocks,
      "line-style": "solid",
    },
  },
  {
    selector: "edge[dep_type='discovered-from']",
    style: {
      "line-color": EDGE_COLORS["discovered-from"],
      "target-arrow-color": EDGE_COLORS["discovered-from"],
      "line-style": "dashed",
    },
  },
]

function truncate(str, max) {
  if (!str) return ""
  return str.length > max ? str.slice(0, max - 1) + "…" : str
}

function buildElements(data) {
  const nodes = (data.nodes || []).map((n) => ({
    group: "nodes",
    data: {
      id: n.id,
      label: truncate(n.title, 25),
      status: n.status,
      type: n.type,
      current: n.id === data.current_id,
    },
  }))

  const edges = (data.edges || []).map((e) => ({
    group: "edges",
    data: {
      id: `${e.from}->${e.to}`,
      source: e.from,
      target: e.to,
      dep_type: e.type,
    },
  }))

  return [...nodes, ...edges]
}

function layoutOpts() {
  const isNarrow = window.innerWidth < 768
  return {
    name: "dagre",
    rankDir: isNarrow ? "TB" : "LR",
    nodeSep: 30,
    rankSep: 80,
    animate: false,
    fit: true,
    padding: 20,
  }
}

const DepGraphHook = {
  mounted() {
    const raw = this.el.dataset.graph
    if (!raw) return

    const data = JSON.parse(raw)
    if (!data || !data.nodes || data.nodes.length < 2) return

    this._currentId = data.current_id

    this._cy = cytoscape({
      container: this.el,
      style: style,
      elements: buildElements(data),
      layout: layoutOpts(),
      minZoom: 0.3,
      maxZoom: 3,
      wheelSensitivity: 0.3,
    })

    this._cy.on("tap", "node", (evt) => {
      const beadId = evt.target.id()
      if (beadId === this._currentId) return

      const el = document.getElementById(`bead-${beadId}`)
      if (el) {
        el.scrollIntoView({ behavior: "smooth", block: "start" })
        el.classList.add("bead-highlight")
        setTimeout(() => el.classList.remove("bead-highlight"), 2000)
      } else {
        this.pushEvent("dep_graph_navigate", { bead_id: beadId })
      }
    })

    this.handleEvent("dep_graph_data", (newData) => {
      if (!this._cy || !newData || !newData.nodes || newData.nodes.length < 2)
        return
      this._currentId = newData.current_id
      this._cy.elements().remove()
      this._cy.add(buildElements(newData))
      this._cy.layout(layoutOpts()).run()
    })
  },

  destroyed() {
    if (this._cy) {
      this._cy.destroy()
      this._cy = null
    }
  },
}

export default DepGraphHook
