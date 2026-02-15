defmodule Spotter.MixProject do
  use Mix.Project

  def project do
    [
      app: :spotter,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      usage_rules: usage_rules(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Spotter.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:oban, "~> 2.0"},
      {:open_api_spex, "~> 3.0"},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:phoenix_live_reload, "~> 1.2", only: [:dev]},
      {:tidewave, "~> 0.5", only: [:dev]},
      {:oban_web, "~> 2.0"},
      {:ash_oban, "~> 0.7"},
      {:ash_sqlite, "~> 0.2"},
      {:ash_json_api, "~> 1.0"},
      {:ash_computer, "~> 0.2.0"},
      {:ash_ai, "~> 0.5"},
      {:ash_phoenix, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:bandit, "~> 1.0", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:tzdata, "~> 1.1"},
      {:toml, "~> 0.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ash, "~> 0.1"},
      {:myxql, "~> 0.8"},
      {:claude_agent_sdk, "~> 0.14"}
    ]
  end

  defp usage_rules do
    [
      file: "CLAUDE.md",
      skills: [
        location: ".claude/skills",
        build: [
          "ash-framework": [
            description:
              "Use this skill working with Ash Framework or any of its extensions. Always consult this when making any domain changes, features or fixes.",
            usage_rules: [:ash, ~r/^ash_/]
          ],
          "phoenix-framework": [
            description:
              "Use this skill working with Phoenix Framework. Consult this when working with the web layer, controllers, views, liveviews etc.",
            usage_rules: [:phoenix, ~r/^phoenix_/]
          ],
          oban: [
            description:
              "Use this skill when working with Oban background jobs, queues, or scheduled work.",
            usage_rules: [:oban, ~r/^oban_/]
          ],
          "front-end-design": [
            description: "Use this skill for any Spotter UI/layout/CSS/LiveView changes.",
            usage_rules: [:ui, :css, :liveview, ~r/\.heex$|spotter\.css$|lib\/spotter_web\/live/]
          ]
        ]
      ]
    ]
  end

  defp aliases() do
    [
      setup: ["deps.get", "cmd --cd assets npm ci"],
      "assets.build": ["cmd --cd assets npm ci", "cmd --cd assets node build.js"],
      "assets.deploy": [
        "cmd --cd assets npm ci",
        "cmd --cd assets node build.js",
        "phx.digest"
      ],
      test: ["ash.setup --quiet", "test --exclude slow"],
      "test.all": ["ash.setup --quiet", "test"],
      "test.slow": ["ash.setup --quiet", "test --only slow"],
      quality: ["credo", "deps.audit"]
    ]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
