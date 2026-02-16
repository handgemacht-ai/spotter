defmodule SpotterWeb.Live.SpecsComputers do
  @moduledoc """
  AshComputer definitions for the merged Specs page.

  Provides reactive pipelines for commit timeline, product/test detail loading,
  and artifact switching from a single URL-driven page.
  """
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  use AshComputer

  computer :specs_view do
    input :project_id do
      initial nil
    end

    input :commit_id do
      initial nil
    end

    input :artifact do
      initial :product
    end

    input :spec_view do
      initial :diff
    end

    input :search_query do
      initial ""
    end

    input :commit_cursor do
      initial nil
    end

    val :project do
      compute(fn
        %{project_id: nil} ->
          nil

        %{project_id: project_id} ->
          case Ash.get(Spotter.Transcripts.Project, project_id) do
            {:ok, project} -> project
            _ -> nil
          end
      end)

      depends_on([:project_id])
    end

    val :commit_rows do
      compute(fn
        %{project_id: nil} ->
          []

        %{project_id: project_id} ->
          result =
            try do
              product_result =
                Spotter.Services.ProductCommitTimeline.list(%{project_id: project_id})

              test_result =
                Spotter.Services.TestCommitTimeline.list(%{project_id: project_id})

              test_runs_by_commit_id =
                Map.new(test_result.rows, &{&1.commit.id, &1.test_run})

              rows =
                Enum.map(product_result.rows, fn row ->
                  %{
                    commit: row.commit,
                    spec_run: row.spec_run,
                    test_run: Map.get(test_runs_by_commit_id, row.commit.id)
                  }
                end)

              %{rows: rows, cursor: product_result.cursor, has_more: product_result.has_more}
            rescue
              _ -> %{rows: [], cursor: nil, has_more: false}
            end

          result.rows
      end)

      depends_on([:project_id])
    end

    val :selected_commit do
      compute(fn
        %{commit_id: nil} ->
          nil

        %{commit_id: commit_id} ->
          case Ash.get(Spotter.Transcripts.Commit, commit_id) do
            {:ok, commit} -> commit
            _ -> nil
          end
      end)

      depends_on([:commit_id])
    end

    val :product_dolt_available do
      compute(fn _ ->
        Spotter.ProductSpec.dolt_available?()
      end)

      depends_on([])
    end

    val :tests_dolt_available do
      compute(fn _ ->
        Spotter.TestSpec.dolt_available?()
      end)

      depends_on([])
    end

    val :product_detail do
      compute(fn
        %{selected_commit: nil} ->
          nil

        %{product_dolt_available: false} ->
          nil

        %{selected_commit: commit, project_id: project_id, spec_view: :diff} ->
          case Spotter.ProductSpec.diff_for_commit(project_id, commit.commit_hash) do
            {:ok, diff} -> %{content: diff, error: nil}
            {:error, reason} -> %{content: nil, error: reason}
          end

        %{selected_commit: commit, project_id: project_id, spec_view: :snapshot} ->
          case Spotter.ProductSpec.tree_for_commit(project_id, commit.commit_hash) do
            {:ok, result} -> %{content: result, error: nil}
            {:error, reason} -> %{content: nil, error: reason}
          end
      end)

      depends_on([:selected_commit, :project_id, :spec_view, :product_dolt_available])
    end

    val :tests_detail do
      compute(fn
        %{selected_commit: nil} ->
          nil

        %{tests_dolt_available: false} ->
          nil

        %{selected_commit: commit, project_id: project_id, spec_view: :diff} ->
          case Spotter.TestSpec.diff_for_commit(project_id, commit.commit_hash) do
            {:ok, diff} -> %{content: diff, error: nil}
            {:error, reason} -> %{content: nil, error: reason}
          end

        %{selected_commit: commit, project_id: project_id, spec_view: :snapshot} ->
          case Spotter.TestSpec.tree_for_commit(project_id, commit.commit_hash) do
            {:ok, result} -> %{content: result, error: nil}
            {:error, reason} -> %{content: nil, error: reason}
          end
      end)

      depends_on([:selected_commit, :project_id, :spec_view, :tests_dolt_available])
    end

    val :active_detail do
      compute(fn
        %{artifact: :product, product_detail: detail} -> detail
        %{artifact: :tests, tests_detail: detail} -> detail
        _ -> nil
      end)

      depends_on([:artifact, :product_detail, :tests_detail])
    end

    val :error_state do
      compute(fn
        %{project_id: nil} -> :no_project
        %{commit_id: nil} -> nil
        %{selected_commit: nil, commit_id: cid} when not is_nil(cid) -> :commit_not_found
        _ -> nil
      end)

      depends_on([:project_id, :commit_id, :selected_commit])
    end
  end
end
