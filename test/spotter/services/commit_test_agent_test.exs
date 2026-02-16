defmodule Spotter.Services.CommitTestAgentTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitTestAgent

  @sample_input %{
    project_id: "019c5952-42f5-7e7e-a8b7-e10e1619db24",
    commit_hash: String.duplicate("a", 40),
    relative_path: "test/foo_test.exs",
    file_content: """
    defmodule FooTest do
      use ExUnit.Case
      test "returns ok" do
        assert Foo.call() == :ok
      end
    end
    """,
    file_diff: """
    --- a/test/foo_test.exs
    +++ b/test/foo_test.exs
    @@ -1,5 +1,6 @@
     defmodule FooTest do
       use ExUnit.Case
    +  test "returns ok" do
    +    assert Foo.call() == :ok
    +  end
     end
    """
  }

  describe "build_prompt/1" do
    test "includes commit hash and file path" do
      prompt = CommitTestAgent.build_prompt(@sample_input)
      assert prompt =~ "Commit: #{@sample_input.commit_hash}"
      assert prompt =~ "File: test/foo_test.exs"
    end

    test "includes numbered instructions" do
      prompt = CommitTestAgent.build_prompt(@sample_input)
      assert prompt =~ "1. Call `mcp__spotter-tests__list_tests`"
      assert prompt =~ "2. Review the diff"
      assert prompt =~ "3. Review the current file content"
      assert prompt =~ "4. Ensure the database mirrors"
      assert prompt =~ "5. For each test, set given, when, and then"

      assert prompt =~
               "6. IMPORTANT: Every create_test and update_test call MUST include source_commit_hash"

      assert prompt =~ "7. Call `mcp__spotter-tests__list_spec_requirements`"
      assert prompt =~ "8. End by printing a short JSON summary"
    end

    test "includes spec linking instructions" do
      prompt = CommitTestAgent.build_prompt(@sample_input)
      assert prompt =~ "list_spec_requirements"
      assert prompt =~ "upsert_spec_test_links"
      assert prompt =~ "If the requirements list is empty, skip linking"
      assert prompt =~ "spec_links"
    end

    test "embeds diff in fenced code block" do
      prompt = CommitTestAgent.build_prompt(@sample_input)
      assert prompt =~ "```diff\n"
      assert prompt =~ "--- a/test/foo_test.exs"
    end

    test "embeds file content with language hint" do
      prompt = CommitTestAgent.build_prompt(@sample_input)
      assert prompt =~ "```elixir\n"
      assert prompt =~ "defmodule FooTest do"
    end

    test "uses text for unknown extensions" do
      input = %{@sample_input | relative_path: "test/data.unknown"}
      prompt = CommitTestAgent.build_prompt(input)
      assert prompt =~ "```text\n"
    end

    test "includes project_id in list_tests instruction" do
      prompt = CommitTestAgent.build_prompt(@sample_input)
      assert prompt =~ "project_id=\"#{@sample_input.project_id}\""
    end
  end

  describe "run_file/1 input normalization" do
    test "returns error for missing required keys" do
      assert {:error, {:invalid_input, keys}} =
               CommitTestAgent.run_file(%{project_id: "p1"})

      assert :commit_hash in keys
    end

    test "returns error for empty string required keys" do
      assert {:error, {:invalid_input, _}} =
               CommitTestAgent.run_file(%{
                 project_id: "",
                 commit_hash: "abc",
                 relative_path: "test.exs",
                 file_content: "content",
                 file_diff: "diff"
               })
    end

    test "string-key input passes normalization" do
      alias Spotter.Observability.AgentRunInput

      input = %{
        "project_id" => "p1",
        "commit_hash" => String.duplicate("a", 40),
        "relative_path" => "test.exs",
        "file_content" => "content",
        "file_diff" => "diff"
      }

      required = ~w(project_id commit_hash relative_path file_content file_diff)a
      assert {:ok, normalized} = AgentRunInput.normalize(input, required)
      assert normalized.project_id == "p1"
      assert normalized.relative_path == "test.exs"
    end
  end

  describe "extract_tool_counts/1" do
    test "counts tool invocations from query messages (atom keys)" do
      messages = [
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => "mcp__spotter-tests__list_tests"},
              %{"type" => "text", "text" => "Let me check..."}
            ]
          }
        },
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => "mcp__spotter-tests__create_test"},
              %{"type" => "tool_use", "name" => "mcp__spotter-tests__create_test"}
            ]
          }
        }
      ]

      counts = CommitTestAgent.extract_tool_counts(messages)
      assert counts["mcp__spotter-tests__list_tests"] == 1
      assert counts["mcp__spotter-tests__create_test"] == 2
    end

    test "counts from Message structs" do
      messages = [
        %ClaudeAgentSDK.Message{
          type: :assistant,
          data: %{
            message: %{
              content: [
                %{"type" => "tool_use", "name" => "mcp__spotter-tests__delete_test"}
              ]
            }
          },
          raw: %{}
        }
      ]

      counts = CommitTestAgent.extract_tool_counts(messages)
      assert counts["mcp__spotter-tests__delete_test"] == 1
    end

    test "ignores non-allowed tools" do
      messages = [
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => "Bash"}
            ]
          }
        }
      ]

      counts = CommitTestAgent.extract_tool_counts(messages)
      assert counts == %{}
    end

    test "returns empty map for no tool calls" do
      messages = [
        %{type: "result", data: %{result: "done"}}
      ]

      assert CommitTestAgent.extract_tool_counts(messages) == %{}
    end
  end
end
