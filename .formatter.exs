# Used by "mix format"
[
  inputs: [".claude.exs", "{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [
    :ash_oban,
    :oban,
    :ash_sqlite,
    :ash_json_api,
    :ash_phoenix,
    :ash,
    :reactor
  ]
]
