defmodule SpotterWeb.SubagentLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Message, Project, Session, Subagent}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-subagent", pattern: "^test"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    agent_id = "agent-test123"

    subagent =
      Ash.create!(Subagent, %{
        agent_id: agent_id,
        session_id: session.id,
        slug: "test-agent"
      })

    %{session: session, session_id: session_id, subagent: subagent, agent_id: agent_id}
  end

  defp create_message(subagent, attrs) do
    defaults = %{
      uuid: Ash.UUID.generate(),
      type: :assistant,
      role: :assistant,
      timestamp: DateTime.utc_now(),
      session_id: subagent.session_id,
      subagent_id: subagent.id
    }

    Ash.create!(Message, Map.merge(defaults, attrs))
  end

  describe "shared transcript component rendering" do
    test "text rows have transcript-row class", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "Hello from subagent"}]}
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "transcript-row"
      assert html =~ "Hello from subagent"
    end

    test "code rows have is-code class and render as pre/code", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "```elixir\ndef foo, do: :bar\n```"}
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "is-code"
      assert html =~ "data-render-mode=\"code\""
      assert html =~ "language-elixir"
      assert html =~ "<pre"
      assert html =~ "<code"
    end

    test "thinking rows have is-thinking class", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        content: %{
          "blocks" => [
            %{"type" => "thinking", "thinking" => "Deep thoughts"},
            %{"type" => "text", "text" => "Answer"}
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "is-thinking"
      assert html =~ "Deep thoughts"
    end

    test "tool_use rows have is-tool-use class", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "name" => "Bash",
              "id" => "toolu_sub",
              "input" => %{"command" => "echo hello"}
            }
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "is-tool-use"
      assert html =~ "Bash"
    end

    test "tool_result rows have is-tool-result class", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        type: :user,
        role: :user,
        content: %{
          "blocks" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_sub",
              "content" => "result output"
            }
          ]
        }
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "is-tool-result"
    end

    test "user text rows have is-user class", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        type: :user,
        role: :user,
        content: %{"text" => "fix the bug"}
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "is-user"
      assert html =~ "fix the bug"
    end

    test "uses TranscriptHighlighter hook (same as SessionLive)", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "test"}]}
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "TranscriptHighlighter"
    end

    test "shows message token counts on the right side", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
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

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "row-token-count"
      assert html =~ "20 tok"
      assert length(Regex.scan(~r/20 tok/, html)) == 1
    end
  end

  describe "empty state" do
    test "renders empty state when no messages", %{session_id: session_id, agent_id: agent_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      assert html =~ "transcript-empty"
      assert html =~ "No transcript available"
    end
  end

  describe "not found" do
    test "renders not found for unknown agent", %{session_id: session_id} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/nonexistent")

      assert html =~ "Subagent not found"
    end
  end

  describe "relative path rendering" do
    test "absolute paths are relativized using session cwd", %{
      subagent: subagent,
      session_id: session_id,
      agent_id: agent_id
    } do
      create_message(subagent, %{
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

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      # Path should be relativized since session.cwd is /home/user/project
      assert html =~ "lib/foo.ex"
      refute html =~ "/home/user/project/lib/foo.ex"
    end
  end
end
