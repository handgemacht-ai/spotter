defmodule Mix.Tasks.Spotter.CliHelpers do
  @moduledoc false

  require Logger

  @doc "Load config and start only the Repo (no Oban, no PubSub, no Endpoint)."
  def start_app_without_server do
    Logger.configure(level: :info)
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Application.ensure_all_started(:ash)

    case Spotter.Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @doc """
  Parse CLI args with strict validation. Exits with usage on invalid flags
  or malformed values. Returns parsed keyword list.

  `usage_fn` is a zero-arity function that prints help text.
  """
  def parse_args!(args, switches, usage_fn) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: switches)

    if invalid != [] do
      bad = Enum.map_join(invalid, ", ", fn {flag, _} -> flag end)
      Mix.shell().error("Unknown option(s): #{bad}")
      usage_fn.()
      exit({:shutdown, 1})
    end

    if rest != [] do
      Mix.shell().error("Unexpected argument(s): #{Enum.join(rest, ", ")}")
      usage_fn.()
      exit({:shutdown, 1})
    end

    validate_positive_integers!(opts, switches, usage_fn)

    opts
  end

  defp validate_positive_integers!(opts, switches, usage_fn) do
    integer_keys =
      for {key, type} <- switches, type == :integer or (is_list(type) and :integer in type) do
        key
      end

    Enum.each(integer_keys, fn key ->
      case Keyword.get(opts, key) do
        nil ->
          :ok

        val when is_integer(val) and val < 1 ->
          flag = key |> Atom.to_string() |> String.replace("_", "-")
          Mix.shell().error("--#{flag} must be a positive integer, got: #{val}")
          usage_fn.()
          exit({:shutdown, 1})

        _ ->
          :ok
      end
    end)
  end
end
