defmodule Spotter.Services.TranscriptSyncTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.{TranscriptRenderer, TranscriptSync}
  alias Spotter.Transcripts.JsonlParser

  @fixtures_dir "test/fixtures/transcripts"

  describe "prepare_terminal_lines/1" do
    test "strips ANSI codes and splits on newlines" do
      input = "\e[31mred line\e[0m\nplain line"
      result = TranscriptSync.prepare_terminal_lines(input)
      assert result == ["red line", "plain line"]
    end

    test "strips trailing spaces" do
      input = "hello   \nworld   "
      result = TranscriptSync.prepare_terminal_lines(input)
      assert result == ["hello", "world"]
    end

    test "returns empty list for nil" do
      assert TranscriptSync.prepare_terminal_lines(nil) == []
    end

    test "returns empty list for empty string" do
      assert TranscriptSync.prepare_terminal_lines("") == []
    end
  end

  describe "find_anchors/2" do
    test "returns empty list for empty inputs" do
      assert TranscriptSync.find_anchors([], ["line"]) == []

      assert TranscriptSync.find_anchors(
               [%{line: "x", message_id: "1", type: :assistant, line_number: 1}],
               []
             ) == []
    end

    test "finds tool_use anchors" do
      rendered = [
        %{line: "● Bash(mix test)", message_id: "msg-1", type: :assistant, line_number: 1}
      ]

      terminal = ["some preamble", "● Bash  mix test", "output line"]
      anchors = TranscriptSync.find_anchors(rendered, terminal)

      assert anchors != []
      assert hd(anchors).type == :tool_use
      assert hd(anchors).id == "msg-1"
    end

    test "finds user text anchors" do
      rendered = [
        %{
          line: "fix the authentication bug in the login flow",
          message_id: "msg-2",
          type: :user,
          line_number: 1
        }
      ]

      terminal = ["preamble", "fix the authentication bug in the login flow", "more"]
      anchors = TranscriptSync.find_anchors(rendered, terminal)

      assert anchors != []
      assert hd(anchors).type == :user
      assert hd(anchors).id == "msg-2"
    end

    test "finds assistant text anchors for long lines" do
      long_text =
        "Let me check the project structure and try running the server to see the error."

      rendered = [
        %{line: long_text, message_id: "msg-3", type: :assistant, line_number: 1}
      ]

      terminal = ["preamble", long_text, "more"]
      anchors = TranscriptSync.find_anchors(rendered, terminal)

      assert anchors != []
      assert hd(anchors).type == :text
    end

    test "advances cursor forward-only" do
      rendered = [
        %{line: "● Bash(ls)", message_id: "msg-1", type: :assistant, line_number: 1},
        %{line: "● Read(file.ex)", message_id: "msg-2", type: :assistant, line_number: 2}
      ]

      terminal = ["● Bash  ls", "output", "● Read  file.ex", "more"]
      anchors = TranscriptSync.find_anchors(rendered, terminal)

      assert length(anchors) == 2
      assert Enum.at(anchors, 0).t < Enum.at(anchors, 1).t
    end

    test "skips whitespace-only rendered lines" do
      rendered = [
        %{line: "   ", message_id: "msg-1", type: :assistant, line_number: 1},
        %{line: "● Bash(mix test)", message_id: "msg-2", type: :assistant, line_number: 2}
      ]

      terminal = ["● Bash  mix test"]
      anchors = TranscriptSync.find_anchors(rendered, terminal)

      assert length(anchors) == 1
      assert hd(anchors).id == "msg-2"
    end
  end

  describe "interpolate/2" do
    test "returns empty list for no anchors" do
      assert TranscriptSync.interpolate([], 100) == []
    end

    test "returns empty list for zero terminal lines" do
      assert TranscriptSync.interpolate([%{t: 0, id: "a", tl: 1, type: :text}], 0) == []
    end

    test "single anchor returns entry at t=0" do
      result = TranscriptSync.interpolate([%{t: 5, id: "a", tl: 1, type: :text}], 10)
      assert result == [%{t: 0, id: "a"}]
    end

    test "two anchors with same id produce single entry" do
      anchors = [
        %{t: 2, id: "a", tl: 1, type: :text},
        %{t: 8, id: "a", tl: 2, type: :text}
      ]

      result = TranscriptSync.interpolate(anchors, 10)
      assert Enum.all?(result, &(&1.id == "a"))
      # Should be deduplicated to just one entry
      assert length(result) == 1
    end

    test "two anchors with different ids produce transition" do
      anchors = [
        %{t: 2, id: "a", tl: 1, type: :text},
        %{t: 8, id: "b", tl: 2, type: :text}
      ]

      result = TranscriptSync.interpolate(anchors, 10)
      ids = Enum.map(result, & &1.id)
      assert "a" in ids
      assert "b" in ids
      assert result == Enum.sort_by(result, & &1.t)
    end

    test "breakpoint map is sorted by t" do
      anchors = [
        %{t: 5, id: "a", tl: 1, type: :text},
        %{t: 15, id: "b", tl: 2, type: :tool_use},
        %{t: 25, id: "c", tl: 3, type: :user}
      ]

      result = TranscriptSync.interpolate(anchors, 30)
      t_values = Enum.map(result, & &1.t)
      assert t_values == Enum.sort(t_values)
    end

    test "no duplicate consecutive ids" do
      anchors = [
        %{t: 2, id: "a", tl: 1, type: :text},
        %{t: 10, id: "b", tl: 2, type: :text},
        %{t: 20, id: "c", tl: 3, type: :text}
      ]

      result = TranscriptSync.interpolate(anchors, 25)

      consecutive_pairs = Enum.chunk_every(result, 2, 1, :discard)
      assert Enum.all?(consecutive_pairs, fn [a, b] -> a.id != b.id end)
    end
  end

  describe "build_breakpoint_map/2" do
    test "returns empty list for empty inputs" do
      assert TranscriptSync.build_breakpoint_map([], "content") == []
      assert TranscriptSync.build_breakpoint_map([%{line: "x"}], "") == []
      assert TranscriptSync.build_breakpoint_map([%{line: "x"}], nil) == []
    end

    test "produces sorted map with valid ids" do
      rendered = [
        %{line: "● Bash(mix test)", message_id: "msg-1", type: :assistant, line_number: 1},
        %{
          line: "Let me check the project structure and see what is happening here.",
          message_id: "msg-2",
          type: :assistant,
          line_number: 2
        }
      ]

      terminal_capture =
        "preamble\n● Bash  mix test\noutput\nLet me check the project structure and see what is happening here.\nmore"

      result = TranscriptSync.build_breakpoint_map(rendered, terminal_capture)
      assert result != []

      # Sorted by t
      t_values = Enum.map(result, & &1.t)
      assert t_values == Enum.sort(t_values)

      # All ids are from rendered_lines
      valid_ids = MapSet.new(["msg-1", "msg-2"])
      assert Enum.all?(result, &MapSet.member?(valid_ids, &1.id))
    end
  end

  describe "fixture integration" do
    test "tool_heavy fixture finds at least 3 anchors" do
      messages = load_fixture("tool_heavy.jsonl")
      rendered_lines = TranscriptRenderer.render(messages)

      # Build synthetic terminal content from rendered lines (simulating terminal output)
      terminal_content = build_synthetic_terminal(rendered_lines)
      terminal_lines = TranscriptSync.prepare_terminal_lines(terminal_content)

      anchors = TranscriptSync.find_anchors(rendered_lines, terminal_lines)
      assert [_, _, _ | _] = anchors
    end

    test "tool_heavy breakpoint map ids are subset of rendered_lines ids" do
      messages = load_fixture("tool_heavy.jsonl")
      rendered_lines = TranscriptRenderer.render(messages)
      terminal_content = build_synthetic_terminal(rendered_lines)

      breakpoint_map = TranscriptSync.build_breakpoint_map(rendered_lines, terminal_content)
      valid_ids = rendered_lines |> Enum.map(& &1.message_id) |> MapSet.new()

      assert Enum.all?(breakpoint_map, &MapSet.member?(valid_ids, &1.id))
    end

    test "tool_heavy breakpoint map is sorted by t" do
      messages = load_fixture("tool_heavy.jsonl")
      rendered_lines = TranscriptRenderer.render(messages)
      terminal_content = build_synthetic_terminal(rendered_lines)

      breakpoint_map = TranscriptSync.build_breakpoint_map(rendered_lines, terminal_content)
      t_values = Enum.map(breakpoint_map, & &1.t)
      assert t_values == Enum.sort(t_values)
    end

    test "tool_heavy breakpoint map has no duplicate consecutive ids" do
      messages = load_fixture("tool_heavy.jsonl")
      rendered_lines = TranscriptRenderer.render(messages)
      terminal_content = build_synthetic_terminal(rendered_lines)

      breakpoint_map = TranscriptSync.build_breakpoint_map(rendered_lines, terminal_content)
      consecutive_pairs = Enum.chunk_every(breakpoint_map, 2, 1, :discard)
      assert Enum.all?(consecutive_pairs, fn [a, b] -> a.id != b.id end)
    end

    test "short fixture finds at least 1 anchor" do
      messages = load_fixture("short.jsonl")
      rendered_lines = TranscriptRenderer.render(messages)
      terminal_content = build_synthetic_terminal(rendered_lines)
      terminal_lines = TranscriptSync.prepare_terminal_lines(terminal_content)

      anchors = TranscriptSync.find_anchors(rendered_lines, terminal_lines)
      assert anchors != []
    end

    test "empty rendered lines return empty breakpoint map" do
      assert TranscriptSync.build_breakpoint_map([], "terminal content\nline 2") == []
    end
  end

  # Helpers

  defp load_fixture(name) do
    path = Path.join(@fixtures_dir, name)
    {:ok, %{messages: messages}} = JsonlParser.parse_session_file(path)
    messages
  end

  defp build_synthetic_terminal(rendered_lines) do
    Enum.map_join(rendered_lines, "\n", & &1.line)
  end
end
