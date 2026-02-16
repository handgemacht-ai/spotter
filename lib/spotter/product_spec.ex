defmodule Spotter.ProductSpec do
  @moduledoc """
  Public read API for the versioned product specification stored in Dolt.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.{Repo, RollingSpecRun, SpecDiff}

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @doc "Normalizes evidence_files from DB (nil/JSON string/list) into a list of strings."
  def normalize_evidence_files(nil), do: []
  def normalize_evidence_files(list) when is_list(list), do: Enum.filter(list, &is_binary/1)

  def normalize_evidence_files(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> Enum.filter(list, &is_binary/1)
      _ -> []
    end
  end

  def normalize_evidence_files(_), do: []

  defp normalize_requirement_evidence(%{evidence_files: raw} = req) do
    %{req | evidence_files: normalize_evidence_files(raw)}
  end

  @doc "Lists all domains for the given project, sorted by name."
  @spec list_domains(String.t()) :: [map()]
  def list_domains(project_id) do
    from(d in "product_domains",
      where: d.project_id == ^project_id,
      order_by: [asc: d.name],
      select: %{
        id: d.id,
        project_id: d.project_id,
        spec_key: d.spec_key,
        name: d.name,
        description: d.description,
        updated_by_git_commit: d.updated_by_git_commit,
        inserted_at: d.inserted_at,
        updated_at: d.updated_at
      }
    )
    |> Repo.all()
  end

  @doc "Lists all features for the given project and domain, sorted by name."
  @spec list_features(String.t(), String.t()) :: [map()]
  def list_features(project_id, domain_id) do
    from(f in "product_features",
      where: f.project_id == ^project_id and f.domain_id == ^domain_id,
      order_by: [asc: f.name],
      select: %{
        id: f.id,
        project_id: f.project_id,
        domain_id: f.domain_id,
        spec_key: f.spec_key,
        name: f.name,
        description: f.description,
        updated_by_git_commit: f.updated_by_git_commit,
        inserted_at: f.inserted_at,
        updated_at: f.updated_at
      }
    )
    |> Repo.all()
  end

  @doc "Lists all requirements for the given project and feature, sorted by spec_key."
  @spec list_requirements(String.t(), String.t()) :: [map()]
  def list_requirements(project_id, feature_id) do
    from(r in "product_requirements",
      where: r.project_id == ^project_id and r.feature_id == ^feature_id,
      order_by: [asc: r.spec_key],
      select: %{
        id: r.id,
        project_id: r.project_id,
        feature_id: r.feature_id,
        spec_key: r.spec_key,
        statement: r.statement,
        rationale: r.rationale,
        acceptance_criteria: r.acceptance_criteria,
        priority: r.priority,
        evidence_files: r.evidence_files,
        updated_by_git_commit: r.updated_by_git_commit,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize_requirement_evidence/1)
  end

  @doc "Returns true when the Dolt-backed ProductSpec.Repo is running."
  @spec dolt_available?() :: boolean()
  def dolt_available?, do: Process.whereis(Spotter.ProductSpec.Repo) != nil

  @doc "LIKE search against product domains."
  @spec search_domains(String.t() | nil, String.t(), pos_integer()) :: [map()]
  def search_domains(project_id, q, limit) do
    pattern = "%#{q}%"

    from(d in "product_domains",
      where: like(d.name, ^pattern) or like(d.spec_key, ^pattern),
      order_by: [asc: d.name],
      limit: ^limit,
      select: %{
        id: d.id,
        project_id: d.project_id,
        spec_key: d.spec_key,
        name: d.name,
        description: d.description
      }
    )
    |> maybe_filter_project(project_id)
    |> Repo.all()
  rescue
    _ -> []
  end

  @doc "LIKE search against product features."
  @spec search_features(String.t() | nil, String.t(), pos_integer()) :: [map()]
  def search_features(project_id, q, limit) do
    pattern = "%#{q}%"

    from(f in "product_features",
      where: like(f.name, ^pattern) or like(f.spec_key, ^pattern),
      order_by: [asc: f.name],
      limit: ^limit,
      select: %{
        id: f.id,
        project_id: f.project_id,
        spec_key: f.spec_key,
        name: f.name,
        description: f.description
      }
    )
    |> maybe_filter_project(project_id)
    |> Repo.all()
  rescue
    _ -> []
  end

  @doc "LIKE search against product requirements."
  @spec search_requirements(String.t() | nil, String.t(), pos_integer()) :: [map()]
  def search_requirements(project_id, q, limit) do
    pattern = "%#{q}%"

    from(r in "product_requirements",
      where: like(r.statement, ^pattern) or like(r.spec_key, ^pattern),
      order_by: [asc: r.spec_key],
      limit: ^limit,
      select: %{id: r.id, project_id: r.project_id, spec_key: r.spec_key, statement: r.statement}
    )
    |> maybe_filter_project(project_id)
    |> Repo.all()
  rescue
    _ -> []
  end

  defp maybe_filter_project(query, nil), do: query

  defp maybe_filter_project(query, project_id),
    do: from(q in query, where: q.project_id == ^project_id)

  @doc """
  Returns the full domain -> features -> requirements tree for a project.

  Domains are sorted by name, features by name, requirements by spec_key.
  """
  @spec tree(String.t()) :: [map()]
  def tree(project_id) do
    domains = list_domains(project_id)
    features_by_domain = list_all_features(project_id)
    requirements_by_feature = list_all_requirements(project_id)

    Enum.map(domains, &attach_features(&1, features_by_domain, requirements_by_feature))
  end

  @doc """
  Returns the full spec tree at a specific Dolt commit hash using time-travel queries.

  Returns the same shape as `tree/1`.
  """
  @spec tree_at(String.t(), String.t()) ::
          {:ok, [map()]} | {:error, {:dolt_query_failed, String.t()} | {:error, String.t()}}
  def tree_at(project_id, dolt_commit_hash) do
    Tracer.with_span "spotter.product_spec.tree_at" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.dolt_commit_hash", dolt_commit_hash)

      with {:ok, domains} <- query_domains_at(project_id, dolt_commit_hash),
           {:ok, features} <- query_features_at(project_id, dolt_commit_hash),
           {:ok, requirements} <- query_requirements_at(project_id, dolt_commit_hash) do
        features_by_domain = Enum.group_by(features, & &1.domain_id)
        requirements_by_feature = Enum.group_by(requirements, & &1.feature_id)

        {:ok,
         Enum.map(domains, &attach_features(&1, features_by_domain, requirements_by_feature))}
      else
        {:error, reason} ->
          Tracer.set_status(:error, to_string(reason))
          {:error, reason}
      end
    end
  end

  @doc """
  Resolves the effective spec tree for a Git commit.

  If the commit's spec run has no Dolt changes (dolt_commit_hash is nil),
  falls back to the previous run's snapshot.

  Returns `{:ok, %{tree: [...], effective_dolt_commit_hash: hash | nil}}`
  or `{:error, :no_spec_run}`.
  """
  @spec tree_for_commit(String.t(), String.t()) ::
          {:ok, %{tree: [map()], effective_dolt_commit_hash: String.t() | nil}}
          | {:error, :no_spec_run | {:dolt_query_failed, String.t()} | {:error, String.t()}}
  def tree_for_commit(project_id, commit_hash) do
    Tracer.with_span "spotter.product_spec.tree_for_commit" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)

      case load_spec_run(project_id, commit_hash) do
        nil ->
          Tracer.set_status(:error, "no_spec_run")
          {:error, :no_spec_run}

        run ->
          effective_hash = run.dolt_commit_hash || find_previous_dolt_hash(project_id, run)
          resolve_tree(project_id, effective_hash)
      end
    end
  end

  defp resolve_tree(_project_id, nil), do: {:ok, %{tree: [], effective_dolt_commit_hash: nil}}

  defp resolve_tree(project_id, effective_hash) do
    case tree_at(project_id, effective_hash) do
      {:ok, tree} -> {:ok, %{tree: tree, effective_dolt_commit_hash: effective_hash}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Computes a semantic spec diff for a Git commit vs its previous spec state.

  Returns:
  - `{:error, :no_spec_run}` when no run exists for this commit
  - `{:ok, %{kind: :no_changes, added: [], removed: [], changed: []}}` when dolt_commit_hash is nil
  - `{:ok, diff_result}` with the semantic diff
  """
  @spec diff_for_commit(String.t(), String.t()) ::
          {:ok, map()}
          | {:error, :no_spec_run | {:dolt_query_failed, String.t()} | {:error, String.t()}}
  def diff_for_commit(project_id, commit_hash) do
    Tracer.with_span "spotter.product_spec.diff_for_commit" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)

      case load_spec_run(project_id, commit_hash) do
        nil ->
          Tracer.set_status(:error, "no_spec_run")
          {:error, :no_spec_run}

        %{dolt_commit_hash: nil} ->
          {:ok, %{kind: :no_changes, added: [], removed: [], changed: []}}

        run ->
          base_hash = find_previous_dolt_hash(project_id, run)

          case {if(base_hash, do: tree_at(project_id, base_hash), else: {:ok, []}),
                tree_at(project_id, run.dolt_commit_hash)} do
            {{:ok, from_tree}, {:ok, to_tree}} ->
              {:ok, SpecDiff.diff(from_tree, to_tree)}

            {{:error, reason}, _} ->
              {:error, reason}

            {_, {:error, reason}} ->
              {:error, reason}
          end
      end
    end
  end

  defp attach_features(domain, features_by_domain, requirements_by_feature) do
    features =
      features_by_domain
      |> Map.get(domain.id, [])
      |> Enum.map(&Map.put(&1, :requirements, Map.get(requirements_by_feature, &1.id, [])))

    Map.put(domain, :features, features)
  end

  defp list_all_features(project_id) do
    from(f in "product_features",
      where: f.project_id == ^project_id,
      order_by: [asc: f.name],
      select: %{
        id: f.id,
        project_id: f.project_id,
        domain_id: f.domain_id,
        spec_key: f.spec_key,
        name: f.name,
        description: f.description,
        updated_by_git_commit: f.updated_by_git_commit,
        inserted_at: f.inserted_at,
        updated_at: f.updated_at
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.domain_id)
  end

  # -- Dolt time-travel helpers ------------------------------------------------

  defp query_domains_at(project_id, dolt_commit_hash) do
    with {:ok, result} <-
           query_at(
             """
             SELECT id, project_id, spec_key, name, description,
                    updated_by_git_commit, inserted_at, updated_at
             FROM `product_domains` AS OF ?
             WHERE project_id = ?
             ORDER BY name ASC
             """,
             [dolt_commit_hash, project_id]
           ) do
      {:ok,
       Enum.map(result.rows, fn [id, proj_id, spec_key, name, desc, git_commit, ins, upd] ->
         %{
           id: id,
           project_id: proj_id,
           spec_key: spec_key,
           name: name,
           description: desc,
           updated_by_git_commit: git_commit,
           inserted_at: ins,
           updated_at: upd
         }
       end)}
    end
  end

  defp query_features_at(project_id, dolt_commit_hash) do
    with {:ok, result} <-
           query_at(
             """
             SELECT id, project_id, domain_id, spec_key, name, description,
                    updated_by_git_commit, inserted_at, updated_at
             FROM `product_features` AS OF ?
             WHERE project_id = ?
             ORDER BY name ASC
             """,
             [dolt_commit_hash, project_id]
           ) do
      {:ok,
       Enum.map(result.rows, fn [id, proj_id, dom_id, spec_key, name, desc, git_commit, ins, upd] ->
         %{
           id: id,
           project_id: proj_id,
           domain_id: dom_id,
           spec_key: spec_key,
           name: name,
           description: desc,
           updated_by_git_commit: git_commit,
           inserted_at: ins,
           updated_at: upd
         }
       end)}
    end
  end

  defp query_requirements_at(project_id, dolt_commit_hash) do
    with {:ok, result} <-
           query_at(
             """
             SELECT id, project_id, feature_id, spec_key, statement, rationale,
                    acceptance_criteria, priority, updated_by_git_commit, inserted_at, updated_at
             FROM `product_requirements` AS OF ?
             WHERE project_id = ?
             ORDER BY spec_key ASC
             """,
             [dolt_commit_hash, project_id]
           ) do
      {:ok,
       Enum.map(result.rows, fn [
                                  id,
                                  proj_id,
                                  feat_id,
                                  spec_key,
                                  stmt,
                                  rat,
                                  ac,
                                  pri,
                                  git_commit,
                                  ins,
                                  upd
                                ] ->
         %{
           id: id,
           project_id: proj_id,
           feature_id: feat_id,
           spec_key: spec_key,
           statement: stmt,
           rationale: rat,
           acceptance_criteria: ac,
           priority: pri,
           updated_by_git_commit: git_commit,
           inserted_at: ins,
           updated_at: upd
         }
       end)}
    end
  end

  defp query_at(query, params) do
    {query_to_run, params_to_run} = query_to_run(query, params)

    case SQL.query(Repo, query_to_run, params_to_run) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        case maybe_retry_query_with_literal_commit(query, params, error) do
          :no_retry ->
            {:error, {:dolt_query_failed, inspect(error)}}

          {:ok, result} ->
            {:ok, result}

          {:error, retry_error} ->
            {:error, {:dolt_query_failed, inspect(retry_error)}}
        end
    end
  rescue
    e -> {:error, {:dolt_query_failed, Exception.message(e)}}
  end

  defp query_to_run(query, [dolt_commit_hash, project_id] = params) do
    case query_with_literal_commit(query, dolt_commit_hash) do
      nil ->
        {query, params}

      literal_query ->
        {literal_query, [project_id]}
    end
  end

  defp query_to_run(query, params), do: {query, params}

  defp maybe_retry_query_with_literal_commit(query, [dolt_commit_hash, project_id], error) do
    literal_query = query_with_literal_commit(query, dolt_commit_hash)

    if literal_query && literal_query != query do
      case SQL.query(Repo, literal_query, [project_id]) do
        {:ok, _} = ok ->
          ok

        {:error, _} = retry_error ->
          retry_error

        _ ->
          {:error, error}
      end
    else
      :no_retry
    end
  end

  defp maybe_retry_query_with_literal_commit(_query, _params, _error), do: :no_retry

  defp query_with_literal_commit(query, dolt_commit_hash) do
    if String.contains?(query, "AS OF ?") and valid_dolt_commit_hash?(dolt_commit_hash) do
      String.replace(query, "AS OF ?", "AS OF '#{dolt_commit_hash}'")
    else
      nil
    end
  end

  defp valid_dolt_commit_hash?(dolt_commit_hash) do
    is_binary(dolt_commit_hash) and
      String.match?(dolt_commit_hash, ~r/\A[0-9a-zA-Z]{6,64}\z/)
  end

  # -- Spec run helpers -------------------------------------------------------

  defp load_spec_run(project_id, commit_hash) do
    RollingSpecRun
    |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
    |> Ash.read_one!()
  end

  defp find_previous_dolt_hash(project_id, current_run) do
    # Load all completed runs for this project with non-nil dolt_commit_hash
    runs =
      RollingSpecRun
      |> Ash.Query.filter(
        project_id == ^project_id and
          not is_nil(dolt_commit_hash) and
          id != ^current_run.id
      )
      |> Ash.read!()

    # Sort by commit timestamp, falling back to run timestamps
    commit_hashes = Enum.map(runs, & &1.commit_hash)
    commits_by_hash = load_commits_by_hash(commit_hashes)

    runs
    |> Enum.map(fn run ->
      commit = Map.get(commits_by_hash, run.commit_hash)
      sort_date = commit_sort_date(commit) || run_sort_date(run)
      {sort_date, run}
    end)
    |> Enum.filter(fn {date, _run} ->
      current_date =
        commit_sort_date(Map.get(commits_by_hash, current_run.commit_hash)) ||
          run_sort_date(current_run)

      date != nil and current_date != nil and DateTime.compare(date, current_date) == :lt
    end)
    |> Enum.sort_by(fn {date, _run} -> date end, {:desc, DateTime})
    |> List.first()
    |> case do
      {_date, run} -> run.dolt_commit_hash
      nil -> nil
    end
  end

  defp load_commits_by_hash([]), do: %{}

  defp load_commits_by_hash(hashes) do
    alias Spotter.Transcripts.Commit

    Commit
    |> Ash.Query.filter(commit_hash in ^hashes)
    |> Ash.read!()
    |> Map.new(&{&1.commit_hash, &1})
  end

  defp commit_sort_date(nil), do: nil
  defp commit_sort_date(commit), do: commit.committed_at || commit.inserted_at

  defp run_sort_date(run), do: run.started_at || run.inserted_at

  # -- Existing private helpers -----------------------------------------------

  defp list_all_requirements(project_id) do
    from(r in "product_requirements",
      where: r.project_id == ^project_id,
      order_by: [asc: r.spec_key],
      select: %{
        id: r.id,
        project_id: r.project_id,
        feature_id: r.feature_id,
        spec_key: r.spec_key,
        statement: r.statement,
        rationale: r.rationale,
        acceptance_criteria: r.acceptance_criteria,
        priority: r.priority,
        evidence_files: r.evidence_files,
        updated_by_git_commit: r.updated_by_git_commit,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize_requirement_evidence/1)
    |> Enum.group_by(& &1.feature_id)
  end
end
