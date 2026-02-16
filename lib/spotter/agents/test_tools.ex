defmodule Spotter.Agents.TestTools do
  @moduledoc """
  In-process MCP tools for syncing test specs per file.

  Defines CRUD tools that the Claude Agent SDK agent uses to keep
  Spotter's stored tests in sync with actual test files.
  Persistence is backed by Dolt `test_specs` table.
  """

  use ClaudeAgentSDK.Tool

  require OpenTelemetry.Tracer, as: Tracer

  # ── List ──

  deftool :list_tests,
          "List all stored tests for a given project and file path",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"}
            },
            required: ["project_id", "relative_path"]
          },
          annotations: %{readOnlyHint: true} do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools
    alias Spotter.TestSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "relative_path" => relative_path}) do
      Tracer.with_span "spotter.commit_tests.tool.list_tests" do
        case H.validate_project_scope(project_id) do
          {:error, mismatch} ->
            H.text_result(mismatch)

          {:ok, pid} ->
            Tracer.set_attribute("spotter.project_id", pid)
            Tracer.set_attribute("spotter.relative_path", relative_path)
            Tracer.set_attribute("spotter.storage_backend", "dolt")

            result =
              H.dolt_query!(
                """
                SELECT id, project_id, test_key, relative_path, framework,
                       describe_path_json, test_name, line_start, line_end,
                       given_json, when_json, then_json, confidence,
                       metadata_json, source_commit_hash, updated_by_git_commit
                FROM test_specs
                WHERE project_id = ? AND relative_path = ?
                ORDER BY describe_path_json, test_name, line_start, framework
                """,
                [pid, relative_path]
              )

            tests = Enum.map(H.rows_to_maps(result), &TestTools.deserialize_row/1)
            H.text_result(%{tests: tests})
        end
      end
    end
  end

  # ── Create ──

  deftool :create_test,
          "Create a new test case record for a file",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"},
              framework: %{type: "string", description: "Test framework (e.g. ExUnit, Jest)"},
              describe_path: %{
                type: "array",
                items: %{type: "string"},
                description: "Nesting path of describe blocks"
              },
              test_name: %{type: "string", description: "Test name"},
              line_start: %{type: "integer", description: "Start line number"},
              line_end: %{type: "integer", description: "End line number"},
              given: %{
                type: "array",
                items: %{type: "string"},
                description: "Given preconditions"
              },
              when: %{type: "array", items: %{type: "string"}, description: "When actions"},
              then: %{type: "array", items: %{type: "string"}, description: "Then assertions"},
              confidence: %{type: "number", description: "Extraction confidence 0.0-1.0"},
              metadata: %{type: "object", description: "Arbitrary metadata"},
              source_commit_hash: %{
                type: "string",
                description: "Git commit hash this test was extracted from (required)"
              }
            },
            required: ["project_id", "relative_path", "framework", "test_name"]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.TestSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "relative_path" => relative_path} = input) do
      Tracer.with_span "spotter.commit_tests.tool.create_test" do
        case H.validate_project_scope(project_id) do
          {:error, mismatch} ->
            H.text_result(mismatch)

          {:ok, pid} ->
            Tracer.set_attribute("spotter.project_id", pid)
            Tracer.set_attribute("spotter.relative_path", relative_path)
            Tracer.set_attribute("spotter.storage_backend", "dolt")

            framework = input["framework"]
            describe_path = input["describe_path"] || []
            test_name = input["test_name"]
            test_key = H.build_test_key(framework, relative_path, describe_path, test_name)
            commit_hash = input["source_commit_hash"] || H.commit_hash()

            H.dolt_query!(
              """
              INSERT INTO test_specs (
                project_id, test_key, relative_path, framework,
                describe_path_json, test_name, line_start, line_end,
                given_json, when_json, then_json, confidence,
                metadata_json, source_commit_hash, updated_by_git_commit
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON DUPLICATE KEY UPDATE
                relative_path = VALUES(relative_path),
                framework = VALUES(framework),
                describe_path_json = VALUES(describe_path_json),
                test_name = VALUES(test_name),
                line_start = VALUES(line_start),
                line_end = VALUES(line_end),
                given_json = VALUES(given_json),
                when_json = VALUES(when_json),
                then_json = VALUES(then_json),
                confidence = VALUES(confidence),
                metadata_json = VALUES(metadata_json),
                source_commit_hash = VALUES(source_commit_hash),
                updated_by_git_commit = VALUES(updated_by_git_commit)
              """,
              [
                pid,
                test_key,
                relative_path,
                framework,
                Jason.encode!(describe_path),
                test_name,
                input["line_start"],
                input["line_end"],
                Jason.encode!(input["given"] || []),
                Jason.encode!(input["when"] || []),
                Jason.encode!(input["then"] || []),
                input["confidence"],
                Jason.encode!(input["metadata"] || %{}),
                input["source_commit_hash"],
                commit_hash
              ]
            )

            # Re-read the upserted row
            row = load_by_key!(pid, test_key)
            H.text_result(%{test: row})
        end
      end
    end

    defp load_by_key!(project_id, test_key) do
      alias Spotter.Agents.TestTools
      alias Spotter.TestSpec.Agent.ToolHelpers, as: H

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, test_key, relative_path, framework,
                 describe_path_json, test_name, line_start, line_end,
                 given_json, when_json, then_json, confidence,
                 metadata_json, source_commit_hash, updated_by_git_commit
          FROM test_specs
          WHERE project_id = ? AND test_key = ?
          LIMIT 1
          """,
          [project_id, test_key]
        )

      result |> H.rows_to_maps() |> List.first() |> TestTools.deserialize_row()
    end
  end

  # ── Update ──

  deftool :update_test,
          "Update an existing test case record",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"},
              test_id: %{type: "string", description: "Test spec row ID"},
              patch: %{
                type: "object",
                description:
                  "Fields to update: framework, describe_path, test_name, line_start, line_end, given, when, then, confidence, metadata, source_commit_hash"
              }
            },
            required: ["project_id", "relative_path", "test_id", "patch"]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools
    alias Spotter.TestSpec.Agent.ToolHelpers, as: H

    @patch_fields ~w(framework describe_path test_name line_start line_end given when then confidence metadata source_commit_hash)

    def execute(%{
          "project_id" => project_id,
          "relative_path" => relative_path,
          "test_id" => test_id,
          "patch" => patch
        }) do
      Tracer.with_span "spotter.commit_tests.tool.update_test" do
        case H.validate_project_scope(project_id) do
          {:error, mismatch} ->
            H.text_result(mismatch)

          {:ok, pid} ->
            Tracer.set_attribute("spotter.project_id", pid)
            Tracer.set_attribute("spotter.relative_path", relative_path)
            Tracer.set_attribute("spotter.test_id", test_id)
            Tracer.set_attribute("spotter.storage_backend", "dolt")

            do_update(pid, relative_path, test_id, patch)
        end
      end
    end

    defp do_update(pid, relative_path, test_id, patch) do
      alias Spotter.Agents.TestTools
      alias Spotter.TestSpec.Agent.ToolHelpers, as: H

      case load_by_id(pid, relative_path, test_id) do
        nil ->
          H.text_result(%{error: "test_not_found"})

        _existing ->
          {sets, params} = build_update(patch)
          apply_update(pid, relative_path, test_id, sets, params)
      end
    end

    defp apply_update(pid, relative_path, test_id, [] = _sets, _params) do
      alias Spotter.Agents.TestTools
      alias Spotter.TestSpec.Agent.ToolHelpers, as: H

      row = load_by_id(pid, relative_path, test_id)
      H.text_result(%{test: TestTools.deserialize_row(row)})
    end

    defp apply_update(pid, relative_path, test_id, sets, params) do
      alias Spotter.Agents.TestTools
      alias Spotter.TestSpec.Agent.ToolHelpers, as: H

      sql = "UPDATE test_specs SET #{Enum.join(sets, ", ")} WHERE id = ?"
      H.dolt_query!(sql, params ++ [String.to_integer(test_id)])

      row = load_by_id(pid, relative_path, test_id)
      H.text_result(%{test: TestTools.deserialize_row(row)})
    end

    defp load_by_id(project_id, relative_path, test_id) do
      alias Spotter.TestSpec.Agent.ToolHelpers, as: H

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, test_key, relative_path, framework,
                 describe_path_json, test_name, line_start, line_end,
                 given_json, when_json, then_json, confidence,
                 metadata_json, source_commit_hash, updated_by_git_commit
          FROM test_specs
          WHERE id = ? AND project_id = ? AND relative_path = ?
          LIMIT 1
          """,
          [String.to_integer(test_id), project_id, relative_path]
        )

      result |> H.rows_to_maps() |> List.first()
    end

    @json_fields ~w(describe_path given when then metadata)

    defp build_update(patch) do
      Enum.reduce(@patch_fields, {[], []}, fn field, {sets, params} ->
        case patch[field] do
          nil -> {sets, params}
          value -> build_update_field(field, value, sets, params)
        end
      end)
    end

    defp build_update_field("source_commit_hash", value, sets, params) do
      {sets ++ ["source_commit_hash = ?", "updated_by_git_commit = ?"], params ++ [value, value]}
    end

    defp build_update_field(field, value, sets, params) when field in @json_fields do
      col = "#{field}_json"
      {sets ++ ["#{col} = ?"], params ++ [Jason.encode!(value)]}
    end

    defp build_update_field(field, value, sets, params) do
      {sets ++ ["#{field} = ?"], params ++ [value]}
    end
  end

  # ── Delete ──

  deftool :delete_test,
          "Delete a test case record",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              relative_path: %{type: "string", description: "File path relative to project root"},
              test_id: %{type: "string", description: "Test spec row ID"}
            },
            required: ["project_id", "relative_path", "test_id"]
          },
          annotations: %{destructiveHint: true} do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.TestSpec.Agent.ToolHelpers, as: H

    def execute(%{
          "project_id" => project_id,
          "relative_path" => relative_path,
          "test_id" => test_id
        }) do
      Tracer.with_span "spotter.commit_tests.tool.delete_test" do
        case H.validate_project_scope(project_id) do
          {:error, mismatch} ->
            H.text_result(mismatch)

          {:ok, pid} ->
            Tracer.set_attribute("spotter.project_id", pid)
            Tracer.set_attribute("spotter.relative_path", relative_path)
            Tracer.set_attribute("spotter.test_id", test_id)
            Tracer.set_attribute("spotter.storage_backend", "dolt")

            H.dolt_query!(
              "DELETE FROM test_specs WHERE id = ? AND project_id = ? AND relative_path = ?",
              [String.to_integer(test_id), pid, relative_path]
            )

            H.text_result(%{ok: true})
        end
      end
    end
  end

  # ── List Spec Requirements (read-only, silent fallback) ──

  deftool :list_spec_requirements,
          "List product spec requirements available for the given project and commit. Returns empty list when spec data is unavailable.",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              commit_hash: %{type: "string", description: "Git commit hash (40 hex chars)"}
            },
            required: ["project_id", "commit_hash"]
          },
          annotations: %{readOnlyHint: true} do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools, as: TTools
    alias Spotter.TestSpec.Agent.ToolHelpers, as: H

    def execute(%{"project_id" => project_id, "commit_hash" => commit_hash}) do
      Tracer.with_span "spotter.commit_tests.tool.list_spec_requirements" do
        case H.validate_project_scope(project_id) do
          {:error, mismatch} ->
            H.text_result(mismatch)

          {:ok, pid} ->
            Tracer.set_attribute("spotter.project_id", pid)
            Tracer.set_attribute("spotter.commit_hash", commit_hash)

            requirements = TTools.fetch_spec_requirements(pid, commit_hash)
            Tracer.set_attribute("spotter.requirement_count", length(requirements))

            H.text_result(%{requirements: requirements})
        end
      end
    end
  end

  # ── Upsert Spec-Test Links ──

  deftool :upsert_spec_test_links,
          "Create or update associations between product requirements and test cases for a commit.",
          %{
            type: "object",
            properties: %{
              project_id: %{type: "string", description: "Project UUID"},
              commit_hash: %{type: "string", description: "Git commit hash (40 hex chars)"},
              links: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    requirement_spec_key: %{
                      type: "string",
                      description: "Spec key of the product requirement"
                    },
                    test_key: %{
                      type: "string",
                      description: "Test key (framework::path::describe_path::name)"
                    },
                    confidence: %{
                      type: "number",
                      description: "Link confidence 0.0-1.0 (default 1.0)"
                    }
                  },
                  required: ["requirement_spec_key", "test_key"]
                },
                description: "Array of requirement-test associations to upsert"
              }
            },
            required: ["project_id", "commit_hash", "links"]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.TestTools, as: TTools
    alias Spotter.TestSpec.Agent.ToolHelpers, as: H

    def execute(%{
          "project_id" => project_id,
          "commit_hash" => commit_hash,
          "links" => links
        }) do
      Tracer.with_span "spotter.commit_tests.tool.upsert_spec_test_links" do
        case H.validate_project_scope(project_id) do
          {:error, mismatch} ->
            H.text_result(mismatch)

          {:ok, pid} ->
            Tracer.set_attribute("spotter.project_id", pid)
            Tracer.set_attribute("spotter.commit_hash", commit_hash)
            Tracer.set_attribute("spotter.link_count", length(links))

            results = TTools.upsert_links(pid, commit_hash, links)
            H.text_result(%{upserted: results.ok, skipped: results.skipped})
        end
      end
    end
  end

  @doc false
  def fetch_spec_requirements(project_id, commit_hash) do
    case Spotter.ProductSpec.tree_for_commit(project_id, commit_hash) do
      {:ok, %{tree: tree}} ->
        flatten_requirements(tree)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp flatten_requirements(tree) do
    Enum.flat_map(tree, &flatten_domain/1)
  end

  defp flatten_domain(domain) do
    domain
    |> Map.get(:features, [])
    |> Enum.flat_map(&flatten_feature(&1, domain.name))
  end

  defp flatten_feature(feature, domain_name) do
    feature
    |> Map.get(:requirements, [])
    |> Enum.map(fn req ->
      %{
        spec_key: req.spec_key,
        statement: req.statement,
        feature_name: feature.name,
        domain_name: domain_name
      }
    end)
  end

  @doc false
  def upsert_links(project_id, commit_hash, links) do
    Enum.reduce(links, %{ok: 0, skipped: 0}, fn link, acc ->
      upsert_single_link(project_id, commit_hash, link, acc)
    end)
  end

  defp upsert_single_link(project_id, commit_hash, link, acc) do
    req_key = link["requirement_spec_key"]
    test_key = link["test_key"]

    if valid_link_keys?(req_key, test_key) do
      do_upsert_link(project_id, commit_hash, req_key, test_key, link["confidence"], acc)
    else
      %{acc | skipped: acc.skipped + 1}
    end
  end

  defp valid_link_keys?(req_key, test_key) do
    is_binary(req_key) and req_key != "" and is_binary(test_key) and test_key != ""
  end

  defp do_upsert_link(project_id, commit_hash, req_key, test_key, confidence, acc) do
    case Ash.create(Spotter.Transcripts.SpecTestLink, %{
           project_id: project_id,
           commit_hash: commit_hash,
           requirement_spec_key: req_key,
           test_key: test_key,
           confidence: confidence || 1.0,
           source: :agent
         }) do
      {:ok, _} -> %{acc | ok: acc.ok + 1}
      _ -> %{acc | skipped: acc.skipped + 1}
    end
  end

  @doc "Returns all tool modules for MCP server registration."
  def all_tool_modules do
    __MODULE__
    |> ClaudeAgentSDK.Tool.list_tools()
    |> Enum.map(& &1.module)
  end

  @doc false
  def deserialize_row(row) when is_map(row) do
    %{
      id: to_string(row["id"]),
      project_id: row["project_id"],
      test_key: row["test_key"],
      relative_path: row["relative_path"],
      framework: row["framework"],
      describe_path: decode_json(row["describe_path_json"], []),
      test_name: row["test_name"],
      line_start: row["line_start"],
      line_end: row["line_end"],
      given: decode_json(row["given_json"], []),
      when: decode_json(row["when_json"], []),
      then: decode_json(row["then_json"], []),
      confidence: row["confidence"],
      metadata: decode_json(row["metadata_json"], %{}),
      source_commit_hash: row["source_commit_hash"],
      updated_by_git_commit: row["updated_by_git_commit"]
    }
  end

  defp decode_json(nil, default), do: default
  defp decode_json(val, _default) when is_list(val), do: val
  defp decode_json(val, _default) when is_map(val), do: val

  defp decode_json(val, default) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, decoded} -> decoded
      _ -> default
    end
  end

  defp decode_json(_, default), do: default
end
