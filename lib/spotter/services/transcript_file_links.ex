defmodule Spotter.Services.TranscriptFileLinks do
  @moduledoc """
  Resolves which file paths from a transcript exist on the repository's default branch.

  Provides a MapSet of repo-relative file paths for a given session working directory,
  enabling transcript views to render clickable file-detail links for existing files only.

  Results are cached in ETS with a 60-second TTL keyed by `{repo_root, ref_hash}`.
  """
  use GenServer

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.GitRunner

  @table __MODULE__
  @sweep_interval 30_000
  @ttl_ms 60_000
  @max_entries 100
  @git_timeout_ms 5_000

  # ETS record: {cache_key, inserted_at_ms, result_map}
  # cache_key: {repo_root, ref_hash}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Resolves the set of files on the default branch for the given session working directory.

  Returns `{:ok, %{repo_root: String.t(), ref: String.t(), ref_hash: String.t(), files: MapSet.t()}}`
  or `{:error, term()}`.
  """
  @spec for_session(String.t() | nil) ::
          {:ok,
           %{repo_root: String.t(), ref: String.t(), ref_hash: String.t(), files: MapSet.t()}}
          | {:error, term()}
  def for_session(nil), do: {:error, :no_cwd}

  def for_session(session_cwd) do
    Tracer.with_span "spotter.file_detail.resolve_file_links" do
      with {:ok, repo_root} <- resolve_repo_root(session_cwd),
           {:ok, ref} <- resolve_default_ref(repo_root),
           {:ok, ref_hash} <- resolve_ref_hash(repo_root, ref) do
        Tracer.set_attribute("spotter.file_links.repo_root", repo_root)
        Tracer.set_attribute("spotter.file_links.resolved_ref", ref)
        Tracer.set_attribute("spotter.file_links.ref_hash", ref_hash)

        resolve_with_cache({repo_root, ref_hash}, ref)
      end
    end
  end

  defp resolve_with_cache(cache_key, ref) do
    {repo_root, ref_hash} = cache_key

    case lookup_cache(cache_key) do
      {:ok, cached} ->
        Tracer.set_attribute("spotter.file_links.cache_hit", true)
        Tracer.set_attribute("spotter.file_links.file_count", MapSet.size(cached.files))
        {:ok, cached}

      :miss ->
        Tracer.set_attribute("spotter.file_links.cache_hit", false)
        fetch_and_cache(cache_key, repo_root, ref, ref_hash)
    end
  end

  defp fetch_and_cache(cache_key, repo_root, ref, ref_hash) do
    case load_file_list(repo_root, ref_hash) do
      {:ok, files} ->
        result = %{repo_root: repo_root, ref: ref, ref_hash: ref_hash, files: files}
        insert_cache(cache_key, result)
        Tracer.set_attribute("spotter.file_links.file_count", MapSet.size(files))
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)

    :ets.tab2list(@table)
    |> Enum.each(fn {key, inserted_at_ms, _result} ->
      if now - inserted_at_ms > @ttl_ms do
        :ets.delete(@table, key)
      end
    end)

    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  # Cache helpers

  defp lookup_cache(cache_key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, cache_key) do
      [{^cache_key, inserted_at_ms, result}] when now - inserted_at_ms <= @ttl_ms ->
        {:ok, result}

      [{^cache_key, _inserted_at_ms, _result}] ->
        :ets.delete(@table, cache_key)
        :miss

      [] ->
        :miss
    end
  end

  defp insert_cache(cache_key, result) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table, {cache_key, now, result})
    enforce_max_entries()
  end

  defp enforce_max_entries do
    entries = :ets.tab2list(@table)

    if length(entries) > @max_entries do
      entries
      |> Enum.sort_by(fn {_key, inserted_at_ms, _result} -> inserted_at_ms end)
      |> Enum.take(length(entries) - @max_entries)
      |> Enum.each(fn {key, _ts, _result} -> :ets.delete(@table, key) end)
    end
  end

  # Git resolution helpers

  defp resolve_repo_root(cwd) do
    case GitRunner.run(["rev-parse", "--show-toplevel"], cd: cwd, timeout_ms: @git_timeout_ms) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:error, :git_root_failed}
    end
  end

  defp resolve_default_ref(repo_root) do
    ref_strategies = [
      fn -> resolve_origin_head(repo_root) end,
      fn -> check_ref_exists(repo_root, "main") end,
      fn -> check_ref_exists(repo_root, "master") end,
      fn -> resolve_current_branch(repo_root) end
    ]

    Enum.find_value(ref_strategies, {:error, :no_default_ref}, fn strategy ->
      case strategy.() do
        {:ok, ref} -> {:ok, ref}
        _ -> nil
      end
    end)
  end

  defp resolve_origin_head(repo_root) do
    case GitRunner.run(["symbolic-ref", "refs/remotes/origin/HEAD"],
           cd: repo_root,
           timeout_ms: @git_timeout_ms
         ) do
      {:ok, output} ->
        ref = output |> String.trim() |> String.replace_prefix("refs/remotes/origin/", "")
        {:ok, ref}

      {:error, _} ->
        :error
    end
  end

  defp check_ref_exists(repo_root, ref) do
    case GitRunner.run(["rev-parse", "--verify", ref],
           cd: repo_root,
           timeout_ms: @git_timeout_ms
         ) do
      {:ok, _} -> {:ok, ref}
      {:error, _} -> :error
    end
  end

  defp resolve_current_branch(repo_root) do
    case GitRunner.run(["rev-parse", "--abbrev-ref", "HEAD"],
           cd: repo_root,
           timeout_ms: @git_timeout_ms
         ) do
      {:ok, output} ->
        branch = String.trim(output)
        if branch != "" and branch != "HEAD", do: {:ok, branch}, else: :error

      {:error, _} ->
        :error
    end
  end

  defp resolve_ref_hash(repo_root, ref) do
    case GitRunner.run(["rev-parse", ref], cd: repo_root, timeout_ms: @git_timeout_ms) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:error, :ref_hash_failed}
    end
  end

  defp load_file_list(repo_root, ref_hash) do
    case GitRunner.run(["ls-tree", "-r", "--name-only", ref_hash],
           cd: repo_root,
           timeout_ms: @git_timeout_ms,
           max_bytes: 10_000_000
         ) do
      {:ok, output} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> MapSet.new()

        {:ok, files}

      {:error, _} ->
        {:error, :ls_tree_failed}
    end
  end
end
