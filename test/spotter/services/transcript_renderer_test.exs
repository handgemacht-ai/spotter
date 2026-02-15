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

    test "renders user tool_result without ⎿ prefix" do
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
      assert Enum.any?(lines, &(&1 =~ "ok"))
      refute Enum.any?(lines, &(&1 =~ "⎿"))
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

      assert Enum.map(lines, & &1.line) == ["def foo do", "end"]
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

      assert Enum.map(lines, & &1.line) == ["line one", "line two"]
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

  describe "token delta metadata" do
    test "first message has nil delta, second message has computed delta" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{"blocks" => [%{"type" => "text", "text" => "first"}]},
          raw_payload: %{
            "message" => %{
              "usage" => %{
                "input_tokens" => 10,
                "output_tokens" => 3,
                "cache_creation_input_tokens" => 0,
                "cache_read_input_tokens" => 0
              }
            }
          }
        },
        %{
          type: :assistant,
          uuid: "msg-2",
          content: %{"blocks" => [%{"type" => "text", "text" => "second"}]},
          raw_payload: %{
            "message" => %{
              "usage" => %{
                "input_tokens" => 15,
                "output_tokens" => 5,
                "cache_creation_input_tokens" => 0,
                "cache_read_input_tokens" => 0
              }
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      first = Enum.find(result, &(&1.line == "first"))
      second = Enum.find(result, &(&1.line == "second"))

      assert first.token_count_total == 13
      assert first.token_count_delta == nil

      assert second.token_count_total == 20
      assert second.token_count_delta == 7
    end

    test "non-first lines of a message have nil delta" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{"blocks" => [%{"type" => "text", "text" => "line1\nline2"}]},
          raw_payload: %{
            "message" => %{
              "usage" => %{
                "input_tokens" => 10,
                "output_tokens" => 5,
                "cache_creation_input_tokens" => 0,
                "cache_read_input_tokens" => 0
              }
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      second_line = Enum.at(result, 1)

      assert second_line.token_count_delta == nil
    end
  end

  describe "Bash command_status enrichment" do
    test "Bash tool_use line has command_status :success when result is not error" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_bash_ok",
                "input" => %{"command" => "echo hello"}
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
                "tool_use_id" => "toolu_bash_ok",
                "content" => "hello",
                "is_error" => false
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      bash_line = Enum.find(result, &(&1.kind == :tool_use))

      assert bash_line.command_status == :success
      assert bash_line.tool_name == "Bash"
    end

    test "Bash tool_use line has command_status :error when result is_error" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_bash_err",
                "input" => %{"command" => "false"}
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
                "tool_use_id" => "toolu_bash_err",
                "content" => "command failed",
                "is_error" => true
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      bash_line = Enum.find(result, &(&1.kind == :tool_use))

      assert bash_line.command_status == :error
    end

    test "Bash tool_use line has command_status :pending when no result yet" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_bash_pending",
                "input" => %{"command" => "sleep 999"}
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      bash_line = Enum.find(result, &(&1.kind == :tool_use))

      assert bash_line.command_status == :pending
    end

    test "non-Bash tool_use does not have command_status" do
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
                "input" => %{"file_path" => "/tmp/foo.ex"}
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      read_line = Enum.find(result, &(&1.kind == :tool_use))

      refute Map.has_key?(read_line, :command_status)
      assert read_line.tool_name == "Read"
    end
  end

  describe "AskUserQuestion rendering" do
    test "renders question lines from AskUserQuestion tool_use" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "AskUserQuestion",
                "id" => "toolu_ask",
                "input" => %{
                  "questions" => [
                    %{
                      "question" => "Which database?",
                      "header" => "Database",
                      "options" => [%{"label" => "PostgreSQL"}, %{"label" => "SQLite"}],
                      "multiSelect" => false
                    },
                    %{
                      "question" => "Enable caching?",
                      "header" => "Cache",
                      "options" => [%{"label" => "Yes"}, %{"label" => "No"}],
                      "multiSelect" => false
                    }
                  ]
                }
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      question_lines = Enum.filter(result, &(&1.kind == :ask_user_question))

      assert length(question_lines) == 2
      assert Enum.any?(question_lines, &(&1.line == "? Database - Which database?"))
      assert Enum.any?(question_lines, &(&1.line == "? Cache - Enable caching?"))
      assert Enum.all?(question_lines, &(&1.tool_use_id == "toolu_ask"))
    end

    test "renders question without header" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "AskUserQuestion",
                "id" => "toolu_ask2",
                "input" => %{
                  "questions" => [
                    %{"question" => "What color?", "options" => [], "multiSelect" => false}
                  ]
                }
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      question_lines = Enum.filter(result, &(&1.kind == :ask_user_question))

      assert [q] = question_lines
      assert q.line == "? What color?"
    end

    test "renders answer lines from AskUserQuestion tool_result" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "AskUserQuestion",
                "id" => "toolu_ask3",
                "input" => %{
                  "questions" => [
                    %{
                      "question" => "Which rig?",
                      "header" => "Rig",
                      "options" => [],
                      "multiSelect" => false
                    }
                  ]
                }
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
                "tool_use_id" => "toolu_ask3",
                "content" => "User answered"
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "answers" => %{"Which rig?" => "spotter"}
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      answer_lines = Enum.filter(result, &(&1.kind == :ask_user_answer))

      assert [answer] = answer_lines
      assert answer.line == "↳ Which rig? = spotter"
      assert answer.tool_use_id == "toolu_ask3"
    end

    test "empty answers map renders nothing" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "AskUserQuestion",
                "id" => "toolu_ask4",
                "input" => %{"questions" => []}
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
                "tool_use_id" => "toolu_ask4",
                "content" => "User answered"
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{"answers" => %{}}
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      answer_lines = Enum.filter(result, &(&1.kind == :ask_user_answer))

      assert answer_lines == []
    end

    test "AskUserQuestion with no content block renders answers from toolUseResult" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "AskUserQuestion",
                "id" => "toolu_ask5",
                "input" => %{
                  "questions" => [
                    %{
                      "question" => "Pick one",
                      "header" => "Choice",
                      "options" => [],
                      "multiSelect" => false
                    }
                  ]
                }
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          content: %{
            "blocks" => [
              %{"type" => "tool_result", "tool_use_id" => "toolu_ask5"}
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{"answers" => %{"Pick one" => "Option A"}}
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      answer_lines = Enum.filter(result, &(&1.kind == :ask_user_answer))

      assert [answer] = answer_lines
      assert answer.line == "↳ Pick one = Option A"
    end
  end

  describe "plan rendering" do
    test "Write to plan.md renders plan content lines" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Write",
                "id" => "toolu_write_plan",
                "input" => %{
                  "file_path" => "/home/user/project/plan.md",
                  "content" => "plan text"
                }
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
                "tool_use_id" => "toolu_write_plan",
                "content" => "File created successfully at: /home/user/project/plan.md"
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "content" => "# Plan\n\n## Step 1\nDo the thing"
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      plan_lines = Enum.filter(result, &(&1.kind == :plan_content))

      assert length(plan_lines) == 4
      assert Enum.map(plan_lines, & &1.line) == ["# Plan", "", "## Step 1", "Do the thing"]
      assert Enum.all?(plan_lines, &(&1.tool_use_id == "toolu_write_plan"))
    end

    test "Write to non-plan.md file renders as generic tool result" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Write",
                "id" => "toolu_write_other",
                "input" => %{"file_path" => "/tmp/readme.md", "content" => "readme"}
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
                "tool_use_id" => "toolu_write_other",
                "content" => "File created"
              }
            ]
          },
          raw_payload: %{}
        }
      ]

      result = TranscriptRenderer.render(messages)
      plan_lines = Enum.filter(result, &(&1.kind == :plan_content))
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert plan_lines == []
      assert tool_result_lines != []
    end

    test "empty plan content falls back to generic tool result" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Write",
                "id" => "toolu_write_empty",
                "input" => %{"file_path" => "/tmp/plan.md", "content" => ""}
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
                "tool_use_id" => "toolu_write_empty",
                "content" => "File created"
              }
            ]
          },
          raw_payload: %{"toolUseResult" => %{"content" => ""}}
        }
      ]

      result = TranscriptRenderer.render(messages)
      plan_lines = Enum.filter(result, &(&1.kind == :plan_content))
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert plan_lines == []
      assert tool_result_lines != []
    end

    test "ExitPlanMode approved renders accepted decision" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "ExitPlanMode",
                "id" => "toolu_exit_plan",
                "input" => %{}
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
                "tool_use_id" => "toolu_exit_plan",
                "content" => "User has approved exiting plan mode. You can now proceed."
              }
            ]
          },
          raw_payload: %{}
        }
      ]

      result = TranscriptRenderer.render(messages)
      decision_lines = Enum.filter(result, &(&1.kind == :plan_decision))

      assert [decision] = decision_lines
      assert decision.line == "Plan decision: accepted"
      assert decision.tool_use_id == "toolu_exit_plan"
    end

    test "ExitPlanMode rejected renders rejected decision" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "ExitPlanMode",
                "id" => "toolu_exit_rej",
                "input" => %{}
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
                "tool_use_id" => "toolu_exit_rej",
                "content" => "User has rejected exiting plan mode."
              }
            ]
          },
          raw_payload: %{}
        }
      ]

      result = TranscriptRenderer.render(messages)
      decision_lines = Enum.filter(result, &(&1.kind == :plan_decision))

      assert [decision] = decision_lines
      assert decision.line == "Plan decision: rejected"
    end

    test "ExitPlanMode unknown text renders unknown decision" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "ExitPlanMode",
                "id" => "toolu_exit_unk",
                "input" => %{}
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
                "tool_use_id" => "toolu_exit_unk",
                "content" => "Something unexpected happened."
              }
            ]
          },
          raw_payload: %{}
        }
      ]

      result = TranscriptRenderer.render(messages)
      decision_lines = Enum.filter(result, &(&1.kind == :plan_decision))

      assert [decision] = decision_lines
      assert decision.line == "Plan decision: unknown"
    end

    test "ExitPlanMode without result yet emits no decision line" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "ExitPlanMode",
                "id" => "toolu_exit_pend",
                "input" => %{}
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      decision_lines = Enum.filter(result, &(&1.kind == :plan_decision))

      assert decision_lines == []
    end
  end

  describe "subagent fixture integration with enriched tool rendering" do
    test "AskUserQuestion and ExitPlanMode in subagent fixture render correctly" do
      messages = load_fixture("subagent.jsonl")
      result = TranscriptRenderer.render(messages)

      # Should have AskUserQuestion lines
      ask_user_lines = Enum.filter(result, &(&1.kind == :ask_user_question))
      assert ask_user_lines != [], "Expected AskUserQuestion lines in subagent fixture"

      # Should have answer lines
      answer_lines = Enum.filter(result, &(&1.kind == :ask_user_answer))
      assert answer_lines != [], "Expected AskUser answer lines in subagent fixture"

      # Should have plan decision
      decision_lines = Enum.filter(result, &(&1.kind == :plan_decision))
      assert decision_lines != [], "Expected plan decision lines in subagent fixture"

      # The fixture has "approved exiting plan mode"
      assert Enum.any?(decision_lines, &(&1.line == "Plan decision: accepted"))
    end

    test "subagent fixture has plan content from Write(plan.md)" do
      messages = load_fixture("subagent.jsonl")
      result = TranscriptRenderer.render(messages)

      plan_lines = Enum.filter(result, &(&1.kind == :plan_content))
      assert plan_lines != [], "Expected plan content lines in subagent fixture"
      assert Enum.any?(plan_lines, &(&1.line =~ "Plan"))
    end
  end

  describe "Edit/Write structuredPatch diff rendering" do
    test "Edit with structuredPatch emits diff rows" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_edit_diff",
                "input" => %{
                  "file_path" => "/home/user/project/lib/app.ex",
                  "old_string" => "old",
                  "new_string" => "new"
                }
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
                "tool_use_id" => "toolu_edit_diff",
                "content" => "The file has been updated successfully."
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 10,
                  "oldLines" => 3,
                  "newStart" => 10,
                  "newLines" => 3,
                  "lines" => [" context", "-old line", "+new line"]
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages, session_cwd: "/home/user/project")
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))

      # File headers + hunk header + 3 content lines = 6
      assert length(diff_lines) == 6
      assert Enum.any?(diff_lines, &(&1.line == "--- a/lib/app.ex"))
      assert Enum.any?(diff_lines, &(&1.line == "+++ b/lib/app.ex"))
      assert Enum.any?(diff_lines, &(&1.line == "@@ -10,3 +10,3 @@"))
      assert Enum.any?(diff_lines, &(&1.line == "-old line"))
      assert Enum.any?(diff_lines, &(&1.line == "+new line"))
      assert Enum.all?(diff_lines, &(&1.render_mode == :code))
      assert Enum.all?(diff_lines, &(&1.tool_use_id == "toolu_edit_diff"))
    end

    test "Write with structuredPatch emits diff rows" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Write",
                "id" => "toolu_write_diff",
                "input" => %{
                  "file_path" => "/tmp/config.json",
                  "content" => "{}"
                }
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
                "tool_use_id" => "toolu_write_diff",
                "content" => "File created successfully."
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 0,
                  "oldLines" => 0,
                  "newStart" => 1,
                  "newLines" => 1,
                  "lines" => ["+{}"]
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))

      assert diff_lines != []
      assert Enum.any?(diff_lines, &(&1.line =~ "@@"))
      assert Enum.any?(diff_lines, &(&1.line == "+{}"))
    end

    test "error Edit does not emit diff rows" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_edit_err",
                "input" => %{
                  "file_path" => "/tmp/foo.ex",
                  "old_string" => "x",
                  "new_string" => "y"
                }
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
                "tool_use_id" => "toolu_edit_err",
                "content" => "Edit failed: string not found",
                "is_error" => true
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 1,
                  "oldLines" => 1,
                  "newStart" => 1,
                  "newLines" => 1,
                  "lines" => ["-x", "+y"]
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))

      assert diff_lines == []
    end

    test "Edit without structuredPatch renders as generic tool result" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_edit_no_diff",
                "input" => %{
                  "file_path" => "/tmp/foo.ex",
                  "old_string" => "x",
                  "new_string" => "y"
                }
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
                "tool_use_id" => "toolu_edit_no_diff",
                "content" => "The file has been updated."
              }
            ]
          },
          raw_payload: %{}
        }
      ]

      result = TranscriptRenderer.render(messages)
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert diff_lines == []
      assert tool_result_lines != []
      assert Enum.any?(tool_result_lines, &(&1.line =~ "updated"))
    end

    test "multiple hunks are all rendered" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_multi_hunk",
                "input" => %{
                  "file_path" => "/tmp/foo.ex",
                  "old_string" => "x",
                  "new_string" => "y"
                }
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
                "tool_use_id" => "toolu_multi_hunk",
                "content" => "Updated."
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 1,
                  "oldLines" => 1,
                  "newStart" => 1,
                  "newLines" => 1,
                  "lines" => ["-a", "+b"]
                },
                %{
                  "oldStart" => 20,
                  "oldLines" => 1,
                  "newStart" => 20,
                  "newLines" => 1,
                  "lines" => ["-c", "+d"]
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))
      hunk_headers = Enum.filter(diff_lines, &(&1.line =~ "@@"))

      # 2 file headers + 2 hunk headers + 4 content lines = 8
      assert length(diff_lines) == 8
      assert length(hunk_headers) == 2
    end

    test "hunk with no lines still renders header" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_empty_hunk",
                "input" => %{
                  "file_path" => "/tmp/foo.ex",
                  "old_string" => "x",
                  "new_string" => "y"
                }
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
                "tool_use_id" => "toolu_empty_hunk",
                "content" => "Updated."
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 5,
                  "oldLines" => 0,
                  "newStart" => 5,
                  "newLines" => 0,
                  "lines" => []
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))

      # 2 file headers + 1 hunk header = 3
      assert length(diff_lines) == 3
      assert Enum.any?(diff_lines, &(&1.line == "@@ -5,0 +5,0 @@"))
    end

    test "diff rows without file path omit file headers" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_no_path",
                "input" => %{"old_string" => "x", "new_string" => "y"}
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
                "tool_use_id" => "toolu_no_path",
                "content" => "Updated."
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 1,
                  "oldLines" => 1,
                  "newStart" => 1,
                  "newLines" => 1,
                  "lines" => ["-x", "+y"]
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      diff_lines = Enum.filter(result, &(&1.code_language == "diff"))

      # No file headers, just hunk header + 2 content lines = 3
      assert length(diff_lines) == 3
      refute Enum.any?(diff_lines, &(&1.line =~ "---"))
    end
  end

  describe "hook_progress rendering" do
    test "single hook_progress is wrapped in a group with summary + detail" do
      messages = [
        %{
          type: :progress,
          uuid: "msg-1",
          content: nil,
          raw_payload: %{
            "parentToolUseID" => "toolu_parent",
            "toolUseID" => "toolu_child",
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "PostToolUse",
              "hookName" => "lint-check",
              "command" => "mix credo"
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert [summary, detail] = result

      assert summary.kind == :hook_group
      assert summary.line == "hooks PostToolUse lint-check (1)"
      assert summary.tool_use_id == "toolu_parent"
      assert summary.thread_key == "toolu_parent"
      assert summary.message_id == nil
      assert summary.hidden_by_default == false

      assert detail.kind == :hook_progress
      assert detail.tool_use_id == "toolu_parent"
      assert detail.thread_key == "toolu_parent"
      assert detail.line == "hook PostToolUse lint-check: mix credo"
      assert detail.hidden_by_default == true
      assert detail.hook_group == summary.hook_group
    end

    test "hook_progress falls back to toolUseID when parentToolUseID is missing" do
      messages = [
        %{
          type: :progress,
          uuid: "msg-1",
          content: nil,
          raw_payload: %{
            "toolUseID" => "toolu_only",
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "PreToolUse",
              "hookName" => "format",
              "command" => "mix format"
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert [summary, _detail] = result

      assert summary.tool_use_id == "toolu_only"
      assert summary.thread_key == "toolu_only"
    end

    test "hook_progress with no tool IDs uses unthreaded fallback" do
      messages = [
        %{
          type: :progress,
          uuid: "msg-1",
          content: nil,
          raw_payload: %{
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "SessionStart",
              "hookName" => "startup",
              "command" => "echo hello"
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      assert [summary, detail] = result

      assert summary.tool_use_id == nil
      assert summary.thread_key == "hook-unthreaded"
      assert detail.tool_use_id == nil
      assert detail.thread_key == "hook-unthreaded"
    end

    test "non-hook progress messages are still skipped" do
      messages = [
        %{
          type: :progress,
          uuid: "msg-1",
          content: nil,
          raw_payload: %{"data" => %{"type" => "something_else"}}
        }
      ]

      assert TranscriptRenderer.render(messages) == []
    end

    test "4 consecutive hook_progress messages are collapsed into one group" do
      messages =
        for i <- 1..4 do
          %{
            type: :progress,
            uuid: "hook-uuid-#{i}",
            content: nil,
            raw_payload: %{
              "parentToolUseID" => "toolu_bash_1",
              "data" => %{
                "type" => "hook_progress",
                "hookEvent" => "PreToolUse",
                "hookName" => "PreToolUse:Bash",
                "command" => "echo step #{i}"
              }
            }
          }
        end

      result = TranscriptRenderer.render(messages)
      assert length(result) == 5

      [summary | details] = result

      assert summary.kind == :hook_group
      assert summary.line == "hooks PreToolUse PreToolUse:Bash (4)"
      assert summary.message_id == nil
      assert summary.timestamp != nil or summary.timestamp == nil
      assert summary.hook_group != nil

      assert Enum.all?(details, &(&1.kind == :hook_progress))
      assert Enum.all?(details, &(&1.hidden_by_default == true))
      assert Enum.all?(details, &(&1.hook_group == summary.hook_group))

      detail_lines = Enum.map(details, & &1.line)

      assert detail_lines == [
               "hook PreToolUse PreToolUse:Bash: echo step 1",
               "hook PreToolUse PreToolUse:Bash: echo step 2",
               "hook PreToolUse PreToolUse:Bash: echo step 3",
               "hook PreToolUse PreToolUse:Bash: echo step 4"
             ]
    end

    test "different hook events create separate groups" do
      messages = [
        %{
          type: :progress,
          uuid: "hook-1",
          content: nil,
          raw_payload: %{
            "parentToolUseID" => "toolu_1",
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "PreToolUse",
              "hookName" => "check",
              "command" => "echo pre"
            }
          }
        },
        %{
          type: :progress,
          uuid: "hook-2",
          content: nil,
          raw_payload: %{
            "parentToolUseID" => "toolu_1",
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "PostToolUse",
              "hookName" => "check",
              "command" => "echo post"
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      summaries = Enum.filter(result, &(&1.kind == :hook_group))
      assert length(summaries) == 2

      assert Enum.map(summaries, & &1.line) == [
               "hooks PreToolUse check (1)",
               "hooks PostToolUse check (1)"
             ]
    end

    test "hook_progress with output fields renders hook_output rows" do
      messages = [
        %{
          type: :progress,
          uuid: "hook-with-output",
          content: nil,
          raw_payload: %{
            "parentToolUseID" => "toolu_1",
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "PostToolUse",
              "hookName" => "lint",
              "command" => "mix credo",
              "exitCode" => 1,
              "stderr" => "line1\nline2",
              "stdout" => "out1",
              "durationMs" => 150
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)

      summaries = Enum.filter(result, &(&1.kind == :hook_group))
      assert [summary] = summaries
      assert summary.line == "hooks PostToolUse lint (1)"

      details = Enum.filter(result, &(&1.kind == :hook_progress))
      assert [detail] = details
      assert detail.hook_exit_code == 1
      assert detail.hook_stderr == "line1\nline2"
      assert detail.hook_stdout == "out1"
      assert detail.hook_duration_ms == 150

      outputs = Enum.filter(result, &(&1.kind == :hook_output))
      output_lines = Enum.map(outputs, & &1.line)

      assert "↳ exit_code: 1" in output_lines
      assert "↳ duration_ms: 150" in output_lines
      assert "↳ stdout:" in output_lines
      assert "out1" in output_lines
      assert "↳ stderr:" in output_lines
      assert "line1" in output_lines
      assert "line2" in output_lines

      # All output rows share the same hook_group as the summary
      assert Enum.all?(outputs, &(&1.hook_group == summary.hook_group))
      assert Enum.all?(outputs, &(&1.hidden_by_default == true))
    end

    test "hook_progress without output fields renders no hook_output rows" do
      messages = [
        %{
          type: :progress,
          uuid: "hook-no-output",
          content: nil,
          raw_payload: %{
            "parentToolUseID" => "toolu_1",
            "data" => %{
              "type" => "hook_progress",
              "hookEvent" => "PreToolUse",
              "hookName" => "check",
              "command" => "echo hi"
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      outputs = Enum.filter(result, &(&1.kind == :hook_output))
      assert outputs == []
    end
  end

  describe "⎿ removal and boilerplate suppression" do
    test "no rendered line contains the ⎿ character" do
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
                "input" => %{"command" => "ls"}
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
                "content" => "file1.txt\nfile2.txt"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      refute Enum.any?(result, &(&1.line =~ "⎿"))
    end

    test "Write tool_result with only boilerplate success line renders no rows" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Write",
                "id" => "toolu_write",
                "input" => %{"file_path" => "/tmp/foo.ex", "content" => "defmodule Foo do\nend"}
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
                "tool_use_id" => "toolu_write",
                "content" => "The file /tmp/foo.ex has been updated successfully."
              }
            ]
          },
          raw_payload: %{}
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert tool_result_lines == []
    end

    test "Edit with structuredPatch emits only diff rows, no generic success lines" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_edit",
                "input" => %{
                  "file_path" => "/tmp/app.ex",
                  "old_string" => "old",
                  "new_string" => "new"
                }
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
                "tool_use_id" => "toolu_edit",
                "content" => "The file /tmp/app.ex has been updated successfully."
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => %{
              "structuredPatch" => [
                %{
                  "oldStart" => 1,
                  "oldLines" => 1,
                  "newStart" => 1,
                  "newLines" => 1,
                  "lines" => ["-old", "+new"]
                }
              ]
            }
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      # All tool_result lines should be diff lines, none should be the success boilerplate
      assert Enum.all?(tool_result_lines, &(&1.code_language == "diff"))
      refute Enum.any?(tool_result_lines, &(&1.line =~ "has been updated successfully"))
    end

    test "no fixture transcript line contains ⎿" do
      for fixture <- ["short.jsonl", "tool_heavy.jsonl", "subagent.jsonl"] do
        messages = load_fixture(fixture)
        result = TranscriptRenderer.render(messages)
        refute Enum.any?(result, &(&1.line =~ "⎿")), "#{fixture}: found ⎿ in rendered line"
      end
    end
  end

  describe "timestamp metadata" do
    test "timestamp only on first rendered line of a message" do
      ts = ~U[2026-02-13 10:00:00Z]

      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ts,
          content: %{"blocks" => [%{"type" => "text", "text" => "first\nsecond"}]}
        }
      ]

      result = TranscriptRenderer.render(messages)
      first = Enum.at(result, 0)
      second = Enum.at(result, 1)

      assert first.timestamp == ts
      assert second.timestamp == nil
    end

    test "row-to-row delta computed correctly" do
      ts1 = ~U[2026-02-13 10:00:00Z]
      ts2 = ~U[2026-02-13 10:00:30Z]

      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ts1,
          content: %{"blocks" => [%{"type" => "text", "text" => "first"}]}
        },
        %{
          type: :assistant,
          uuid: "msg-2",
          timestamp: ts2,
          content: %{"blocks" => [%{"type" => "text", "text" => "second"}]}
        }
      ]

      result = TranscriptRenderer.render(messages)
      first = Enum.find(result, &(&1.line == "first"))
      second = Enum.find(result, &(&1.line == "second"))

      assert first.timestamp_delta_seconds == nil
      assert first.timestamp_delta_slow? == nil
      assert second.timestamp_delta_seconds == 30
      assert second.timestamp_delta_slow? == false
    end

    test "slow flag set when delta > 60" do
      ts1 = ~U[2026-02-13 10:00:00Z]
      ts2 = ~U[2026-02-13 10:02:00Z]

      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ts1,
          content: %{"blocks" => [%{"type" => "text", "text" => "first"}]}
        },
        %{
          type: :assistant,
          uuid: "msg-2",
          timestamp: ts2,
          content: %{"blocks" => [%{"type" => "text", "text" => "second"}]}
        }
      ]

      result = TranscriptRenderer.render(messages)
      second = Enum.find(result, &(&1.line == "second"))

      assert second.timestamp_delta_seconds == 120
      assert second.timestamp_delta_slow? == true
    end

    test "missing timestamp treated as nil" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{"blocks" => [%{"type" => "text", "text" => "no timestamp"}]}
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert line.timestamp == nil
      assert line.timestamp_delta_seconds == nil
    end
  end

  describe "tool duration metadata" do
    test "tool duration computed for tool_use with matching tool_result" do
      ts1 = ~U[2026-02-13 10:00:00Z]
      ts2 = ~U[2026-02-13 10:00:45Z]

      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ts1,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_dur",
                "input" => %{"command" => "sleep 45"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          timestamp: ts2,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_dur",
                "content" => "done"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_use = Enum.find(result, &(&1.kind == :tool_use))

      assert tool_use.tool_duration_seconds == 45
      assert tool_use.tool_duration_slow? == false
    end

    test "tool duration slow flag when > 60s" do
      ts1 = ~U[2026-02-13 10:00:00Z]
      ts2 = ~U[2026-02-13 10:01:30Z]

      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ts1,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_slow",
                "input" => %{"command" => "sleep 90"}
              }
            ]
          }
        },
        %{
          type: :user,
          uuid: "msg-2",
          timestamp: ts2,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_slow",
                "content" => "done"
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_use = Enum.find(result, &(&1.kind == :tool_use))

      assert tool_use.tool_duration_seconds == 90
      assert tool_use.tool_duration_slow? == true
    end

    test "no tool duration when no matching tool_result" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ~U[2026-02-13 10:00:00Z],
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_orphan",
                "input" => %{"command" => "echo hi"}
              }
            ]
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_use = Enum.find(result, &(&1.kind == :tool_use))

      assert tool_use.tool_duration_seconds == nil
      assert tool_use.tool_duration_slow? == nil
    end

    test "non-tool_use lines have nil tool duration" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          timestamp: ~U[2026-02-13 10:00:00Z],
          content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]}
        }
      ]

      [line] = TranscriptRenderer.render(messages)
      assert line.tool_duration_seconds == nil
      assert line.tool_duration_slow? == nil
    end
  end

  describe "malformed toolUseResult payloads" do
    test "Edit with string toolUseResult renders generic fallback instead of crashing" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_err1",
                "input" => %{
                  "file_path" => "/tmp/foo.ex",
                  "old_string" => "x",
                  "new_string" => "y"
                }
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
                "tool_use_id" => "toolu_err1",
                "content" => "Error: String to replace not found in file",
                "is_error" => true
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => "Error: String to replace not found in file"
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert [first | _] = tool_result_lines
      assert first.line =~ "Error: String to replace not found"
    end

    test "Edit with nil toolUseResult renders generic fallback" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Edit",
                "id" => "toolu_nil1",
                "input" => %{
                  "file_path" => "/tmp/foo.ex",
                  "old_string" => "x",
                  "new_string" => "y"
                }
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
                "tool_use_id" => "toolu_nil1",
                "content" => "Edit failed"
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => nil
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      tool_result_lines = Enum.filter(result, &(&1.kind == :tool_result))

      assert [_ | _] = tool_result_lines
    end

    test "AskUserQuestion with string toolUseResult renders empty answers" do
      messages = [
        %{
          type: :assistant,
          uuid: "msg-1",
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "AskUserQuestion",
                "id" => "toolu_ask1",
                "input" => %{"questions" => [%{"question" => "Pick one", "header" => "Choice"}]}
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
                "tool_use_id" => "toolu_ask1",
                "content" => "user responded"
              }
            ]
          },
          raw_payload: %{
            "toolUseResult" => "user responded"
          }
        }
      ]

      result = TranscriptRenderer.render(messages)
      ask_answers = Enum.filter(result, &(&1.kind == :ask_user_answer))

      assert ask_answers == []
    end
  end

  defp load_fixture(name) do
    path = Path.join(@fixtures_dir, name)
    {:ok, %{messages: messages}} = JsonlParser.parse_session_file(path)
    messages
  end
end
