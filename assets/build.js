const esbuild = require("esbuild")
const path = require("path")

const watch = process.argv.includes("--watch")

const ctx = esbuild.context({
  entryPoints: ["js/app.js"],
  bundle: true,
  outdir: path.resolve(__dirname, "../priv/static/assets"),
  logLevel: "info",
  alias: {
    "phoenix_html": path.resolve(__dirname, "../deps/phoenix_html/priv/static/phoenix_html.js"),
    "phoenix": path.resolve(__dirname, "../deps/phoenix/priv/static/phoenix.cjs.js"),
    "phoenix_live_view": path.resolve(__dirname, "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js"),
  },
})

ctx.then(async (c) => {
  if (watch) {
    await c.watch()
    console.log("Watching for changes...")
  } else {
    await c.rebuild()
    await c.dispose()
  }
})
