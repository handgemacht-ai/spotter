defmodule Spotter.ProductSpec.Agent.ToolsTest do
  @moduledoc """
  Integration tests for the spec agent tools against a live Dolt instance.

  Requires:
  - Dolt running: `docker compose -f docker-compose.dolt.yml up -d`
  - Schema created (auto on app start with SPOTTER_PRODUCT_SPEC_ENABLED=true)

  Run with: mix test test/spotter/product_spec/agent/tools_test.exs --include live_dolt
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.Agent.ToolHelpers
  alias Spotter.ProductSpec.Agent.Tools
  alias Spotter.ProductSpec.Repo
  alias Spotter.ProductSpec.Schema

  @moduletag :live_dolt

  @project_id "00000000-0000-0000-0000-000000000099"
  @commit_hash String.duplicate("a", 40)

  setup_all do
    # Ensure schema exists (the app supervisor may have started before Dolt was ready)
    Schema.ensure_schema!()
    :ok
  end

  setup do
    ToolHelpers.set_commit_hash(@commit_hash)

    # Clean up test data before each test
    SQL.query!(Repo, "DELETE FROM product_requirements WHERE project_id = ?", [@project_id])
    SQL.query!(Repo, "DELETE FROM product_features WHERE project_id = ?", [@project_id])
    SQL.query!(Repo, "DELETE FROM product_domains WHERE project_id = ?", [@project_id])

    :ok
  end

  describe "tool registration" do
    test "all_tool_modules returns 14 tool modules" do
      tools = Tools.all_tool_modules()
      assert length(tools) == 14
    end

    test "MCP server can be created with all tools" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "test-spec-tools",
          version: "1.0.0",
          tools: Tools.all_tool_modules()
        )

      assert server.name == "test-spec-tools"
    end
  end

  describe "domains" do
    test "domains_list returns empty list for new project" do
      {:ok, result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      parsed = decode_text_result(result)
      assert parsed["domains"] == []
    end

    test "domains_create inserts a domain" do
      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "auth-system",
          "name" => "Authentication"
        })

      {:ok, result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      parsed = decode_text_result(result)
      assert length(parsed["domains"]) == 1
      [domain] = parsed["domains"]
      assert domain["name"] == "Authentication"
      assert domain["spec_key"] == "auth-system"
      assert domain["updated_by_git_commit"] == @commit_hash
    end

    test "domains_create rejects invalid spec_key" do
      {:ok, result} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "INVALID KEY",
          "name" => "Bad"
        })

      parsed = decode_text_result(result)
      assert parsed["error"] =~ "spec_key must match"
    end

    test "domains_create upserts on duplicate spec_key" do
      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "ui-layer",
          "name" => "UI"
        })

      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "ui-layer",
          "name" => "User Interface"
        })

      {:ok, result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      parsed = decode_text_result(result)
      assert length(parsed["domains"]) == 1
      assert hd(parsed["domains"])["name"] == "User Interface"
    end

    test "domains_update modifies an existing domain" do
      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "core",
          "name" => "Core"
        })

      {:ok, list_result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      domain_id = hd(decode_text_result(list_result)["domains"])["id"]

      {:ok, _} =
        Tools.DomainsUpdate.execute(%{
          "project_id" => @project_id,
          "domain_id" => domain_id,
          "name" => "Core System"
        })

      {:ok, list_result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      assert hd(decode_text_result(list_result)["domains"])["name"] == "Core System"
    end
  end

  describe "features" do
    setup do
      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "test-domain",
          "name" => "Test Domain"
        })

      {:ok, list_result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      domain_id = hd(decode_text_result(list_result)["domains"])["id"]

      %{domain_id: domain_id}
    end

    test "features_create and features_search", %{domain_id: domain_id} do
      {:ok, _} =
        Tools.FeaturesCreate.execute(%{
          "project_id" => @project_id,
          "domain_id" => domain_id,
          "spec_key" => "login-flow",
          "name" => "Login Flow",
          "description" => "User authentication via login form"
        })

      {:ok, result} =
        Tools.FeaturesSearch.execute(%{"project_id" => @project_id, "domain_id" => domain_id})

      parsed = decode_text_result(result)
      assert length(parsed["features"]) == 1
      assert hd(parsed["features"])["name"] == "Login Flow"
    end

    test "features_search with text query", %{domain_id: domain_id} do
      {:ok, _} =
        Tools.FeaturesCreate.execute(%{
          "project_id" => @project_id,
          "domain_id" => domain_id,
          "spec_key" => "session-mgmt",
          "name" => "Session Management"
        })

      {:ok, result} =
        Tools.FeaturesSearch.execute(%{"project_id" => @project_id, "q" => "session"})

      parsed = decode_text_result(result)
      assert length(parsed["features"]) == 1
    end

    test "features_delete removes feature and its requirements", %{domain_id: domain_id} do
      {:ok, _} =
        Tools.FeaturesCreate.execute(%{
          "project_id" => @project_id,
          "domain_id" => domain_id,
          "spec_key" => "to-delete",
          "name" => "To Delete"
        })

      {:ok, list_result} =
        Tools.FeaturesSearch.execute(%{"project_id" => @project_id, "domain_id" => domain_id})

      feature_id = hd(decode_text_result(list_result)["features"])["id"]

      {:ok, _} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "req-one",
          "statement" => "The system shall delete cleanly"
        })

      {:ok, _} =
        Tools.FeaturesDelete.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      {:ok, result} =
        Tools.FeaturesSearch.execute(%{"project_id" => @project_id, "domain_id" => domain_id})

      assert decode_text_result(result)["features"] == []

      {:ok, req_result} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      assert decode_text_result(req_result)["requirements"] == []
    end
  end

  describe "requirements" do
    setup do
      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "req-domain",
          "name" => "Req Domain"
        })

      {:ok, list_result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      domain_id = hd(decode_text_result(list_result)["domains"])["id"]

      {:ok, _} =
        Tools.FeaturesCreate.execute(%{
          "project_id" => @project_id,
          "domain_id" => domain_id,
          "spec_key" => "req-feature",
          "name" => "Req Feature"
        })

      {:ok, feat_result} =
        Tools.FeaturesSearch.execute(%{"project_id" => @project_id, "domain_id" => domain_id})

      feature_id = hd(decode_text_result(feat_result)["features"])["id"]

      %{feature_id: feature_id}
    end

    test "requirements_create with valid shall statement", %{feature_id: feature_id} do
      {:ok, result} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "auth-shall-verify",
          "statement" => "The system shall verify credentials before granting access",
          "rationale" => "Security requirement"
        })

      parsed = decode_text_result(result)
      assert parsed["ok"] == true
    end

    test "requirements_create rejects missing shall", %{feature_id: feature_id} do
      {:ok, result} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "bad-req",
          "statement" => "The system verifies credentials"
        })

      parsed = decode_text_result(result)
      assert parsed["error"] =~ "shall"
    end

    test "requirements_search with text query", %{feature_id: feature_id} do
      {:ok, _} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "searchable-req",
          "statement" => "The system shall encrypt passwords at rest"
        })

      {:ok, result} =
        Tools.RequirementsSearch.execute(%{"project_id" => @project_id, "q" => "encrypt"})

      parsed = decode_text_result(result)
      assert length(parsed["requirements"]) == 1
    end

    test "requirements_delete removes a requirement", %{feature_id: feature_id} do
      {:ok, _} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "del-req",
          "statement" => "The system shall be deletable"
        })

      {:ok, search_result} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      req_id = hd(decode_text_result(search_result)["requirements"])["id"]

      {:ok, _} =
        Tools.RequirementsDelete.execute(%{
          "project_id" => @project_id,
          "requirement_id" => req_id
        })

      {:ok, result} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      assert decode_text_result(result)["requirements"] == []
    end
  end

  describe "evidence_files" do
    setup do
      {:ok, _} =
        Tools.DomainsCreate.execute(%{
          "project_id" => @project_id,
          "spec_key" => "ev-domain",
          "name" => "Evidence Domain"
        })

      {:ok, list_result} = Tools.DomainsList.execute(%{"project_id" => @project_id})
      domain_id = hd(decode_text_result(list_result)["domains"])["id"]

      {:ok, _} =
        Tools.FeaturesCreate.execute(%{
          "project_id" => @project_id,
          "domain_id" => domain_id,
          "spec_key" => "ev-feature",
          "name" => "Evidence Feature"
        })

      {:ok, feat_result} =
        Tools.FeaturesSearch.execute(%{"project_id" => @project_id, "domain_id" => domain_id})

      feature_id = hd(decode_text_result(feat_result)["features"])["id"]

      %{feature_id: feature_id}
    end

    test "requirements_create stores evidence_files and search returns them", %{
      feature_id: feature_id
    } do
      {:ok, _} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "ev-req-one",
          "statement" => "The system shall track evidence",
          "evidence_files" => ["lib/foo.ex", "lib/bar.ex"]
        })

      {:ok, result} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      parsed = decode_text_result(result)
      req = hd(parsed["requirements"])
      assert req["evidence_files"] == ~s(["lib/foo.ex","lib/bar.ex"])
    end

    test "requirements_update replaces evidence_files", %{feature_id: feature_id} do
      {:ok, _} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "ev-req-replace",
          "statement" => "The system shall be replaceable",
          "evidence_files" => ["lib/old.ex"]
        })

      {:ok, search} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      req_id = hd(decode_text_result(search)["requirements"])["id"]

      {:ok, _} =
        Tools.RequirementsUpdate.execute(%{
          "project_id" => @project_id,
          "requirement_id" => req_id,
          "evidence_files" => ["lib/new.ex", "lib/also_new.ex"]
        })

      {:ok, result} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      req = hd(decode_text_result(result)["requirements"])
      assert req["evidence_files"] == ~s(["lib/new.ex","lib/also_new.ex"])
    end

    test "requirements_add_evidence_files merges and de-dupes", %{feature_id: feature_id} do
      {:ok, _} =
        Tools.RequirementsCreate.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id,
          "spec_key" => "ev-req-merge",
          "statement" => "The system shall merge evidence",
          "evidence_files" => ["lib/a.ex", "lib/b.ex"]
        })

      {:ok, search} =
        Tools.RequirementsSearch.execute(%{
          "project_id" => @project_id,
          "feature_id" => feature_id
        })

      req_id = hd(decode_text_result(search)["requirements"])["id"]

      {:ok, result} =
        Tools.RequirementsAddEvidenceFiles.execute(%{
          "project_id" => @project_id,
          "requirement_id" => req_id,
          "files" => ["lib/b.ex", "lib/c.ex"]
        })

      parsed = decode_text_result(result)
      assert parsed["ok"] == true
      assert parsed["evidence_files"] == ["lib/a.ex", "lib/b.ex", "lib/c.ex"]
    end
  end

  defp decode_text_result(%{"content" => [%{"type" => "text", "text" => json}]}) do
    Jason.decode!(json)
  end
end

defmodule Spotter.ProductSpec.Agent.RepoToolsTest do
  @moduledoc "Non-Dolt tests for repo inspection tools fail-safe behavior."

  use ExUnit.Case, async: true

  alias Spotter.ProductSpec.Agent.ToolHelpers
  alias Spotter.ProductSpec.Agent.Tools

  describe "repo tools fail-safe" do
    test "repo_read_file_at_commit returns error when git_cwd not set" do
      ToolHelpers.set_git_cwd(nil)

      {:ok, result} =
        Tools.RepoReadFileAtCommit.execute(%{
          "commit_hash" => "abc123",
          "relative_path" => "lib/foo.ex"
        })

      parsed = decode_text_result(result)
      assert parsed["ok"] == false
      assert parsed["error"] =~ "git_cwd"
    end

    test "repo_list_files_at_commit returns error when git_cwd not set" do
      ToolHelpers.set_git_cwd(nil)

      {:ok, result} =
        Tools.RepoListFilesAtCommit.execute(%{"commit_hash" => "abc123"})

      parsed = decode_text_result(result)
      assert parsed["ok"] == false
      assert parsed["error"] =~ "git_cwd"
    end

    test "repo_read_file_at_commit returns error for invalid cwd" do
      ToolHelpers.set_git_cwd("/nonexistent/path")

      {:ok, result} =
        Tools.RepoReadFileAtCommit.execute(%{
          "commit_hash" => "abc123",
          "relative_path" => "lib/foo.ex"
        })

      parsed = decode_text_result(result)
      assert parsed["ok"] == false
      assert is_binary(parsed["error"])
    end
  end

  defp decode_text_result(%{"content" => [%{"type" => "text", "text" => json}]}) do
    Jason.decode!(json)
  end
end
