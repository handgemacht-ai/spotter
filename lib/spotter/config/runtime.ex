defmodule Spotter.Config.Runtime do
  @moduledoc """
  Resolves effective configuration values with deterministic precedence.

  Each accessor returns `{value, source}` where source indicates
  where the value came from (`:db`, `:toml`, `:env`, or `:default`).
  """

  alias Spotter.Config.Setting

  require Ash.Query

  @default_transcripts_dir "~/.claude/projects"

  @doc """
  Returns the effective transcripts directory.

  Precedence: DB override -> TOML `priv/spotter.toml` -> default `~/.claude/projects`.
  The `~` is expanded to the user's home directory.
  """
  @spec transcripts_dir() :: {String.t(), atom()}
  def transcripts_dir do
    case db_get("transcripts_dir") do
      {:ok, val} -> {expand_path(val), :db}
      :miss -> transcripts_dir_from_toml()
    end
  end

  # -- Private helpers --

  defp db_get(key) do
    case Setting
         |> Ash.Query.filter(key == ^key)
         |> Ash.read_one() do
      {:ok, %Setting{value: val}} -> {:ok, val}
      _ -> :miss
    end
  end

  defp transcripts_dir_from_toml do
    case read_toml_transcripts_dir() do
      {:ok, dir} -> {expand_path(dir), :toml}
      :error -> {expand_path(@default_transcripts_dir), :default}
    end
  end

  defp read_toml_transcripts_dir do
    path = Application.app_dir(:spotter, "priv/spotter.toml")

    with {:ok, content} <- File.read(path),
         {:ok, toml} <- Toml.decode(content),
         %{"transcripts_dir" => dir} when is_binary(dir) <- toml do
      {:ok, dir}
    else
      _ -> :error
    end
  end

  defp expand_path(path) do
    String.replace(path, "~", System.user_home!())
  end
end
