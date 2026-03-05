defmodule Spotter.Services.TranscriptTaskActionsTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.TranscriptTaskActions

  describe "extract/2" do
    test "extracts TodoWrite actions and binds marker ids" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TodoWrite",
                "id" => "toolu_todo_1",
                "input" => %{
                  "todos" => [
                    %{"id" => "todo-1", "content" => "Draft plan", "status" => "completed"},
                    %{"id" => "todo-2", "content" => "Implement hook", "status" => "in_progress"}
                  ]
                }
              }
            ]
          }
        }
      ]

      rendered_lines = [
        %{kind: :tool_use, tool_use_id: "toolu_todo_1"},
        %{kind: :tool_result, tool_use_id: "toolu_todo_1"}
      ]

      assert {:ok, actions} = TranscriptTaskActions.extract(messages, rendered_lines)
      assert length(actions) == 1

      assert [action] = actions
      assert action.tool_use_id == "toolu_todo_1"
      assert action.marker_id == "tool-use:toolu_todo_1"
      assert action.action_type == :replace
      assert Enum.map(action.todos, & &1.id) == ["todo-1", "todo-2"]
    end

    test "returns error when TodoWrite action has no matching tool marker" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TodoWrite",
                "id" => "toolu_todo_missing",
                "input" => %{"todos" => []}
              }
            ]
          }
        }
      ]

      assert {:error, {:missing_tool_use_marker, "toolu_todo_missing"}} =
               TranscriptTaskActions.extract(messages, [])
    end

    test "returns error for invalid todo status" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TodoWrite",
                "id" => "toolu_todo_1",
                "input" => %{
                  "todos" => [
                    %{"id" => "todo-1", "content" => "Draft plan", "status" => "blocked"}
                  ]
                }
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_todo_1"}]

      assert {:error, {:invalid_todo_status, "toolu_todo_1", 0}} =
               TranscriptTaskActions.extract(messages, rendered_lines)
    end

    test "returns error when rendered lines contain duplicate tool markers" do
      messages = []

      rendered_lines = [
        %{kind: :tool_use, tool_use_id: "toolu_dup"},
        %{kind: :tool_use, tool_use_id: "toolu_dup"}
      ]

      assert {:error, {:duplicate_tool_use_marker, "toolu_dup"}} =
               TranscriptTaskActions.extract(messages, rendered_lines)
    end

    test "extracts TaskCreate actions as single-item pending todos" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskCreate",
                "id" => "toolu_tc_1",
                "input" => %{
                  "subject" => "Implement auth flow",
                  "description" => "Add OAuth2 login",
                  "activeForm" => "Implementing auth flow"
                }
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_tc_1"}]

      assert {:ok, [action]} = TranscriptTaskActions.extract(messages, rendered_lines)
      assert action.tool_use_id == "toolu_tc_1"
      assert action.marker_id == "tool-use:toolu_tc_1"
      assert action.action_type == :replace
      assert [todo] = action.todos
      assert todo.content == "Implement auth flow"
      assert todo.status == "pending"
    end

    test "extracts TaskUpdate actions with status mapping" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskUpdate",
                "id" => "toolu_tu_1",
                "input" => %{
                  "taskId" => "42",
                  "status" => "completed",
                  "subject" => "Fix login bug"
                }
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_tu_1"}]

      assert {:ok, [action]} = TranscriptTaskActions.extract(messages, rendered_lines)
      assert action.tool_use_id == "toolu_tu_1"
      assert [todo] = action.todos
      assert todo.id == "42"
      assert todo.content == "Fix login bug"
      assert todo.status == "completed"
    end

    test "TaskUpdate falls back to taskId as content when subject is missing" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskUpdate",
                "id" => "toolu_tu_2",
                "input" => %{"taskId" => "99", "status" => "in_progress"}
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_tu_2"}]

      assert {:ok, [action]} = TranscriptTaskActions.extract(messages, rendered_lines)
      assert [todo] = action.todos
      assert todo.content == "99"
      assert todo.status == "in_progress"
    end

    test "TaskUpdate maps deleted status to completed" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskUpdate",
                "id" => "toolu_tu_3",
                "input" => %{"taskId" => "7", "status" => "deleted"}
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_tu_3"}]

      assert {:ok, [action]} = TranscriptTaskActions.extract(messages, rendered_lines)
      assert [todo] = action.todos
      assert todo.status == "completed"
    end

    test "TaskCreate returns error when subject is missing" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskCreate",
                "id" => "toolu_tc_bad",
                "input" => %{"description" => "no subject"}
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_tc_bad"}]

      assert {:error, {:missing_task_subject, "toolu_tc_bad"}} =
               TranscriptTaskActions.extract(messages, rendered_lines)
    end

    test "TaskUpdate returns error when taskId is missing" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskUpdate",
                "id" => "toolu_tu_bad",
                "input" => %{"status" => "completed"}
              }
            ]
          }
        }
      ]

      rendered_lines = [%{kind: :tool_use, tool_use_id: "toolu_tu_bad"}]

      assert {:error, {:missing_task_id, "toolu_tu_bad"}} =
               TranscriptTaskActions.extract(messages, rendered_lines)
    end

    test "extracts mixed TodoWrite, TaskCreate, and TaskUpdate actions in order" do
      messages = [
        %{
          type: :assistant,
          content: %{
            "blocks" => [
              %{
                "type" => "tool_use",
                "name" => "TaskCreate",
                "id" => "toolu_tc",
                "input" => %{"subject" => "Write tests"}
              },
              %{
                "type" => "tool_use",
                "name" => "TodoWrite",
                "id" => "toolu_tw",
                "input" => %{
                  "todos" => [
                    %{"id" => "t1", "content" => "Plan", "status" => "completed"}
                  ]
                }
              },
              %{
                "type" => "tool_use",
                "name" => "TaskUpdate",
                "id" => "toolu_tu",
                "input" => %{"taskId" => "5", "status" => "in_progress"}
              }
            ]
          }
        }
      ]

      rendered_lines = [
        %{kind: :tool_use, tool_use_id: "toolu_tc"},
        %{kind: :tool_use, tool_use_id: "toolu_tw"},
        %{kind: :tool_use, tool_use_id: "toolu_tu"}
      ]

      assert {:ok, actions} = TranscriptTaskActions.extract(messages, rendered_lines)
      assert length(actions) == 3
      assert Enum.map(actions, & &1.tool_use_id) == ["toolu_tc", "toolu_tw", "toolu_tu"]
    end
  end
end
