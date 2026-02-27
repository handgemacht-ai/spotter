defmodule Spotter.Transcripts.RetroMcpActionsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Test.OtelHelpers
  alias Spotter.Transcripts.{Project, RetroSubmission, Session}

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    OtelHelpers.setup_otel_test(%{})

    project = Ash.create!(Project, %{name: "retro-mcp-test", pattern: "^retro"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id
      })

    %{project: project, session: session}
  end

  describe "mcp_submit" do
    test "creates submission with child items", %{project: project, session: session} do
      items = [
        %{
          "category" => "knowledge_gained",
          "observation" => "Learned Ash",
          "explanation" => "DSL is declarative"
        },
        %{
          "category" => "gotcha",
          "observation" => "SQLite quirk",
          "explanation" => "FKs need pragma"
        }
      ]

      submission =
        Ash.create!(
          RetroSubmission,
          %{session_id: session.session_id, items: items},
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert submission.id != nil
      assert submission.project_id == project.id
      assert submission.submitted_at != nil

      loaded = Ash.load!(submission, :items)
      assert length(loaded.items) == 2

      categories = Enum.map(loaded.items, & &1.category) |> Enum.sort()
      assert categories == [:gotcha, :knowledge_gained]
    end

    test "sets submitted_at automatically", %{project: project, session: session} do
      before = DateTime.utc_now()

      submission =
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{
                "category" => "struggle",
                "observation" => "obs",
                "explanation" => "exp"
              }
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert DateTime.compare(submission.submitted_at, before) in [:gt, :eq]
    end

    test "rejects session_id from different project", %{session: session} do
      other_project = Ash.create!(Project, %{name: "other-proj", pattern: "^other"})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{"category" => "gotcha", "observation" => "obs", "explanation" => "exp"}
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: other_project.id}}
        )
      end
    end

    test "rejects calls without MCP project scope", %{session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{"category" => "gotcha", "observation" => "obs", "explanation" => "exp"}
            ]
          },
          action: :mcp_submit
        )
      end
    end

    test "rejects empty items array", %{project: project, session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          RetroSubmission,
          %{session_id: session.session_id, items: []},
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )
      end
    end

    test "rejects item with invalid category", %{project: project, session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{
                "category" => "invalid_category",
                "observation" => "obs",
                "explanation" => "exp"
              }
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )
      end
    end

    test "accepts optional summary", %{project: project, session: session} do
      submission =
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            summary: "Good session",
            items: [
              %{
                "category" => "effective_strategy",
                "observation" => "obs",
                "explanation" => "exp"
              }
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert submission.summary == "Good session"
    end

    test "emits spotter.retro.submit_items span with item_count", %{
      project: project,
      session: session
    } do
      Ash.create!(
        RetroSubmission,
        %{
          session_id: session.session_id,
          items: [
            %{"category" => "knowledge_gained", "observation" => "obs1", "explanation" => "exp1"},
            %{"category" => "gotcha", "observation" => "obs2", "explanation" => "exp2"},
            %{"category" => "struggle", "observation" => "obs3", "explanation" => "exp3"}
          ]
        },
        action: :mcp_submit,
        context: %{spotter_mcp_scope: %{project_id: project.id}}
      )

      OtelHelpers.assert_span_attributes(
        "spotter.retro.submit_items",
        %{"retro.item_count": 3}
      )
    end
  end

  describe "mcp_list" do
    test "returns submissions scoped to caller's project", %{project: project, session: session} do
      Ash.create!(
        RetroSubmission,
        %{
          session_id: session.session_id,
          items: [
            %{"category" => "gotcha", "observation" => "obs", "explanation" => "exp"}
          ]
        },
        action: :mcp_submit,
        context: %{spotter_mcp_scope: %{project_id: project.id}}
      )

      submissions =
        Ash.read!(
          RetroSubmission,
          action: :mcp_list,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert length(submissions) == 1
      assert hd(submissions).project_id == project.id
    end

    test "does not return submissions from other projects", %{
      project: project,
      session: session
    } do
      Ash.create!(
        RetroSubmission,
        %{
          session_id: session.session_id,
          items: [
            %{"category" => "gotcha", "observation" => "obs", "explanation" => "exp"}
          ]
        },
        action: :mcp_submit,
        context: %{spotter_mcp_scope: %{project_id: project.id}}
      )

      other_project = Ash.create!(Project, %{name: "other-list", pattern: "^other"})

      submissions =
        Ash.read!(
          RetroSubmission,
          action: :mcp_list,
          context: %{spotter_mcp_scope: %{project_id: other_project.id}}
        )

      assert submissions == []
    end

    test "rejects calls without MCP project scope" do
      assert_raise Ash.Error.Unknown, fn ->
        Ash.read!(RetroSubmission, action: :mcp_list)
      end
    end
  end
end
