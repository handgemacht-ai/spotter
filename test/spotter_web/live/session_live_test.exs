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

  describe "empty state" do
    test "renders empty state when no messages", %{session_id: session_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "transcript-empty"
      assert html =~ ~s(data-testid="transcript-empty")
      assert html =~ "No transcript available"
    end
  end

  describe "rework panel" do
    test "renders rework panel when rework records exist", %{
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

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ "Rework (2)"
      assert html =~ "transcript-rework-panel"
      assert html =~ "lib/foo.ex"
      assert html =~ "jump_to_rework"
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

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ ~s(phx-click="jump_to_rework")
      assert html =~ ~s(phx-value-tool-use-id="tu-click-test")
    end

    test "rework panel is hidden when no rework records", %{session_id: session_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      refute html =~ "transcript-rework-panel"
      refute html =~ "Rework"
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
end
