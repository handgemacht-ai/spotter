import cytoscape from "cytoscape"
import dagre from "cytoscape-dagre"

cytoscape.use(dagre)

const STATUS_COLORS = {
  running: "#3b82f6",
  ok: "#22c55e",
  error: "#ef4444",
  queued: "#a855f7",
  unknown: "#6b7280",
}

const TYPE_SHAPES = {
  session: "round-rectangle",
  commit: "diamond",
  oban: "rectangle",
  agent_run: "hexagon",
}

const style = [
  {
    selector: "node",
    style: {
      label: "data(label)",
      "text-valign": "center",
      "text-halign": "center",
      "font-size": "11px",
      "font-family": "var(--font-ui, system-ui)",
      color: "#e2e8f0",
      "text-outline-color": "#1e293b",
      "text-outline-width": 1,
      "background-color": "#334155",
      "border-width": 2,
      "border-color": "#475569",
      width: 120,
      height: 36,
      shape: "round-rectangle",
      "text-max-width": "100px",
      "text-wrap": "ellipsis",
    },
  },
  {
    selector: "node[type='session']",
    style: { shape: "round-rectangle", "background-color": "#1e3a5f" },
  },
  {
    selector: "node[type='commit']",
    style: { shape: "diamond", width: 100, height: 50 },
  },
  {
    selector: "node[type='oban']",
    style: { shape: "rectangle" },
  },
  {
    selector: "node[type='agent_run']",
    style: { shape: "hexagon", width: 130, height: 40 },
  },
  {
    selector: "node[status='running']",
    style: { "border-color": STATUS_COLORS.running, "border-width": 3 },
  },
  {
    selector: "node[status='ok']",
    style: { "border-color": STATUS_COLORS.ok },
  },
  {
    selector: "node[status='error']",
    style: { "border-color": STATUS_COLORS.error, "border-width": 3 },
  },
  {
    selector: "node[status='queued']",
    style: { "border-color": STATUS_COLORS.queued },
  },
  {
    selector: "node:selected",
    style: {
      "border-color": "#f59e0b",
      "border-width": 3,
      "background-color": "#44403c",
    },
  },
  {
    selector: "edge",
    style: {
      width: 1.5,
      "line-color": "#475569",
      "target-arrow-color": "#475569",
      "target-arrow-shape": "triangle",
      "curve-style": "bezier",
      "arrow-scale": 0.8,
    },
  },
]

export function createFlowGraphHook() {
  return {
    mounted() {
      this._cy = cytoscape({
        container: this.el,
        style: style,
        layout: { name: "preset" },
        minZoom: 0.3,
        maxZoom: 3,
        wheelSensitivity: 0.3,
      })

      this._cy.on("tap", "node", (evt) => {
        const nodeId = evt.target.id()
        this.pushEvent("flow_node_selected", { node_id: nodeId })
      })

      this._cy.on("tap", (evt) => {
        if (evt.target === this._cy) {
          this.pushEvent("clear_selection", {})
        }
      })

      this.handleEvent("flow_graph_update", (data) => {
        this._updateGraph(data)
      })
    },

    _updateGraph(data) {
      const cy = this._cy
      if (!cy) return

      const existingNodeIds = new Set()
      cy.nodes().forEach((n) => existingNodeIds.add(n.id()))

      const newNodeIds = new Set(data.nodes.map((n) => n.id))
      const newEdgeIds = new Set(
        data.edges.map((e) => `${e.from}->${e.to}`)
      )

      // Remove nodes no longer present
      cy.nodes().forEach((n) => {
        if (!newNodeIds.has(n.id())) n.remove()
      })

      // Remove edges no longer present
      cy.edges().forEach((e) => {
        const edgeId = `${e.source().id()}->${e.target().id()}`
        if (!newEdgeIds.has(edgeId)) e.remove()
      })

      // Add or update nodes
      data.nodes.forEach((node) => {
        const existing = cy.getElementById(node.id)
        if (existing.length) {
          existing.data("status", node.status)
          existing.data("label", node.label)
        } else {
          cy.add({
            group: "nodes",
            data: {
              id: node.id,
              label: node.label,
              type: node.type,
              status: node.status,
              trace_id: node.trace_id,
            },
          })
        }
      })

      // Add edges
      data.edges.forEach((edge) => {
        const edgeId = `${edge.from}->${edge.to}`
        if (!cy.getElementById(edgeId).length) {
          cy.add({
            group: "edges",
            data: {
              id: edgeId,
              source: edge.from,
              target: edge.to,
            },
          })
        }
      })

      // Re-layout
      if (data.nodes.length > 0) {
        cy.layout({
          name: "dagre",
          rankDir: "TB",
          nodeSep: 40,
          rankSep: 60,
          animate: false,
          fit: true,
          padding: 30,
        }).run()
      }
    },

    destroyed() {
      if (this._cy) {
        this._cy.destroy()
        this._cy = null
      }
    },
  }
}
