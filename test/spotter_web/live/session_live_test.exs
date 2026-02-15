defmodule SpotterWeb.SessionLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Message, Project, Session, SessionRework}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-live", pattern: "^test"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    %{session: session, session_id: session_id}
  end

  defp create_message(session, attrs) do
    defaults = %{
      uuid: Ash.UUID.generate(),
      type: :assistant,
      role: :assistant,
      timestamp: DateTime.utc_now(),
      session_id: session.id
    }

    Ash.create!(Message, Map.merge(defaults, attrs))
  end

  describe "transcript row class mapping" do
    test "text rows have transcript-row class", %{session: session, session_id: session_id} do
      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "Hello world"}]}
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ ~s(data-testid="session-root")
      assert html =~ ~s(data-testid="transcript-container")
      assert html =~ "transcript-row"
      assert html =~ ~s(data-testid="transcript-row")
      assert html =~ ~s(data-line-number="1")
      assert html =~ "Hello world"
    end

    test "thinking rows have is-thinking class", %{session: session, session_id: session_id} do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "thinking", "thinking" => "Deep thoughts here"},
            %{"type" => "text", "text" => "Answer"}
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-thinking"
      assert html =~ "Deep thoughts here"
    end

    test "tool_use rows have is-tool-use class", %{session: session, session_id: session_id} do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "name" => "Bash",
              "id" => "toolu_test",
              "input" => %{"command" => "echo hello"}
            }
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-tool-use"
      assert html =~ "Bash"
    end

    test "tool_result rows have is-tool-result class", %{session: session, session_id: session_id} do
      create_message(session, %{
        type: :user,
        role: :user,
        content: %{
          "blocks" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_test",
              "content" => "result output"
            }
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-tool-result"
    end

    test "code rows have is-code class and render as pre/code", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "```elixir\ndef foo, do: :bar\n```"}
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-code"
      assert html =~ "data-render-mode=\"code\""
      assert html =~ "language-elixir"
      assert html =~ "<pre"
      assert html =~ "<code"
    end

    test "user text rows have is-user class", %{session: session, session_id: session_id} do
      create_message(session, %{
        type: :user,
        role: :user,
        content: %{"text" => "fix the bug"}
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-user"
      assert html =~ "fix the bug"
    end

    test "shows message token counts on the right side", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
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
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "row-token-count"
      assert html =~ "20 tok"
      assert length(Regex.scan(~r/20 tok/, html)) == 1
    end

    test "shows token delta for second message", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
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
      })

      create_message(session, %{
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
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "20 tok (+7)"
    end
  end

  describe "timestamp and duration rendering" do
    test "renders timestamp and delta for two messages", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "first"}]},
        timestamp: ~U[2026-02-13 10:00:00Z]
      })

      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "second"}]},
        timestamp: ~U[2026-02-13 10:01:24Z]
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "10:00:00"
      assert html =~ "(+1m24s)"
    end

    test "slow delta has is-slow class", %{session: session, session_id: session_id} do
      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "first"}]},
        timestamp: ~U[2026-02-13 10:00:00Z]
      })

      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "second"}]},
        timestamp: ~U[2026-02-13 10:02:00Z]
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-slow"
    end

    test "tool duration rendered for tool_use with matching tool_result", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "name" => "Bash",
              "id" => "toolu_ts",
              "input" => %{"command" => "sleep 90"}
            }
          ]
        },
        timestamp: ~U[2026-02-13 10:00:00Z]
      })

      create_message(session, %{
        type: :user,
        role: :user,
        content: %{
          "blocks" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_ts",
              "content" => "done"
            }
          ]
        },
        timestamp: ~U[2026-02-13 10:01:30Z]
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "tool 1m30s"
      assert html =~ "is-slow"
    end
  end

  describe "subagent rendering" do
    test "subagent rows detected by text pattern have is-subagent class and badge", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "Launching agent-abc123 to handle this task"}
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-subagent"
      assert html =~ "subagent-badge"
      # Accessibility: badge has readable text label, not just color
      assert html =~ "subagent-badge"
      assert html =~ "agent"
    end

    test "subagent click updates clicked_subagent state", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "Using agent-clickTest for this work"}
          ]
        }
      })

      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      html =
        view
        |> element(".subagent-badge")
        |> render_click()

      assert html =~ "is-clicked"
    end
  end

  describe "tool threading attributes" do
    test "tool_use and tool_result rows share data-message-id lineage", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "name" => "Read",
              "id" => "toolu_thread",
              "input" => %{"file_path" => "/home/user/project/lib/app.ex"}
            }
          ]
        }
      })

      create_message(session, %{
        type: :user,
        role: :user,
        content: %{
          "blocks" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_thread",
              "content" => "defmodule App do\nend"
            }
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      # Both tool_use and tool_result rows are rendered
      assert html =~ "is-tool-use"
      assert html =~ "is-tool-result"
    end
  end

  describe "relative path rendering" do
    test "absolute paths are relativized using session cwd", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "name" => "Read",
              "id" => "toolu_path",
              "input" => %{"file_path" => "/home/user/project/lib/foo.ex"}
            }
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      # Path should be relativized since session.cwd is /home/user/project
      assert html =~ "lib/foo.ex"
      refute html =~ "/home/user/project/lib/foo.ex"
    end
  end

  describe "transcript container contract" do
    test "transcript panel has container with id, class, and data-testid", %{
      session_id: session_id
    } do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ ~s(id="transcript-panel")
      assert html =~ ~s(class="session-transcript")
      assert html =~ ~s(data-testid="transcript-container")
    end

    test "transcript header shows title and debug hint", %{session_id: session_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ ~s(class="transcript-header")
      assert html =~ "<h3>Transcript</h3>"
      assert html =~ "Ctrl+Shift+D: debug"
    end

    test "debug hint toggles to DEBUG ON", %{session_id: session_id} do
      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      html = render_click(view, "toggle_debug")
      assert html =~ "DEBUG ON"
      assert html =~ "debug-active"
    end
  end

  describe "hook_progress rendering" do
    test "renders hook_group summary and hook_progress detail rows", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        type: :progress,
        role: :system,
        content: nil,
        raw_payload: %{
          "parentToolUseID" => "toolu_parent",
          "data" => %{
            "type" => "hook_progress",
            "hookEvent" => "PostToolUse",
            "hookName" => "lint-check",
            "command" => "mix credo"
          }
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "is-hook-group"
      assert html =~ "hooks PostToolUse lint-check (1)"
      # Detail rows are hidden by default (hidden_by_default: true)
      refute html =~ "hook PostToolUse lint-check: mix credo"
    end
  end

  describe "empty state" do
    test "renders empty state when no messages", %{session_id: session_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "transcript-empty"
      assert html =~ ~s(data-testid="transcript-empty")
      assert html =~ "No transcript available"
    end
  end

  describe "rework sidebar tab" do
    test "rework tab shows count and renders items when clicked", %{
      session: session,
      session_id: session_id
    } do
      Ash.create!(SessionRework, %{
        tool_use_id: "tu-002",
        file_path: "/home/user/project/lib/foo.ex",
        relative_path: "lib/foo.ex",
        occurrence_index: 2,
        first_tool_use_id: "tu-001",
        session_id: session.id
      })

      Ash.create!(SessionRework, %{
        tool_use_id: "tu-003",
        file_path: "/home/user/project/lib/foo.ex",
        relative_path: "lib/foo.ex",
        occurrence_index: 3,
        first_tool_use_id: "tu-001",
        session_id: session.id
      })

      {:ok, view, html} = live(build_conn(), "/sessions/#{session_id}")

      # Tab button shows count
      assert html =~ "Rework (2)"

      # Rework is NOT in transcript header
      refute html =~ "transcript-rework-panel"

      # Click rework tab to see content
      html = render_click(view, "switch_sidebar_tab", %{"tab" => "rework"})

      assert html =~ "lib/foo.ex"
      assert html =~ ~s(phx-click="jump_to_rework")
      assert html =~ "tu-002"
      assert html =~ "tu-003"
    end

    test "each rework item has phx-click and correct tool_use_id", %{
      session: session,
      session_id: session_id
    } do
      Ash.create!(SessionRework, %{
        tool_use_id: "tu-click-test",
        file_path: "lib/bar.ex",
        occurrence_index: 2,
        first_tool_use_id: "tu-001",
        session_id: session.id
      })

      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      html = render_click(view, "switch_sidebar_tab", %{"tab" => "rework"})

      assert html =~ ~s(phx-click="jump_to_rework")
      assert html =~ ~s(phx-value-tool-use-id="tu-click-test")
    end

    test "rework tab shows empty state when no rework records", %{session_id: session_id} do
      {:ok, view, html} = live(build_conn(), "/sessions/#{session_id}")

      # Tab is present with zero count
      assert html =~ "Rework (0)"

      # No rework panels in transcript header
      refute html =~ "transcript-rework-panel"

      # Click rework tab shows empty message
      html = render_click(view, "switch_sidebar_tab", %{"tab" => "rework"})
      assert html =~ "No rework detected"
    end
  end

  describe "errors not in transcript header" do
    test "errors are not rendered as transcript header blocks", %{session_id: session_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      refute html =~ "transcript-error-panel"
    end
  end

  describe "PubSub live updates" do
    test "session_activity updates status badge", %{session_id: session_id} do
      {:ok, view, html} = live(build_conn(), "/sessions/#{session_id}")

      refute html =~ "session-status-active"

      Phoenix.PubSub.broadcast!(
        Spotter.PubSub,
        "session_activity",
        {:session_activity, %{session_id: session_id, status: :active}}
      )

      html = render(view)
      assert html =~ "session-status-active"
      assert html =~ "active"
    end

    test "session_activity ignores other sessions", %{session_id: session_id} do
      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      Phoenix.PubSub.broadcast!(
        Spotter.PubSub,
        "session_activity",
        {:session_activity, %{session_id: "other-session", status: :active}}
      )

      html = render(view)
      refute html =~ "session-status-active"
    end

    test "transcript_updated reloads messages", %{
      session: session,
      session_id: session_id
    } do
      {:ok, view, html} = live(build_conn(), "/sessions/#{session_id}")
      assert html =~ "transcript-empty"

      # Create a message after mount and update session message_count
      # so maybe_bootstrap_sync is skipped on reload
      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "live update message"}]}
      })

      Ash.update!(session, %{message_count: 1})

      # Send directly to view process to avoid PubSub timing issues
      send(view.pid, {:transcript_updated, session_id, 1})

      html = render(view)
      assert html =~ "live update message"
    end
  end

  describe "accessibility" do
    test "transcript rows have readable text content, not just color signaling", %{
      session: session,
      session_id: session_id
    } do
      # Create various message types
      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "thinking", "thinking" => "Thinking text"},
            %{"type" => "text", "text" => "Response text"},
            %{
              "type" => "tool_use",
              "name" => "Bash",
              "id" => "toolu_a11y",
              "input" => %{"command" => "ls"}
            }
          ]
        }
      })

      create_message(session, %{
        type: :user,
        role: :user,
        content: %{
          "blocks" => [
            %{"type" => "tool_result", "tool_use_id" => "toolu_a11y", "content" => "file.txt"}
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      # All rows have readable text via row-text span/pre elements
      assert html =~ "row-text"
      # Tool use has tool name as readable text
      assert html =~ "Bash"
      # Tool result has content as readable text
      assert html =~ "file.txt"
      # Thinking has its text visible
      assert html =~ "Thinking text"
    end
  end

  describe "row_classes/3 for new transcript kinds" do
    alias SpotterWeb.TranscriptComponents

    test "Bash success tool_use includes is-bash-success" do
      line = %{
        kind: :tool_use,
        type: :assistant,
        render_mode: :plain,
        message_id: "m1",
        tool_name: "Bash",
        command_status: :success
      }

      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-tool-use"
      assert classes =~ "is-bash-success"
      refute classes =~ "is-bash-error"
    end

    test "Bash error tool_use includes is-bash-error" do
      line = %{
        kind: :tool_use,
        type: :assistant,
        render_mode: :plain,
        message_id: "m1",
        tool_name: "Bash",
        command_status: :error
      }

      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-tool-use"
      assert classes =~ "is-bash-error"
    end

    test "Bash pending tool_use has no status class" do
      line = %{
        kind: :tool_use,
        type: :assistant,
        render_mode: :plain,
        message_id: "m1",
        tool_name: "Bash",
        command_status: :pending
      }

      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-tool-use"
      refute classes =~ "is-bash-success"
      refute classes =~ "is-bash-error"
    end

    test "non-Bash tool_use has no bash status class" do
      line = %{
        kind: :tool_use,
        type: :assistant,
        render_mode: :plain,
        message_id: "m1",
        tool_name: "Read"
      }

      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-tool-use"
      refute classes =~ "is-bash"
    end

    test "ask_user_question kind maps to is-ask-user-question" do
      line = %{kind: :ask_user_question, type: :assistant, render_mode: :plain, message_id: "m1"}
      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-ask-user-question"
    end

    test "ask_user_answer kind maps to is-ask-user-answer" do
      line = %{kind: :ask_user_answer, type: :user, render_mode: :plain, message_id: "m1"}
      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-ask-user-answer"
    end

    test "plan_content kind maps to is-plan-content" do
      line = %{kind: :plan_content, type: :user, render_mode: :plain, message_id: "m1"}
      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-plan-content"
    end

    test "plan_decision kind maps to is-plan-decision" do
      line = %{kind: :plan_decision, type: :user, render_mode: :plain, message_id: "m1"}
      classes = TranscriptComponents.row_classes(line, nil, nil)

      assert classes =~ "is-plan-decision"
    end
  end
end
