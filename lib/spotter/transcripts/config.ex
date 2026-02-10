defmodule Spotter.Transcripts.Config do
  @moduledoc """
  Reads and parses the spotter.toml configuration file.
  """

  @config_path "priv/spotter.toml"

  @spec read!() :: %{
          transcripts_dir: String.t(),
          projects: %{String.t() => %{pattern: Regex.t()}}
        }
  def read! do
    path = Application.app_dir(:spotter, @config_path)

    toml =
      path
      |> File.read!()
      |> Toml.decode!()

    transcripts_dir =
      toml
      |> Map.fetch!("transcripts_dir")
      |> expand_path()

    projects =
      toml
      |> Map.get("projects", %{})
      |> Map.new(fn {name, config} ->
        {name, %{pattern: Regex.compile!(config["pattern"])}}
      end)

    %{transcripts_dir: transcripts_dir, projects: projects}
  end

  defp expand_path(path) do
    String.replace(path, "~", System.user_home!())
  end
end
