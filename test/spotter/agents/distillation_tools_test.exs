defmodule Spotter.Agents.DistillationToolsTest do
  use ExUnit.Case, async: true

  alias Spotter.Agents.DistillationTools

  # ── Fixtures ──

  defp valid_metadata do
    %{
      "confidence" => 0.85,
      "source_sections" => ["transcript", "commits"]
    }
  end

  defp valid_snippet do
    %{
      "relative_path" => "lib/foo.ex",
      "line_start" => 10,
      "line_end" => 20,
      "snippet" => "def hello, do: :world",
      "why_important" => "Core logic"
    }
  end

  defp valid_session_input do
    %{
      "session_summary" => "Implemented feature X",
      "what_changed" => ["Added module A", "Updated config"],
      "commands_run" => ["mix test"],
      "open_threads" => [],
      "risks" => [],
      "key_files" => [%{"path" => "lib/foo.ex", "reason" => "Main module"}],
      "important_snippets" => [valid_snippet()],
      "distillation_metadata" => valid_metadata()
    }
  end

  defp valid_project_input do
    %{
      "period_summary" => "Productive week on auth system",
      "themes" => ["Authentication", "Testing"],
      "notable_commits" => [%{"hash" => "abc123", "why_it_matters" => "Added OAuth"}],
      "open_threads" => ["Token refresh edge case"],
      "risks" => ["Rate limiting not implemented"],
      "important_snippets" => [],
      "distillation_metadata" => valid_metadata()
    }
  end

  # ── Session validation ──

  describe "validate_session/1" do
    test "valid payload returns ok with sanitized payload" do
      assert {:ok, payload} = DistillationTools.validate_session(valid_session_input())

      assert payload.session_summary == "Implemented feature X"
      assert payload.what_changed == ["Added module A", "Updated config"]
      assert payload.commands_run == ["mix test"]
      assert payload.open_threads == []
      assert payload.risks == []
      assert [%{path: "lib/foo.ex", reason: "Main module"}] = payload.key_files

      assert [%{relative_path: "lib/foo.ex", line_start: 10, line_end: 20}] =
               payload.important_snippets

      assert payload.distillation_metadata.confidence == 0.85
      assert payload.distillation_metadata.source_sections == ["transcript", "commits"]
    end

    test "trims whitespace from strings" do
      input = put_in(valid_session_input(), ["session_summary"], "  trimmed  ")
      assert {:ok, payload} = DistillationTools.validate_session(input)
      assert payload.session_summary == "trimmed"
    end

    test "rejects missing session_summary" do
      input = Map.delete(valid_session_input(), "session_summary")
      assert {:error, ["session_summary is required"]} = DistillationTools.validate_session(input)
    end
  end

  # ── Project rollup validation ──

  describe "validate_project_rollup/1" do
    test "valid payload returns ok with sanitized payload" do
      assert {:ok, payload} = DistillationTools.validate_project_rollup(valid_project_input())

      assert payload.period_summary == "Productive week on auth system"
      assert payload.themes == ["Authentication", "Testing"]
      assert [%{hash: "abc123", why_it_matters: "Added OAuth"}] = payload.notable_commits
      assert payload.important_snippets == []
    end

    test "allows empty important_snippets array" do
      assert {:ok, payload} = DistillationTools.validate_project_rollup(valid_project_input())
      assert payload.important_snippets == []
    end
  end

  # ── Path traversal ──

  describe "path validation" do
    test "rejects absolute paths in key_files" do
      input = put_in(valid_session_input(), ["key_files"], [%{"path" => "/etc/passwd"}])

      assert {:error, ["key_files[0].path must not be an absolute path"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects path traversal (..) in key_files" do
      input = put_in(valid_session_input(), ["key_files"], [%{"path" => "../secret.txt"}])

      assert {:error, ["key_files[0].path must not contain path traversal (..)"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects backslashes in snippet relative_path" do
      snippet = Map.put(valid_snippet(), "relative_path", "lib\\foo.ex")
      input = put_in(valid_session_input(), ["important_snippets"], [snippet])

      assert {:error, ["important_snippets[0].relative_path must not contain backslashes"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects absolute paths in snippet relative_path" do
      snippet = Map.put(valid_snippet(), "relative_path", "/etc/shadow")
      input = put_in(valid_session_input(), ["important_snippets"], [snippet])

      assert {:error, ["important_snippets[0].relative_path must not be an absolute path"]} =
               DistillationTools.validate_session(input)
    end
  end

  # ── Line range validation ──

  describe "line range validation" do
    test "rejects line_start < 1" do
      snippet = Map.put(valid_snippet(), "line_start", 0)
      input = put_in(valid_session_input(), ["important_snippets"], [snippet])

      assert {:error, ["important_snippets[0].line_start must be >= 1"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects line_end < line_start" do
      snippet = valid_snippet() |> Map.put("line_start", 20) |> Map.put("line_end", 10)
      input = put_in(valid_session_input(), ["important_snippets"], [snippet])

      assert {:error, ["important_snippets[0].line_end must be >= line_start"]} =
               DistillationTools.validate_session(input)
    end
  end

  # ── Array size limits ──

  describe "array size limits" do
    test "rejects what_changed exceeding max count" do
      items = Enum.map(1..13, &"change #{&1}")
      input = put_in(valid_session_input(), ["what_changed"], items)

      assert {:error, ["what_changed exceeds max count 12"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects key_files exceeding max count" do
      items = Enum.map(1..21, &%{"path" => "file#{&1}.ex"})
      input = put_in(valid_session_input(), ["key_files"], items)

      assert {:error, ["key_files exceeds max count 20"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects important_snippets exceeding max count" do
      items = Enum.map(1..13, fn _ -> valid_snippet() end)
      input = put_in(valid_session_input(), ["important_snippets"], items)

      assert {:error, ["important_snippets exceeds max count 12"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects notable_commits exceeding max count" do
      items = Enum.map(1..21, &%{"hash" => "abc#{&1}", "why_it_matters" => "reason"})
      input = put_in(valid_project_input(), ["notable_commits"], items)

      assert {:error, ["notable_commits exceeds max count 20"]} =
               DistillationTools.validate_project_rollup(input)
    end
  end

  # ── Confidence validation ──

  describe "confidence validation" do
    test "rejects confidence below 0" do
      input = put_in(valid_session_input(), ["distillation_metadata", "confidence"], -0.1)

      assert {:error, ["distillation_metadata.confidence must be between 0 and 1"]} =
               DistillationTools.validate_session(input)
    end

    test "rejects confidence above 1" do
      input = put_in(valid_session_input(), ["distillation_metadata", "confidence"], 1.5)

      assert {:error, ["distillation_metadata.confidence must be between 0 and 1"]} =
               DistillationTools.validate_session(input)
    end

    test "accepts confidence at boundaries" do
      input_zero = put_in(valid_session_input(), ["distillation_metadata", "confidence"], 0)

      assert {:ok, %{distillation_metadata: %{confidence: 0}}} =
               DistillationTools.validate_session(input_zero)

      input_one = put_in(valid_session_input(), ["distillation_metadata", "confidence"], 1)

      assert {:ok, %{distillation_metadata: %{confidence: 1}}} =
               DistillationTools.validate_session(input_one)
    end
  end

  # ── Tool server ──

  describe "DistillationToolServer" do
    alias Spotter.Agents.DistillationToolServer

    test "allowed_session_tools returns session tool name" do
      assert DistillationToolServer.allowed_session_tools() == [
               "mcp__spotter-distill__record_session_distillation"
             ]
    end

    test "allowed_project_rollup_tools returns rollup tool name" do
      assert DistillationToolServer.allowed_project_rollup_tools() == [
               "mcp__spotter-distill__record_project_rollup_distillation"
             ]
    end
  end
end
