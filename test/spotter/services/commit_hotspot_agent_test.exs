defmodule Spotter.Services.CommitHotspotAgentTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitHotspotAgent

  describe "parse_main_response/1" do
    test "parses valid main response" do
      json =
        ~s({"hotspots":[{"relative_path":"lib/foo.ex","symbol_name":"run/2","line_start":10,"line_end":25,"snippet":"def run do","reason":"complex logic","overall_score":78.5,"rubric":{"complexity":80,"change_risk":85}}]})

      assert {:ok, hotspots} = CommitHotspotAgent.parse_main_response(json)
      assert length(hotspots) == 1

      h = hd(hotspots)
      assert h.relative_path == "lib/foo.ex"
      assert h.symbol_name == "run/2"
      assert h.overall_score == 78.5
      assert h.rubric["complexity"] == 80.0
    end

    test "clamps scores to 0-100" do
      json =
        ~s({"hotspots":[{"relative_path":"a.ex","line_start":1,"line_end":5,"overall_score":150,"rubric":{"x":-10}}]})

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(json)
      assert h.overall_score == 100.0
      assert h.rubric["x"] == 0.0
    end

    test "returns error for missing hotspots key" do
      assert {:error, :invalid_main_response} =
               CommitHotspotAgent.parse_main_response(~s({"results":[]}))
    end

    test "accepts a decoded map" do
      map = %{"hotspots" => [%{"relative_path" => "a.ex", "line_start" => 1, "line_end" => 5}]}
      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(map)
      assert h.relative_path == "a.ex"
    end
  end

  describe "dedupe_hotspots/1" do
    test "keeps hotspot with highest score when duplicated" do
      hotspots = [
        %{
          relative_path: "a.ex",
          line_start: 1,
          line_end: 10,
          symbol_name: "foo",
          overall_score: 70.0
        },
        %{
          relative_path: "a.ex",
          line_start: 1,
          line_end: 10,
          symbol_name: "foo",
          overall_score: 85.0
        },
        %{
          relative_path: "b.ex",
          line_start: 1,
          line_end: 5,
          symbol_name: nil,
          overall_score: 60.0
        }
      ]

      result = CommitHotspotAgent.dedupe_hotspots(hotspots)
      assert length(result) == 2
      a_hotspot = Enum.find(result, &(&1.relative_path == "a.ex"))
      assert a_hotspot.overall_score == 85.0
    end

    test "returns empty list for empty input" do
      assert CommitHotspotAgent.dedupe_hotspots([]) == []
    end
  end

  describe "extract_tool_counts/1" do
    test "counts tool invocations from assistant messages" do
      tool_name = "mcp__spotter-hotspots__repo_read_file_at_commit"

      messages = [
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => tool_name, "id" => "1"},
              %{"type" => "tool_use", "name" => tool_name, "id" => "2"}
            ]
          }
        },
        %{type: "user", message: %{content: "result"}},
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => tool_name, "id" => "3"}
            ]
          }
        }
      ]

      counts = CommitHotspotAgent.extract_tool_counts(messages)
      assert counts[tool_name] == 3
    end

    test "ignores non-allowed tools" do
      messages = [
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => "some_other_tool", "id" => "1"}
            ]
          }
        }
      ]

      assert CommitHotspotAgent.extract_tool_counts(messages) == %{}
    end

    test "returns empty map for empty messages" do
      assert CommitHotspotAgent.extract_tool_counts([]) == %{}
    end
  end
end
