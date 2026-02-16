defmodule Spotter.ProductSpec.Agent.Tools do
  @moduledoc """
  In-process MCP tools for the product specification agent.

  Defines 11 tools (domains CRUD, features CRUD+search+delete,
  requirements CRUD+search+delete) that execute SQL directly against the
  Dolt-backed `ProductSpec.Repo`.

  The current commit hash is stored in the process dictionary before the
  agent run starts (see `ToolHelpers.set_commit_hash/1`).
  """

  use ClaudeAgentSDK.Tool

  alias Spotter.Observability.ErrorReport
  alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

  # ── Domains ──

  deftool :domains_list,
          "List all product domains for the current project",
          %{type: "object", properties: %{}},
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{}) do
      pid = H.project_id!()

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, spec_key, name, description, updated_by_git_commit
          FROM product_domains WHERE project_id = ? ORDER BY name
          """,
          [pid]
        )

      H.text_result(%{domains: H.rows_to_maps(result)})
    end
  end

  deftool :domains_create,
          "Create or upsert a product domain by spec_key",
          %{
            type: "object",
            properties: %{
              spec_key: %{type: "string", description: "Unique domain key (lowercase, hyphens)"},
              name: %{type: "string", description: "Human-readable domain name"},
              description: %{type: "string", description: "Domain description"}
            },
            required: ["spec_key", "name"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"spec_key" => spec_key, "name" => name} = input) do
      pid = H.project_id!()

      case H.validate_spec_key(spec_key) do
        :ok ->
          id = Ash.UUID.generate()

          H.dolt_query!(
            """
            INSERT INTO product_domains (id, project_id, spec_key, name, description, updated_by_git_commit)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description),
              updated_by_git_commit = VALUES(updated_by_git_commit)
            """,
            [id, pid, spec_key, name, input["description"], H.commit_hash()]
          )

          H.text_result(%{ok: true, spec_key: spec_key})

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end
  end

  deftool :domains_update,
          "Update an existing product domain",
          %{
            type: "object",
            properties: %{
              domain_id: %{type: "string", description: "Domain UUID"},
              spec_key: %{type: "string", description: "New spec_key"},
              name: %{type: "string", description: "New name"},
              description: %{type: "string", description: "New description"}
            },
            required: ["domain_id"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"domain_id" => domain_id} = input) do
      pid = H.project_id!()

      case H.maybe_validate_spec_key(input["spec_key"]) do
        :ok ->
          {sets, params} = H.build_update_sets(input, ["spec_key", "name", "description"])

          if sets == [] do
            H.text_result(%{error: "no fields to update"})
          else
            sets = sets ++ ["updated_by_git_commit = ?"]
            params = params ++ [H.commit_hash(), pid, domain_id]

            H.dolt_query!(
              "UPDATE product_domains SET #{Enum.join(sets, ", ")} WHERE project_id = ? AND id = ?",
              params
            )

            H.text_result(%{ok: true})
          end

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end
  end

  # ── Features ──

  deftool :features_search,
          "Search product features by domain and/or text query",
          %{
            type: "object",
            properties: %{
              domain_id: %{type: "string", description: "Filter by domain UUID"},
              q: %{
                type: "string",
                description: "Substring search on spec_key, name, or description"
              }
            }
          },
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{} = input) do
      pid = H.project_id!()
      {where, params} = {["project_id = ?"], [pid]}

      {where, params} =
        if input["domain_id"] do
          {where ++ ["domain_id = ?"], params ++ [input["domain_id"]]}
        else
          {where, params}
        end

      {where, params} =
        if input["q"] do
          like = "%#{input["q"]}%"

          {where ++ ["(spec_key LIKE ? OR name LIKE ? OR description LIKE ?)"],
           params ++ [like, like, like]}
        else
          {where, params}
        end

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, domain_id, spec_key, name, description, updated_by_git_commit
          FROM product_features WHERE #{Enum.join(where, " AND ")} ORDER BY name
          """,
          params
        )

      H.text_result(%{features: H.rows_to_maps(result)})
    end
  end

  deftool :features_create,
          "Create or upsert a product feature by (domain_id, spec_key)",
          %{
            type: "object",
            properties: %{
              domain_id: %{type: "string", description: "Parent domain UUID"},
              spec_key: %{type: "string", description: "Unique feature key within domain"},
              name: %{type: "string", description: "Human-readable feature name"},
              description: %{type: "string", description: "Feature description"}
            },
            required: ["domain_id", "spec_key", "name"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"domain_id" => did, "spec_key" => sk, "name" => name} = input) do
      pid = H.project_id!()

      with :ok <- H.validate_spec_key(sk),
           :ok <- H.verify_domain_belongs_to_project(did, pid) do
        id = Ash.UUID.generate()

        H.dolt_query!(
          """
          INSERT INTO product_features (id, project_id, domain_id, spec_key, name, description, updated_by_git_commit)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description),
            updated_by_git_commit = VALUES(updated_by_git_commit)
          """,
          [id, pid, did, sk, name, input["description"], H.commit_hash()]
        )

        H.text_result(%{ok: true, spec_key: sk})
      else
        {:error, msg} -> H.text_result(%{error: msg})
      end
    end
  end

  deftool :features_update,
          "Update an existing product feature",
          %{
            type: "object",
            properties: %{
              feature_id: %{type: "string", description: "Feature UUID"},
              domain_id: %{type: "string", description: "New parent domain UUID"},
              spec_key: %{type: "string", description: "New spec_key"},
              name: %{type: "string", description: "New name"},
              description: %{type: "string", description: "New description"}
            },
            required: ["feature_id"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"feature_id" => feature_id} = input) do
      pid = H.project_id!()

      with :ok <- H.maybe_validate_spec_key(input["spec_key"]),
           :ok <-
             if(input["domain_id"],
               do: H.verify_domain_belongs_to_project(input["domain_id"], pid),
               else: :ok
             ) do
        {sets, params} =
          H.build_update_sets(input, ["domain_id", "spec_key", "name", "description"])

        if sets == [] do
          H.text_result(%{error: "no fields to update"})
        else
          sets = sets ++ ["updated_by_git_commit = ?"]
          params = params ++ [H.commit_hash(), pid, feature_id]

          H.dolt_query!(
            "UPDATE product_features SET #{Enum.join(sets, ", ")} WHERE project_id = ? AND id = ?",
            params
          )

          H.text_result(%{ok: true})
        end
      else
        {:error, msg} -> H.text_result(%{error: msg})
      end
    end
  end

  deftool :features_delete,
          "Delete a product feature and its requirements",
          %{
            type: "object",
            properties: %{
              feature_id: %{type: "string", description: "Feature UUID to delete"}
            },
            required: ["feature_id"]
          },
          annotations: %{destructiveHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"feature_id" => feature_id}) do
      pid = H.project_id!()

      H.dolt_query!(
        "DELETE FROM product_requirements WHERE project_id = ? AND feature_id = ?",
        [pid, feature_id]
      )

      H.dolt_query!(
        "DELETE FROM product_features WHERE project_id = ? AND id = ?",
        [pid, feature_id]
      )

      H.text_result(%{ok: true})
    end
  end

  # ── Requirements ──

  deftool :requirements_search,
          "Search product requirements by feature and/or text query",
          %{
            type: "object",
            properties: %{
              feature_id: %{type: "string", description: "Filter by feature UUID"},
              q: %{
                type: "string",
                description: "Substring search on spec_key, statement, or rationale"
              }
            }
          },
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{} = input) do
      pid = H.project_id!()
      {where, params} = {["project_id = ?"], [pid]}

      {where, params} =
        if input["feature_id"] do
          {where ++ ["feature_id = ?"], params ++ [input["feature_id"]]}
        else
          {where, params}
        end

      {where, params} =
        if input["q"] do
          like = "%#{input["q"]}%"

          {where ++ ["(spec_key LIKE ? OR statement LIKE ? OR rationale LIKE ?)"],
           params ++ [like, like, like]}
        else
          {where, params}
        end

      result =
        H.dolt_query!(
          """
          SELECT id, project_id, feature_id, spec_key, statement, rationale,
                 acceptance_criteria, priority, evidence_files, updated_by_git_commit
          FROM product_requirements WHERE #{Enum.join(where, " AND ")} ORDER BY spec_key
          """,
          params
        )

      H.text_result(%{requirements: H.rows_to_maps(result)})
    end
  end

  deftool :requirements_create,
          "Create or upsert a product requirement by (feature_id, spec_key)",
          %{
            type: "object",
            properties: %{
              feature_id: %{type: "string", description: "Parent feature UUID"},
              spec_key: %{type: "string", description: "Unique requirement key within feature"},
              statement: %{
                type: "string",
                description: "Requirement statement (must include 'shall')"
              },
              rationale: %{type: "string", description: "Why this requirement exists"},
              acceptance_criteria: %{
                type: "array",
                items: %{type: "string"},
                description: "List of acceptance criteria"
              },
              priority: %{type: "string", description: "Priority level"},
              evidence_files: %{
                type: "array",
                items: %{type: "string"},
                description: "Repo-relative file paths that evidence this requirement"
              }
            },
            required: ["feature_id", "spec_key", "statement"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(
          %{
            "feature_id" => fid,
            "spec_key" => sk,
            "statement" => statement
          } = input
        ) do
      pid = H.project_id!()
      ev_files = input["evidence_files"] || []

      with :ok <- H.validate_spec_key(sk),
           :ok <- H.validate_shall(statement),
           :ok <- H.validate_evidence_files(ev_files),
           :ok <- H.verify_feature_belongs_to_project(fid, pid) do
        id = Ash.UUID.generate()
        ac_json = if input["acceptance_criteria"], do: Jason.encode!(input["acceptance_criteria"])
        ev_json = if ev_files != [], do: Jason.encode!(ev_files)

        H.dolt_query!(
          """
          INSERT INTO product_requirements
            (id, project_id, feature_id, spec_key, statement, rationale, acceptance_criteria, priority, evidence_files, updated_by_git_commit)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE statement = VALUES(statement), rationale = VALUES(rationale),
            acceptance_criteria = VALUES(acceptance_criteria), priority = VALUES(priority),
            evidence_files = VALUES(evidence_files),
            updated_by_git_commit = VALUES(updated_by_git_commit)
          """,
          [
            id,
            pid,
            fid,
            sk,
            statement,
            input["rationale"],
            ac_json,
            input["priority"],
            ev_json,
            H.commit_hash()
          ]
        )

        H.text_result(%{ok: true, spec_key: sk})
      else
        {:error, msg} -> H.text_result(%{error: msg})
      end
    end
  end

  deftool :requirements_update,
          "Update an existing product requirement",
          %{
            type: "object",
            properties: %{
              requirement_id: %{type: "string", description: "Requirement UUID"},
              spec_key: %{type: "string", description: "New spec_key"},
              statement: %{type: "string", description: "New statement (must include 'shall')"},
              rationale: %{type: "string", description: "New rationale"},
              acceptance_criteria: %{
                type: "array",
                items: %{type: "string"},
                description: "New acceptance criteria"
              },
              priority: %{type: "string", description: "New priority"},
              evidence_files: %{
                type: "array",
                items: %{type: "string"},
                description: "Repo-relative file paths (replaces existing evidence)"
              }
            },
            required: ["requirement_id"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"requirement_id" => requirement_id} = input) do
      pid = H.project_id!()
      ev_files = input["evidence_files"]

      with :ok <- H.maybe_validate_spec_key(input["spec_key"]),
           :ok <- H.maybe_validate_shall(input["statement"]),
           :ok <- if(ev_files, do: H.validate_evidence_files(ev_files), else: :ok) do
        {sets, params} =
          H.build_update_sets(input, ["spec_key", "statement", "rationale", "priority"])

        {sets, params} =
          if input["acceptance_criteria"] do
            {sets ++ ["acceptance_criteria = ?"],
             params ++ [Jason.encode!(input["acceptance_criteria"])]}
          else
            {sets, params}
          end

        {sets, params} =
          if ev_files do
            {sets ++ ["evidence_files = ?"], params ++ [Jason.encode!(ev_files)]}
          else
            {sets, params}
          end

        if sets == [] do
          H.text_result(%{error: "no fields to update"})
        else
          sets = sets ++ ["updated_by_git_commit = ?"]
          params = params ++ [H.commit_hash(), pid, requirement_id]

          H.dolt_query!(
            "UPDATE product_requirements SET #{Enum.join(sets, ", ")} WHERE project_id = ? AND id = ?",
            params
          )

          H.text_result(%{ok: true})
        end
      else
        {:error, msg} -> H.text_result(%{error: msg})
      end
    end
  end

  deftool :requirements_delete,
          "Delete a product requirement",
          %{
            type: "object",
            properties: %{
              requirement_id: %{type: "string", description: "Requirement UUID to delete"}
            },
            required: ["requirement_id"]
          },
          annotations: %{destructiveHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"requirement_id" => requirement_id}) do
      pid = H.project_id!()

      H.dolt_query!(
        "DELETE FROM product_requirements WHERE project_id = ? AND id = ?",
        [pid, requirement_id]
      )

      H.text_result(%{ok: true})
    end
  end

  deftool :requirements_add_evidence_files,
          "Append additional evidence files to an existing requirement (union, de-duped)",
          %{
            type: "object",
            properties: %{
              requirement_id: %{type: "string", description: "Requirement UUID"},
              files: %{
                type: "array",
                items: %{type: "string"},
                description: "Repo-relative file paths to add as evidence"
              }
            },
            required: ["requirement_id", "files"]
          } do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"requirement_id" => rid, "files" => new_files}) do
      pid = H.project_id!()

      case H.validate_evidence_files(new_files) do
        :ok ->
          result =
            H.dolt_query!(
              "SELECT evidence_files FROM product_requirements WHERE project_id = ? AND id = ?",
              [pid, rid]
            )

          case result.rows do
            [[existing_json]] ->
              existing = parse_evidence(existing_json)
              existing_set = MapSet.new(existing)
              merged = existing ++ Enum.reject(new_files, &MapSet.member?(existing_set, &1))
              merged_json = Jason.encode!(merged)

              H.dolt_query!(
                "UPDATE product_requirements SET evidence_files = ?, updated_by_git_commit = ? WHERE project_id = ? AND id = ?",
                [merged_json, H.commit_hash(), pid, rid]
              )

              H.text_result(%{ok: true, evidence_files: merged})

            _ ->
              H.text_result(%{error: "requirement not found"})
          end

        {:error, msg} ->
          H.text_result(%{error: msg})
      end
    end

    defp parse_evidence(nil), do: []

    defp parse_evidence(json) when is_binary(json) do
      case Jason.decode(json) do
        {:ok, list} when is_list(list) -> Enum.filter(list, &is_binary/1)
        _ -> []
      end
    end

    defp parse_evidence(_), do: []
  end

  # ── Git repo inspection (read-only) ──

  deftool :repo_read_file_at_commit,
          "Read a file from the repository at a specific commit",
          %{
            type: "object",
            properties: %{
              commit_hash: %{type: "string", description: "Git commit hash"},
              relative_path: %{type: "string", description: "Repo-relative file path"},
              max_chars: %{
                type: "integer",
                description: "Maximum characters to return (default 60000)"
              }
            },
            required: ["commit_hash", "relative_path"]
          },
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    require OpenTelemetry.Tracer, as: Tracer

    def execute(%{"commit_hash" => hash, "relative_path" => path} = input) do
      max_chars = input["max_chars"] || 60_000
      cwd = H.git_cwd()

      Tracer.with_span "spotter.product_spec.repo_read_file" do
        Tracer.set_attribute("spotter.commit_hash", hash)
        Tracer.set_attribute("spotter.relative_path", path)

        case git_show(cwd, hash, path) do
          {:ok, content} ->
            truncated = byte_size(content) > max_chars

            content =
              if truncated, do: String.slice(content, 0, max_chars), else: content

            H.text_result(%{
              ok: true,
              relative_path: path,
              commit_hash: hash,
              content: content,
              truncated: truncated
            })

          {:error, reason} ->
            ErrorReport.set_trace_error("git_show_error", reason, "product_spec.agent.tools")

            H.text_result(%{
              ok: false,
              relative_path: path,
              commit_hash: hash,
              error: reason
            })
        end
      end
    end

    defp git_show(nil, _hash, _path), do: {:error, "git_cwd not available"}

    defp git_show(cwd, hash, path) do
      case System.cmd("git", ["-C", cwd, "show", "#{hash}:#{path}"], stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, String.trim(output)}
      end
    end
  end

  deftool :repo_list_files_at_commit,
          "List files in the repository at a specific commit",
          %{
            type: "object",
            properties: %{
              commit_hash: %{type: "string", description: "Git commit hash"},
              q: %{type: "string", description: "Substring filter on file paths"},
              limit: %{
                type: "integer",
                description: "Maximum files to return (default 200)"
              }
            },
            required: ["commit_hash"]
          },
          annotations: %{readOnlyHint: true} do
    alias Spotter.ProductSpec.Agent.ToolHelpers, as: H

    def execute(%{"commit_hash" => hash} = input) do
      limit = input["limit"] || 200
      q = input["q"]
      cwd = H.git_cwd()

      case git_ls_tree(cwd, hash) do
        {:ok, files} ->
          files = if q, do: Enum.filter(files, &String.contains?(&1, q)), else: files
          truncated = length(files) > limit
          files = Enum.take(files, limit)
          H.text_result(%{ok: true, files: files, truncated: truncated})

        {:error, reason} ->
          H.text_result(%{ok: false, files: [], error: reason})
      end
    end

    defp git_ls_tree(nil, _hash), do: {:error, "git_cwd not available"}

    defp git_ls_tree(cwd, hash) do
      case System.cmd("git", ["-C", cwd, "ls-tree", "-r", "--name-only", hash],
             stderr_to_stdout: true
           ) do
        {output, 0} -> {:ok, output |> String.trim() |> String.split("\n", trim: true)}
        {output, _} -> {:error, String.trim(output)}
      end
    end
  end

  @doc "Returns all tool modules for MCP server registration."
  def all_tool_modules do
    __MODULE__
    |> ClaudeAgentSDK.Tool.list_tools()
    |> Enum.map(& &1.module)
  end
end
