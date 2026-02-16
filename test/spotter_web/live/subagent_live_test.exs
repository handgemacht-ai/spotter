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
  end

  describe "annotations" do
    test "shows annotation editor when transcript text is selected", %{
      session_id: session_id,
      agent_id: agent_id
    } do
      {:ok, view, html} = live(build_conn(), "/sessions/#{session_id}/agents/#{agent_id}")

      refute html =~ ~s(class="annotation-form")

      html =
        render_hook(view, "transcript_text_selected", %{
          "text" => "selected snippet",
          "message_ids" => ["msg-1"]
        })

      assert html =~ ~s(class="annotation-form")
      assert html =~ "selected snippet"
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

  describe "row_classes/3 parity with session view" do
    alias SpotterWeb.TranscriptComponents

    test "Bash success/error classes are available in shared component" do
      success = %{
        kind: :tool_use,
        type: :assistant,
        render_mode: :plain,
        message_id: "m1",
        tool_name: "Bash",
        command_status: :success
      }

      error = %{
        kind: :tool_use,
        type: :assistant,
        render_mode: :plain,
        message_id: "m1",
        tool_name: "Bash",
        command_status: :error
      }

      assert TranscriptComponents.row_classes(success, nil, nil) =~ "is-bash-success"
      assert TranscriptComponents.row_classes(error, nil, nil) =~ "is-bash-error"
    end

    test "interactive kind classes are available in shared component" do
      ask_q = %{kind: :ask_user_question, type: :assistant, render_mode: :plain, message_id: "m1"}
      ask_a = %{kind: :ask_user_answer, type: :user, render_mode: :plain, message_id: "m1"}
      plan_c = %{kind: :plan_content, type: :user, render_mode: :plain, message_id: "m1"}
      plan_d = %{kind: :plan_decision, type: :user, render_mode: :plain, message_id: "m1"}

      assert TranscriptComponents.row_classes(ask_q, nil, nil) =~ "is-ask-user-question"
      assert TranscriptComponents.row_classes(ask_a, nil, nil) =~ "is-ask-user-answer"
      assert TranscriptComponents.row_classes(plan_c, nil, nil) =~ "is-plan-content"
      assert TranscriptComponents.row_classes(plan_d, nil, nil) =~ "is-plan-decision"
    end
  end
end
