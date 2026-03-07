defmodule Spotter.Config.Runtime do
  @moduledoc """
  Resolves effective configuration values with deterministic precedence.

  Each accessor returns `{value, source}` where source indicates
  where the value came from (`:db`, `:toml`, `:env`, or `:default`).
  """

  alias Spotter.Config.Setting

  require Ash.Query

  @default_transcript_roots ["~/.claude/projects", "~/.claude_agents/projects"]

  @doc """
  Returns the effective transcript roots as a normalized list of paths.

  Precedence: DB override -> TOML `priv/spotter.toml` -> defaults.
  Paths are expanded (`~` -> home), trimmed, deduped, and made absolute.
  """
  @spec transcript_roots() :: {[String.t()], atom()}
  def transcript_roots do
    case db_get_roots() do
      {:ok, roots} -> {normalize_roots(roots), :db}
      :miss -> transcript_roots_from_toml()
    end
  end

  # -- Private helpers --

  defp db_get_roots do
    case db_get("transcript_roots") do
      {:ok, json} -> parse_json_roots(json)
      :miss -> :miss
    end
  end

  defp parse_json_roots(json) do
    case Jason.decode(json) do
      {:ok, roots} when is_list(roots) ->
        roots = Enum.filter(roots, &is_binary/1)
        if roots == [], do: :miss, else: {:ok, roots}

      _ ->
        :miss
    end
  end

  defp db_get(key) do
    case Setting
         |> Ash.Query.filter(key == ^key)
         |> Ash.read_one() do
      {:ok, %Setting{value: val}} -> {:ok, val}
      _ -> :miss
    end
  end

  defp transcript_roots_from_toml do
    case read_toml_transcript_roots() do
      {:ok, roots} -> {normalize_roots(roots), :toml}
      :error -> {normalize_roots(@default_transcript_roots), :default}
    end
  end

  defp read_toml_transcript_roots do
    path = Application.app_dir(:spotter, "priv/spotter.toml")

    with {:ok, content} <- File.read(path),
         {:ok, toml} <- Toml.decode(content),
         %{"transcript_roots" => roots} when is_list(roots) <- toml do
      roots = Enum.filter(roots, &is_binary/1)
      if roots == [], do: :error, else: {:ok, roots}
    else
      _ -> :error
    end
  end

  defp normalize_roots(roots) do
    case roots |> Enum.map(&normalize_path/1) |> Enum.uniq() do
      [] -> Enum.map(@default_transcript_roots, &normalize_path/1)
      normalized -> normalized
    end
  end

  defp normalize_path(path) do
    path
    |> String.trim()
    |> Path.expand()
  end
end
