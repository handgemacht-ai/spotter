defmodule Spotter.Services.PromptCollectorTest do
  use Spotter.DataCase

  alias Spotter.Services.PromptCollector
  alias Spotter.Transcripts.{Message, Project, Session, Subagent}

  @now ~U[2026-02-13 12:00:00Z]

  defp create_project do
    Ash.create!(Project, %{
      name: "test-#{System.unique_integer([:positive])}",
      pattern: "^test"
    })
  end

  defp create_session(project) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id
    })
  end

  defp create_message(session, attrs) do
    defaults = %{
      uuid: Ash.UUID.generate(),
      type: :user,
      role: :user,
      timestamp: @now,
      session_id: session.id,
      content: %{"text" => "hello world"}
    }

    Ash.create!(Message, Map.merge(defaults, attrs))
  end

  defp default_opts(overrides \\ %{}) do
    Map.merge(
      %{
        scope: :global,
        project_id: nil,
        timespan_days: nil,
        prompt_limit: 100,
        max_prompt_chars: 400,
        now: @now
      },
      overrides
    )
  end

  describe "collect/1" do
    test "collects user prompts" do
      project = create_project()
      session = create_session(project)
      create_message(session, %{content: %{"text" => "fix the bug"}, timestamp: @now})

      result = PromptCollector.collect(default_opts())

      assert length(result.items) == 1
      assert hd(result.items).prompt == "fix the bug"
      assert hd(result.items).project_id == project.id
      assert result.meta.prompts_analyzed == 1
      assert result.meta.prompts_total == 1
    end

    test "excludes messages with subagent_id set" do
      project = create_project()
      session = create_session(project)

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "agent-123",
          session_id: session.id,
          subagent_type: "task"
        })

      create_message(session, %{subagent_id: subagent.id, content: %{"text" => "subagent msg"}})
      create_message(session, %{content: %{"text" => "user msg"}})

      result = PromptCollector.collect(default_opts())

      assert length(result.items) == 1
      assert hd(result.items).prompt == "user msg"
    end

    test "skips tool-result-wrapper user messages" do
      project = create_project()
      session = create_session(project)

      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "tool_result", "content" => "result1"},
            %{"type" => "tool_result", "content" => "result2"}
          ]
        }
      })

      create_message(session, %{content: %{"text" => "real prompt"}})

      result = PromptCollector.collect(default_opts())

      assert length(result.items) == 1
      assert hd(result.items).prompt == "real prompt"
    end

    test "does not skip messages with mixed block types" do
      project = create_project()
      session = create_session(project)

      create_message(session, %{
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "some text"},
            %{"type" => "tool_result", "content" => "result"}
          ]
        }
      })

      result = PromptCollector.collect(default_opts())

      assert length(result.items) == 1
    end

    test "timespan filtering works" do
      project = create_project()
      session = create_session(project)

      # Message within timespan (1 day ago)
      create_message(session, %{
        timestamp: DateTime.add(@now, -1 * 86_400, :second),
        content: %{"text" => "recent"}
      })

      # Message outside timespan (10 days ago)
      create_message(session, %{
        timestamp: DateTime.add(@now, -10 * 86_400, :second),
        content: %{"text" => "old"}
      })

      result = PromptCollector.collect(default_opts(%{timespan_days: 7}))

      assert length(result.items) == 1
      assert hd(result.items).prompt == "recent"
    end

    test "respects prompt_limit" do
      project = create_project()
      session = create_session(project)

      for i <- 1..5 do
        create_message(session, %{
          timestamp: DateTime.add(@now, -i, :second),
          content: %{"text" => "prompt #{i}"}
        })
      end

      result = PromptCollector.collect(default_opts(%{prompt_limit: 3}))

      assert length(result.items) == 3
    end

    test "respects max_prompt_chars" do
      project = create_project()
      session = create_session(project)
      create_message(session, %{content: %{"text" => String.duplicate("a", 500)}})

      result = PromptCollector.collect(default_opts(%{max_prompt_chars: 100}))

      assert String.length(hd(result.items).prompt) == 100
    end

    test "project scope filters to specific project" do
      project1 = create_project()
      project2 = create_project()
      session1 = create_session(project1)
      session2 = create_session(project2)

      create_message(session1, %{content: %{"text" => "project 1 msg"}})
      create_message(session2, %{content: %{"text" => "project 2 msg"}})

      result =
        PromptCollector.collect(default_opts(%{scope: :project, project_id: project1.id}))

      assert length(result.items) == 1
      assert hd(result.items).prompt == "project 1 msg"
    end

    test "normalizes whitespace" do
      project = create_project()
      session = create_session(project)
      create_message(session, %{content: %{"text" => "  hello   world  \n\t foo  "}})

      result = PromptCollector.collect(default_opts())

      assert hd(result.items).prompt == "hello world foo"
    end

    test "drops empty prompts" do
      project = create_project()
      session = create_session(project)
      create_message(session, %{content: %{"text" => "   "}})

      result = PromptCollector.collect(default_opts())

      assert result.items == []
    end

    test "meta includes unique_prompts count" do
      project = create_project()
      session = create_session(project)

      create_message(session, %{
        timestamp: DateTime.add(@now, -1, :second),
        content: %{"text" => "same prompt"}
      })

      create_message(session, %{
        timestamp: DateTime.add(@now, -2, :second),
        content: %{"text" => "same prompt"}
      })

      create_message(session, %{
        timestamp: DateTime.add(@now, -3, :second),
        content: %{"text" => "different prompt"}
      })

      result = PromptCollector.collect(default_opts())

      assert result.meta.prompts_analyzed == 3
      assert result.meta.unique_prompts == 2
    end
  end
end
