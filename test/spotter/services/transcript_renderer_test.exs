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

  describe "render/2 enriched metadata" do
    test "includes kind, tool_use_id, thread_key, subagent_ref, code_language, render_mode" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]},
          uuid: "msg-1"
        }
      ]

      [line] = TranscriptRenderer.render(messages)

      assert %{
               kind: :text,
               tool_use_id: nil,
               thread_key: nil,
               subagent_ref: nil,
               code_language: nil,
               render_mode: :plain
             } = line
    end
  end

  describe "thinking rendering in render/2" do
    test "includes thinking blocks from assistant messages" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "thinking", "thinking" => "Let me think about this"},
              %{"type" => "text", "text" => "Here's my answer"}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      thinking_lines = Enum.filter(result, &(&1.kind == :thinking))
      assert thinking_lines != []
      assert Enum.any?(thinking_lines, &(&1.line =~ "Let me think"))
      assert Enum.all?(thinking_lines, &(&1.render_mode == :plain))
    end

    test "includes top-level thinking messages" do
      messages = [
        %{type: :thinking, content: %{"text" => "thinking..."}, uuid: "msg-1"}
      ]

      result = TranscriptRenderer.render(messages)
      assert result != []
      assert hd(result).kind == :thinking
      assert hd(result).render_mode == :plain
    end

    test "render_message/1 still skips thinking (backward compat)" do
      msg = %{type: :thinking, content: %{"text" => "thinking..."}, uuid: "abc"}
      assert TranscriptRenderer.render_message(msg) == []
    end
  end

  describe "tool threading" do
    test "tool_use and tool_result share thread_key" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_123",
                "input" => %{"command" => "ls"}
              }
            ]
          },
          uuid: "msg-1"
        },
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_123",
                "content" => "file1.txt\nfile2.txt"
              }
            ]
          },
          uuid: "msg-2"
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_use_line = Enum.find(result, &(&1.kind == :tool_use))
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert tool_use_line.thread_key == "toolu_123"
      assert tool_use_line.tool_use_id == "toolu_123"
      assert Enum.all?(tool_result_lines, &(&1.thread_key == "toolu_123"))
      assert Enum.all?(tool_result_lines, &(&1.tool_use_id == "toolu_123"))
    end

    test "tool_use without id uses fallback thread_key" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "tool_use", "name" => "Bash", "input" => %{"command" => "ls"}}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_use_line = Enum.find(result, &(&1.kind == :tool_use))

      assert tool_use_line.thread_key == "tool-use-Bash"
      assert tool_use_line.tool_use_id == nil
    end

    test "tool_result without tool_use_id uses fallback thread_key" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [%{"type" => "tool_result", "content" => "ok"}]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      line = hd(result)

      assert line.kind == :tool_result
      assert line.thread_key == "unmatched-result"
    end
  end

  describe "code detection" do
    test "detects fenced code blocks with language" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "text",
                "text" => "Here's code:\n```elixir\ndef foo, do: :bar\n```\nDone."
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))
      plain_lines = Enum.filter(result, &(&1.render_mode == :plain))

      assert length(code_lines) == 3
      assert Enum.all?(code_lines, &(&1.code_language == "elixir"))
      assert length(plain_lines) == 2
    end

    test "detects arrow-numbered lines as code" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "text", "text" => "File content:\n     1→import foo\n     2→import bar"}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 2
      assert Enum.all?(code_lines, &(&1.code_language == "plaintext"))
    end

    test "unclosed fence renders as code until end" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "text", "text" => "```python\nprint('hello')\nmore code"}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 3
      assert Enum.all?(code_lines, &(&1.code_language == "python"))
    end

    test "bare fence opens plaintext code block" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "text", "text" => "```\nsome code\n```"}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 3
      assert Enum.all?(code_lines, &(&1.code_language == "plaintext"))
    end
  end

  describe "subagent detection" do
    test "detects subagent_ref from message agent_id" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Some text"}]},
          uuid: "msg-1",
          agent_id: "afb92ff"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert Enum.all?(result, &(&1.subagent_ref == "afb92ff"))
    end

    test "detects subagent_ref from text pattern" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "text", "text" => "Launching agent-abc123 to handle this"}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert Enum.any?(result, &(&1.subagent_ref == "agent-abc123"))
    end

    test "subagent_ref is nil when no agent reference" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Just plain text"}]},
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert Enum.all?(result, &is_nil(&1.subagent_ref))
    end
  end

  describe "to_relative_path/2" do
    test "relativizes absolute path with matching prefix" do
      assert TranscriptRenderer.to_relative_path(
               "/home/user/project/lib/foo.ex",
               "/home/user/project"
             ) == "lib/foo.ex"
    end

    test "preserves path with no matching prefix" do
      assert TranscriptRenderer.to_relative_path(
               "/other/path/foo.ex",
               "/home/user/project"
             ) == "/other/path/foo.ex"
    end

    test "preserves relative path" do
      assert TranscriptRenderer.to_relative_path("lib/foo.ex", "/home/user/project") ==
               "lib/foo.ex"
    end

    test "handles nil session_cwd" do
      assert TranscriptRenderer.to_relative_path("/home/user/project/lib/foo.ex", nil) ==
               "/home/user/project/lib/foo.ex"
    end

    test "non-path strings with / are not mangled" do
      assert TranscriptRenderer.to_relative_path("config/key", "/home/user") == "config/key"
    end
  end

  describe "render/2 with session_cwd" do
    test "relativizes file paths in tool_use preview" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_1",
                "input" => %{"file_path" => "/home/user/project/lib/foo.ex"}
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages, session_cwd: "/home/user/project")
      assert Enum.any?(result, &(&1.line =~ "lib/foo.ex"))
      refute Enum.any?(result, &(&1.line =~ "/home/user/project"))
    end

    test "relativizes file paths in tool_result content" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_1",
                "content" => "/home/user/project/lib/foo.ex:10: some warning"
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages, session_cwd: "/home/user/project")
      assert Enum.any?(result, &(&1.line =~ "lib/foo.ex"))
      refute Enum.any?(result, &(&1.line =~ "/home/user/project"))
    end

    test "without session_cwd preserves absolute paths" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_1",
                "content" => "/home/user/project/lib/foo.ex"
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert Enum.any?(result, &(&1.line =~ "/home/user/project/lib/foo.ex"))
    end
  end

  describe "edge cases" do
    test "transcript with no tool calls renders cleanly" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]},
          uuid: "msg-1"
        },
        %{
          type: :user,
          content: %{"text" => "Thanks"},
          uuid: "msg-2"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert result != []
      assert Enum.all?(result, &(&1.kind in [:text]))
      assert Enum.all?(result, &is_nil(&1.tool_use_id))
      assert Enum.all?(result, &is_nil(&1.thread_key))
    end

    test "malformed code fence does not crash render" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "text", "text" => "```\nsome code\n```not-a-close\nmore text\n```"}
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert is_list(result)
      assert result != []
    end

    test "tool_result with list content has correct metadata" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_list",
                "content" => [
                  %{"type" => "text", "text" => "line one\nline two"}
                ]
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert Enum.all?(result, &(&1.kind == :tool_result))
      assert Enum.all?(result, &(&1.tool_use_id == "toolu_list"))
      assert Enum.all?(result, &(&1.thread_key == "toolu_list"))
    end

    test "tool_result with no content renders empty placeholder" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [%{"type" => "tool_result", "tool_use_id" => "toolu_empty"}]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert [line] = result
      assert line.kind == :tool_result
      assert line.line =~ "(empty)"
      assert line.tool_use_id == "toolu_empty"
    end

    test "empty message list returns empty result" do
      assert TranscriptRenderer.render([]) == []
    end

    test "mixed content with thinking, text, and tool_use in one message" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{"type" => "thinking", "thinking" => "Let me reason"},
              %{"type" => "text", "text" => "Here's my answer"},
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_mix",
                "input" => %{"file_path" => "/tmp/foo.ex"}
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      kinds = Enum.map(result, & &1.kind)
      assert :thinking in kinds
      assert :text in kinds
      assert :tool_use in kinds
    end
  end

  describe "fixture integration with enriched metadata" do
    test "tool_heavy fixture has tool_use and tool_result kinds" do
      messages = load_fixture("tool_heavy.jsonl")
      result = TranscriptRenderer.render(messages)

      kinds = result |> Enum.map(& &1.kind) |> MapSet.new()
      assert MapSet.member?(kinds, :tool_use)
      assert MapSet.member?(kinds, :tool_result)
    end

    test "subagent fixture renders without errors and has enriched keys" do
      messages = load_fixture("subagent.jsonl")
      result = TranscriptRenderer.render(messages)

      assert result != []

      for line <- result do
        assert Map.has_key?(line, :subagent_ref)
      end
    end

    test "all fixture lines have required enriched keys" do
      for fixture <- ["short.jsonl", "tool_heavy.jsonl", "subagent.jsonl"] do
        messages = load_fixture(fixture)
        result = TranscriptRenderer.render(messages)

        for line <- result do
          assert Map.has_key?(line, :kind), "#{fixture}: missing :kind"
          assert Map.has_key?(line, :tool_use_id), "#{fixture}: missing :tool_use_id"
          assert Map.has_key?(line, :thread_key), "#{fixture}: missing :thread_key"
          assert Map.has_key?(line, :subagent_ref), "#{fixture}: missing :subagent_ref"
          assert Map.has_key?(line, :code_language), "#{fixture}: missing :code_language"
          assert Map.has_key?(line, :render_mode), "#{fixture}: missing :render_mode"
          assert line.render_mode in [:plain, :code], "#{fixture}: invalid render_mode"
        end
      end
    end
  end

  describe "tool result group metadata" do
    test "all tool_result lines have group metadata" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_grp",
                "content" => "line1\nline2\nline3"
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)

      for line <- result do
        assert line.tool_result_group == "toolu_grp"
        assert line.result_total_lines == 3
        assert is_integer(line.result_line_index)
        assert is_boolean(line.hidden_by_default)
      end

      assert Enum.map(result, & &1.result_line_index) == [1, 2, 3]
      assert Enum.all?(result, &(&1.hidden_by_default == false))
    end

    test "lines beyond 10 are hidden_by_default" do
      lines = Enum.map_join(1..15, "\n", &"line #{&1}")

      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_long",
                "content" => lines
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert length(result) == 15

      visible = Enum.reject(result, & &1.hidden_by_default)
      hidden = Enum.filter(result, & &1.hidden_by_default)

      assert length(visible) == 10
      assert length(hidden) == 5
      assert Enum.all?(visible, &(&1.result_line_index <= 10))
      assert Enum.all?(hidden, &(&1.result_line_index > 10))
    end

    test "no silent truncation - all lines preserved" do
      lines = Enum.map_join(1..20, "\n", &"line #{&1}")

      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_all",
                "content" => lines
              }
            ]
          },
          uuid: "msg-1"
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert length(result) == 20
    end

    test "non-tool-result lines have nil group metadata" do
      messages = [
        %{
          type: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]},
          uuid: "msg-1"
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert line.tool_result_group == nil
      assert line.result_line_index == nil
      assert line.result_total_lines == nil
      assert line.hidden_by_default == false
    end

    test "tool_result without tool_use_id gets deterministic group" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [%{"type" => "tool_result", "content" => "output"}]
          },
          uuid: "msg-1"
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert line.tool_result_group != nil
      assert line.result_line_index == 1
      assert line.result_total_lines == 1
    end

    test "empty tool_result has group metadata" do
      messages = [
        %{
          type: :user,
          content: %{
            "blocks" => [%{"type" => "tool_result", "tool_use_id" => "toolu_empty"}]
          },
          uuid: "msg-1"
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert line.tool_result_group != nil
      assert line.result_line_index == 1
      assert line.result_total_lines == 1
      assert line.hidden_by_default == false
    end
  end

  describe "debug payload" do
    test "each rendered line has a debug_payload map" do
      messages = [
        %{
          type: :assistant,
          id: "db-1",
          uuid: "uuid-1",
          role: :assistant,
          content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]}
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert is_map(line.debug_payload)
      assert line.debug_payload.id == "db-1"
      assert line.debug_payload.uuid == "uuid-1"
      assert line.debug_payload.type == :assistant
      assert line.debug_payload.role == :assistant
      assert line.debug_payload.kind == :text
      assert line.debug_payload.rendered_line == "Hello"
    end

    test "tool_use debug payload includes tool_use_id" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_dbg",
                "input" => %{"command" => "ls"}
              }
            ]
          }
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert line.debug_payload.tool_use_id == "toolu_dbg"
      assert line.debug_payload.thread_key == "toolu_dbg"
    end
  end

  describe "read snippet code classification" do
    test "numbered read output in tool_result marked as code with inferred elixir language" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_read",
                "input" => %{"file_path" => "/home/user/project/lib/app.ex"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_read",
                "content" => "     1→defmodule App do\n     2→  def hello, do: :world\n     3→end"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 3
      assert Enum.all?(code_lines, &(&1.code_language == "elixir"))
    end

    test "numbered read output for .json file infers json language" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_json",
                "input" => %{"file_path" => "/tmp/config.json"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_json",
                "content" => "     1→{\"key\": \"value\"}"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 1
      assert hd(code_lines).code_language == "json"
    end

    test "numbered output from non-Read tool defaults to plaintext" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_bash",
                "input" => %{"command" => "cat -n file.txt"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_bash",
                "content" => "     1→some output"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 1
      assert hd(code_lines).code_language == "plaintext"
    end

    test "unknown extension defaults to plaintext for numbered lines" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_unk",
                "input" => %{"file_path" => "/tmp/file.xyz"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_unk",
                "content" => "     1→content"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      code_lines = Enum.filter(result, &(&1.render_mode == :code))

      assert length(code_lines) == 1
      assert hd(code_lines).code_language == "plaintext"
    end

    test "non-numbered tool_result lines remain plain" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_mix",
                "input" => %{"file_path" => "/tmp/app.ex"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_mix",
                "content" => "     1→defmodule App do\nsome plain text\n     3→end"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      code = Enum.filter(tool_result_lines, &(&1.render_mode == :code))
      plain = Enum.filter(tool_result_lines, &(&1.render_mode == :plain))

      assert length(code) == 2
      assert length(plain) == 1
    end
  end

  describe "source line number metadata" do
    test "strips inline numbered prefixes and uses startLine from raw payload when available" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_read",
                "input" => %{"file_path" => "/home/user/project/lib/foo.ex"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_read",
                "content" => "    7→def foo do\n    8→end"
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "type" => "text",
              "file" => %{"startLine" => 42, "numLines" => 2}
            }
          }
        }
      ]

      lines =
        messages
        |> TranscriptRenderer.render(session_cwd: "/home/user/project")
        |> Enum.filter(&(&1.kind == :tool_result))

      assert Enum.map(lines, & &1.line) == ["  ⎿  def foo do", "  ⎿  end"]
      assert Enum.map(lines, & &1.source_line_number) == [42, 43]
      assert Enum.all?(lines, &(&1.render_mode == :code))
      assert Enum.all?(lines, &(&1.code_language == "elixir"))
    end

    test "falls back to parsed line numbers when startLine is missing" do
      messages = [
        %{
          type: :user,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_read",
                "content" => "    9→line one\n    10→line two"
              }
            ]
          }
        }
      ]

      lines =
        messages
        |> TranscriptRenderer.render()
        |> Enum.filter(&(&1.kind == :tool_result))

      assert Enum.map(lines, & &1.line) == ["  ⎿  line one", "  ⎿  line two"]
      assert Enum.map(lines, & &1.source_line_number) == [9, 10]
    end
  end

  describe "tool_use preview formatting" do
    test "relativizes before truncation and uses deterministic input keys" do
      long_relative_path =
        "lib/" <> Enum.map_join(1..20, "/", fn idx -> "nested#{idx}" end) <> "/foo.ex"

      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_preview",
                "input" => %{
                  "description" => "fallback value",
                  "file_path" => "/home/user/project/#{long_relative_path}"
                }
              }
            ]
          }
        }
      ]

      [line] = TranscriptRenderer.render(messages, session_cwd: "/home/user/project")

      assert line.kind == :tool_use
      assert line.line =~ "● Read("
      assert line.line =~ "lib/nested1"
      refute line.line =~ "/home/user/project"
      assert line.line =~ "…"
    end
  end

  describe "token usage metadata" do
    test "sets token_count_total on the first rendered line only" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{"blocks" => [%{"type" => "text", "text" => "first\nsecond"}]},
          raw_payload: %{
            "message" => %{
              "usage" => %{
                "input_tokens" => 10,
                "output_tokens" => 5,
                "cache_creation_input_tokens" => 2,
                "cache_read_input_tokens" => 3
              }
            }
          }
        }
      ]

      [first, second] = TranscriptRenderer.render(messages)

      assert first.token_count_total == 20
      assert second.token_count_total == nil
    end
  end

  defp load_fixture(name) do
    path = Path.join(@fixtures_dir, name)
    {:ok, %{messages: messages}} = JsonlParser.parse_session_file(path)
    messages
  end
end
