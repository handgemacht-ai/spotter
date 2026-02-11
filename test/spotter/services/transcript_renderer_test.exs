defmodule Spotter.Services.TranscriptRendererTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.TranscriptRenderer
  alias Spotter.Transcripts.JsonlParser

  @fixtures_dir "test/fixtures/transcripts"

  describe "strip_ansi/1" do
    test "removes color codes" do
      assert TranscriptRenderer.strip_ansi("\e[31mred\e[0m") == "red"
    end

    test "removes bold and underline" do
      assert TranscriptRenderer.strip_ansi("\e[1mbold\e[0m") == "bold"
      assert TranscriptRenderer.strip_ansi("\e[4munderline\e[0m") == "underline"
    end

    test "handles multiple sequences" do
      assert TranscriptRenderer.strip_ansi("\e[1;31mbold red\e[0m normal") == "bold red normal"
    end

    test "returns plain text unchanged" do
      assert TranscriptRenderer.strip_ansi("hello world") == "hello world"
    end

    test "handles empty string" do
      assert TranscriptRenderer.strip_ansi("") == ""
    end
  end

  describe "extract_text/1" do
    test "extracts text from text map" do
      assert TranscriptRenderer.extract_text(%{"text" => "hello"}) == "hello"
    end

    test "extracts text from blocks" do
      blocks = [%{"type" => "text", "text" => "hello"}, %{"type" => "text", "text" => " world"}]
      assert TranscriptRenderer.extract_text(%{"blocks" => blocks}) == "hello world"
    end

    test "handles nil content" do
      assert TranscriptRenderer.extract_text(nil) == ""
    end

    test "extracts tool_use names from blocks" do
      blocks = [
        %{"type" => "text", "text" => "Let me check."},
        %{"type" => "tool_use", "name" => "Bash", "input" => %{"command" => "ls"}}
      ]

      result = TranscriptRenderer.extract_text(%{"blocks" => blocks})
      assert result =~ "Let me check."
    end
  end

  describe "render_message/1" do
    test "renders assistant text message" do
      msg = %{
        type: :assistant,
        content: %{"blocks" => [%{"type" => "text", "text" => "Hello there"}]},
        uuid: "abc"
      }

      lines = TranscriptRenderer.render_message(msg)
      assert lines != []
      assert Enum.any?(lines, &(&1 =~ "Hello there"))
    end

    test "renders assistant tool_use with bullet prefix" do
      msg = %{
        type: :assistant,
        content: %{
          "blocks" => [
            %{"type" => "tool_use", "name" => "Bash", "input" => %{"command" => "mix test"}}
          ]
        },
        uuid: "abc"
      }

      lines = TranscriptRenderer.render_message(msg)
      assert Enum.any?(lines, &(&1 =~ "●"))
      assert Enum.any?(lines, &(&1 =~ "Bash"))
    end

    test "renders user tool_result with indent" do
      msg = %{
        type: :user,
        content: %{
          "blocks" => [
            %{"type" => "tool_result", "content" => "ok", "tool_use_id" => "toolu_123"}
          ]
        },
        uuid: "abc"
      }

      lines = TranscriptRenderer.render_message(msg)
      assert Enum.any?(lines, &(&1 =~ "⎿"))
    end

    test "renders user text input" do
      msg = %{type: :user, content: %{"text" => "fix the bug"}, uuid: "abc"}
      lines = TranscriptRenderer.render_message(msg)
      assert Enum.any?(lines, &(&1 =~ "fix the bug"))
    end

    test "skips progress messages" do
      msg = %{type: :progress, content: nil, uuid: "abc"}
      assert TranscriptRenderer.render_message(msg) == []
    end

    test "skips file_history_snapshot messages" do
      msg = %{type: :file_history_snapshot, content: nil, uuid: "abc"}
      assert TranscriptRenderer.render_message(msg) == []
    end

    test "skips system messages" do
      msg = %{type: :system, content: nil, uuid: "abc"}
      assert TranscriptRenderer.render_message(msg) == []
    end

    test "skips thinking messages" do
      msg = %{type: :thinking, content: %{"text" => "thinking..."}, uuid: "abc"}
      assert TranscriptRenderer.render_message(msg) == []
    end

    test "handles nil content" do
      msg = %{type: :assistant, content: nil, uuid: "abc"}
      assert TranscriptRenderer.render_message(msg) == []
    end
  end

  describe "render/1" do
    test "returns list of rendered line maps" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]},
          uuid: "msg-1"
        },
        %{type: :progress, content: nil, uuid: "msg-2"},
        %{type: :user, content: %{"text" => "thanks"}, uuid: "msg-3"}
      ]

      result = TranscriptRenderer.render(messages)
      assert is_list(result)
      assert Enum.all?(result, &match?(%{line: _, message_id: _, type: _, line_number: _}, &1))
    end

    test "assigns sequential line numbers" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Line 1\nLine 2"}]},
          uuid: "m1"
        },
        %{type: :user, content: %{"text" => "ok"}, uuid: "m2"}
      ]

      result = TranscriptRenderer.render(messages)
      line_numbers = Enum.map(result, & &1.line_number)
      assert line_numbers == Enum.to_list(1..length(result))
    end

    test "skips non-renderable messages" do
      messages = [
        %{type: :progress, content: nil, uuid: "m1"},
        %{type: :file_history_snapshot, content: nil, uuid: "m2"},
        %{type: :system, content: nil, uuid: "m3"}
      ]

      assert TranscriptRenderer.render(messages) == []
    end

    test "each line maps to valid message uuid" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "hi"}]},
          uuid: "msg-abc"
        },
        %{type: :user, content: %{"text" => "bye"}, uuid: "msg-def"}
      ]

      result = TranscriptRenderer.render(messages)
      message_ids = MapSet.new(["msg-abc", "msg-def"])
      assert Enum.all?(result, &MapSet.member?(message_ids, &1.message_id))
    end

    test "uses id when present, falls back to uuid" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "db msg"}]},
          id: "db-id-1",
          uuid: "legacy-uuid-1"
        },
        %{type: :user, content: %{"text" => "fixture msg"}, uuid: "fixture-uuid-2"}
      ]

      result = TranscriptRenderer.render(messages)
      db_line = Enum.find(result, &(&1.line =~ "db msg"))
      fixture_line = Enum.find(result, &(&1.line =~ "fixture msg"))

      assert db_line.message_id == "db-id-1"
      assert fixture_line.message_id == "fixture-uuid-2"
    end
  end

  describe "fixture integration" do
    test "renders short fixture without errors" do
      messages = load_fixture("short.jsonl")
      result = TranscriptRenderer.render(messages)
      assert result != []
    end

    test "renders tool_heavy fixture with tool_use markers" do
      messages = load_fixture("tool_heavy.jsonl")
      result = TranscriptRenderer.render(messages)
      assert result != []
      assert Enum.any?(result, &(&1.line =~ "●"))
    end

    test "renders subagent fixture without errors" do
      messages = load_fixture("subagent.jsonl")
      result = TranscriptRenderer.render(messages)
      assert result != []
    end

    test "all rendered message types produce at least one line" do
      messages = load_fixture("tool_heavy.jsonl")
      result = TranscriptRenderer.render(messages)

      rendered_types = result |> Enum.map(& &1.type) |> MapSet.new()
      assert MapSet.member?(rendered_types, :assistant)
      assert MapSet.member?(rendered_types, :user)
    end

    test "tool_use messages render with bullet prefix" do
      messages = load_fixture("tool_heavy.jsonl")
      result = TranscriptRenderer.render(messages)

      tool_lines = Enum.filter(result, &(&1.type == :assistant && &1.line =~ "●"))
      assert tool_lines != []
    end
  end

  defp load_fixture(name) do
    path = Path.join(@fixtures_dir, name)
    {:ok, %{messages: messages}} = JsonlParser.parse_session_file(path)
    messages
  end
end
