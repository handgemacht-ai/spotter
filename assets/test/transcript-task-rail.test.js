/**
 * @vitest-environment happy-dom
 */
import { describe, expect, it } from "vitest"
import { deriveTaskState, parseTaskActions } from "../js/hooks/transcript_task_rail"

describe("parseTaskActions", () => {
  it("parses strict TodoWrite action snapshots", () => {
    const actions = parseTaskActions(
      JSON.stringify([
        {
          marker_id: "tool-use:toolu_1",
          tool_use_id: "toolu_1",
          action_type: "replace",
          todos: [
            { id: "t1", content: "Draft plan", status: "completed" },
            { id: "t2", content: "Implement", status: "in_progress" },
          ],
        },
      ]),
    )

    expect(actions).toHaveLength(1)
    expect(actions[0].marker_id).toBe("tool-use:toolu_1")
    expect(actions[0].todos).toHaveLength(2)
  })

  it("throws when marker_id is missing", () => {
    expect(() =>
      parseTaskActions(
        JSON.stringify([
          {
            tool_use_id: "toolu_1",
            action_type: "replace",
            todos: [],
          },
        ]),
      ),
    ).toThrow(/marker_id/)
  })

  it("throws when todo status is invalid", () => {
    expect(() =>
      parseTaskActions(
        JSON.stringify([
          {
            marker_id: "tool-use:toolu_1",
            tool_use_id: "toolu_1",
            action_type: "replace",
            todos: [{ id: "t1", content: "Draft", status: "blocked" }],
          },
        ]),
      ),
    ).toThrow(/invalid status/)
  })
})

describe("deriveTaskState", () => {
  const actions = [
    {
      marker_id: "tool-use:toolu_1",
      tool_use_id: "toolu_1",
      action_type: "replace",
      todos: [{ id: "t1", content: "Draft plan", status: "in_progress" }],
    },
    {
      marker_id: "tool-use:toolu_2",
      tool_use_id: "toolu_2",
      action_type: "replace",
      todos: [{ id: "t1", content: "Draft plan", status: "completed" }],
    },
  ]

  it("returns empty state before first action", () => {
    const state = deriveTaskState(actions, -1)

    expect(state.todos).toEqual([])
    expect(state.updateIndex).toBe(0)
    expect(state.totalUpdates).toBe(2)
  })

  it("returns action snapshot at current index", () => {
    const state = deriveTaskState(actions, 1)

    expect(state.updateIndex).toBe(2)
    expect(state.totalUpdates).toBe(2)
    expect(state.todos[0].status).toBe("completed")
  })
})
