defmodule Spotter.Services.SessionSliceResolverTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.SessionSliceResolver
  alias Spotter.Transcripts.{Message, Project, Session, SessionSlice}

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "slice-test", pattern: "^slice"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/slice-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  defp create_message(session, ordinal, attrs) do
    defaults = %{
      uuid: Ash.UUID.generate(),
      type: :assistant,
      role: :assistant,
      timestamp: DateTime.utc_now(),
      session_id: session.id,
      ordinal: ordinal,
      source_scope: "main"
    }

    Ash.create!(Message, Map.merge(defaults, attrs))
  end

  defp create_slice(session, attrs) do
    defaults = %{
      session_id: session.id,
      project_id: session.project_id,
      title: "Test Slice"
    }

    Ash.create!(SessionSlice, Map.merge(defaults, attrs))
  end

  describe "resolve/2" do
    test "returns filtered message windows based on highlight_tool_use_ids", %{session: session} do
      _msg0 =
        create_message(session, 0, %{
          content: %{"blocks" => [%{"type" => "text", "text" => "preamble"}]}
        })

      _msg1 =
        create_message(session, 1, %{
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Read",
                "id" => "toolu_highlight_1",
                "input" => %{"file_path" => "/tmp/foo.ex"}
              }
            ]
          }
        })

      _msg2 =
        create_message(session, 2, %{
          type: :user,
          role: :user,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_highlight_1",
                "content" => "file contents"
              }
            ]
          }
        })

      _msg3 =
        create_message(session, 3, %{
          content: %{"blocks" => [%{"type" => "text", "text" => "epilogue"}]}
        })

      slice =
        create_slice(session, %{
          highlight_tool_use_ids: ["toolu_highlight_1"],
          context_before_lines: 0,
          context_after_lines: 0
        })

      {:ok, windows} = SessionSliceResolver.resolve(session, slice)

      tool_use_ids =
        windows
        |> List.flatten()
        |> Enum.flat_map(fn msg ->
          case msg.content do
            %{"blocks" => blocks} ->
              blocks
              |> Enum.filter(&(&1["type"] == "tool_use"))
              |> Enum.map(& &1["id"])

            _ ->
              []
          end
        end)

      assert "toolu_highlight_1" in tool_use_ids
      assert length(List.flatten(windows)) < 4
    end

    test "context_before_lines expands window before highlighted messages", %{session: session} do
      _msg0 =
        create_message(session, 0, %{
          content: %{"blocks" => [%{"type" => "text", "text" => "context before"}]}
        })

      _msg1 =
        create_message(session, 1, %{
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_ctx",
                "input" => %{"command" => "echo hi"}
              }
            ]
          }
        })

      slice =
        create_slice(session, %{
          highlight_tool_use_ids: ["toolu_ctx"],
          context_before_lines: 1,
          context_after_lines: 0
        })

      {:ok, windows} = SessionSliceResolver.resolve(session, slice)
      flat = List.flatten(windows)

      ordinals = Enum.map(flat, & &1.ordinal)
      assert 0 in ordinals
      assert 1 in ordinals
    end

    test "context_after_lines expands window after highlighted messages", %{session: session} do
      _msg0 =
        create_message(session, 0, %{
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_after",
                "input" => %{"command" => "echo hi"}
              }
            ]
          }
        })

      _msg1 =
        create_message(session, 1, %{
          content: %{"blocks" => [%{"type" => "text", "text" => "context after"}]}
        })

      slice =
        create_slice(session, %{
          highlight_tool_use_ids: ["toolu_after"],
          context_before_lines: 0,
          context_after_lines: 1
        })

      {:ok, windows} = SessionSliceResolver.resolve(session, slice)
      flat = List.flatten(windows)

      ordinals = Enum.map(flat, & &1.ordinal)
      assert 0 in ordinals
      assert 1 in ordinals
    end

    test "overlapping windows merge into one", %{session: session} do
      _msg0 =
        create_message(session, 0, %{
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_a",
                "input" => %{"command" => "echo a"}
              }
            ]
          }
        })

      _msg1 =
        create_message(session, 1, %{
          content: %{"blocks" => [%{"type" => "text", "text" => "gap"}]}
        })

      _msg2 =
        create_message(session, 2, %{
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_b",
                "input" => %{"command" => "echo b"}
              }
            ]
          }
        })

      slice =
        create_slice(session, %{
          highlight_tool_use_ids: ["toolu_a", "toolu_b"],
          context_before_lines: 1,
          context_after_lines: 1
        })

      {:ok, windows} = SessionSliceResolver.resolve(session, slice)

      assert length(windows) == 1
    end

    test "missing tool_use_ids are ignored gracefully", %{session: session} do
      _msg0 =
        create_message(session, 0, %{
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "Bash",
                "id" => "toolu_exists",
                "input" => %{"command" => "echo hi"}
              }
            ]
          }
        })

      slice =
        create_slice(session, %{
          highlight_tool_use_ids: ["toolu_exists", "toolu_nonexistent"],
          context_before_lines: 0,
          context_after_lines: 0
        })

      {:ok, windows} = SessionSliceResolver.resolve(session, slice)

      all_ids =
        windows
        |> List.flatten()
        |> Enum.flat_map(fn msg ->
          case msg.content do
            %{"blocks" => blocks} ->
              blocks
              |> Enum.filter(&(&1["type"] == "tool_use"))
              |> Enum.map(& &1["id"])

            _ ->
              []
          end
        end)

      assert "toolu_exists" in all_ids
      refute "toolu_nonexistent" in all_ids
    end

    test "cross-session slice returns error", %{session: session, project: project} do
      other_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/other",
          project_id: project.id
        })

      slice =
        create_slice(other_session, %{
          highlight_tool_use_ids: ["toolu_x"],
          context_before_lines: 0,
          context_after_lines: 0
        })

      assert {:error, :cross_session_slice} = SessionSliceResolver.resolve(session, slice)
    end
  end
end
