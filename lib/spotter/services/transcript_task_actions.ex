defmodule Spotter.Services.TranscriptTaskActions do
  @moduledoc """
  Extracts task-related tool call actions (TodoWrite, TaskCreate, TaskUpdate)
  from transcript messages and binds them to strict marker IDs present in
  rendered transcript lines.

  The output is intentionally reducer-friendly: each action contains the full task
  snapshot for a single tool call.
  """

  @todo_tool_name "TodoWrite"
  @task_create_tool_name "TaskCreate"
  @task_update_tool_name "TaskUpdate"
  @valid_statuses ~w(pending in_progress completed)

  @type todo_item :: %{
          id: String.t(),
          content: String.t(),
          status: String.t()
        }

  @type task_action :: %{
          tool_use_id: String.t(),
          marker_id: String.t(),
          action_type: :replace,
          todos: [todo_item()]
        }

  @spec marker_id(String.t()) :: String.t()
  def marker_id(tool_use_id) when is_binary(tool_use_id) and tool_use_id != "" do
    "tool-use:" <> tool_use_id
  end

  @spec extract([map()], [map()]) :: {:ok, [task_action()]} | {:error, term()}
  def extract(messages, rendered_lines) when is_list(messages) and is_list(rendered_lines) do
    with {:ok, marker_index} <- build_marker_index(rendered_lines),
         {:ok, actions} <- extract_actions(messages),
         :ok <- ensure_unique_action_ids(actions),
         :ok <- ensure_marker_coverage(actions, marker_index) do
      {:ok,
       Enum.map(actions, fn action ->
         Map.put(action, :marker_id, Map.fetch!(marker_index, action.tool_use_id))
       end)}
    end
  end

  def extract(_messages, _rendered_lines), do: {:error, :invalid_arguments}

  defp build_marker_index(rendered_lines) do
    Enum.reduce_while(rendered_lines, {:ok, %{}}, fn line, {:ok, acc} ->
      case maybe_put_marker(line, acc) do
        {:ok, next_acc} ->
          {:cont, {:ok, next_acc}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp extract_actions(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn msg, {:ok, acc} ->
      case extract_actions_from_message(msg) do
        {:ok, []} ->
          {:cont, {:ok, acc}}

        {:ok, msg_actions} ->
          {:cont, {:ok, Enum.reverse(msg_actions, acc)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, actions_reversed} -> {:ok, Enum.reverse(actions_reversed)}
      error -> error
    end
  end

  defp extract_actions_from_message(%{type: :assistant, content: %{"blocks" => blocks}})
       when is_list(blocks) do
    blocks
    |> Enum.reduce_while({:ok, []}, fn block, {:ok, acc} ->
      case parse_action_block(block) do
        :skip ->
          {:cont, {:ok, acc}}

        {:ok, action} ->
          {:cont, {:ok, [action | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, actions} -> {:ok, Enum.reverse(actions)}
      error -> error
    end
  end

  defp extract_actions_from_message(_msg), do: {:ok, []}

  defp parse_todo_tool_use(block) do
    with {:ok, tool_use_id} <- require_non_empty_string(block["id"], :missing_todo_tool_use_id),
         %{} = input <- block["input"],
         {:ok, todos} <- parse_todo_items(input["todos"], tool_use_id) do
      {:ok,
       %{
         tool_use_id: tool_use_id,
         marker_id: nil,
         action_type: :replace,
         todos: todos
       }}
    else
      nil ->
        {:error, {:missing_todo_input, block["id"]}}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, {:invalid_todo_tool_input, block["id"]}}
    end
  end

  defp parse_todo_items(todos, tool_use_id) when is_list(todos) do
    todos
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {todo, idx}, {:ok, acc} ->
      case parse_todo_item(todo, idx, tool_use_id) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp parse_todo_items(_todos, tool_use_id), do: {:error, {:invalid_todo_list, tool_use_id}}

  defp parse_todo_item(todo, idx, tool_use_id) when is_map(todo) do
    with {:ok, content} <-
           require_non_empty_string(todo["content"], {:invalid_todo_content, tool_use_id, idx}),
         {:ok, status} <- normalize_status(todo["status"], tool_use_id, idx) do
      {:ok,
       %{
         id: normalize_todo_id(todo["id"], content, idx),
         content: content,
         status: status
       }}
    end
  end

  defp parse_todo_item(_todo, idx, tool_use_id),
    do: {:error, {:invalid_todo_item, tool_use_id, idx}}

  defp normalize_status(status, _tool_use_id, _idx) when status in @valid_statuses,
    do: {:ok, status}

  defp normalize_status(status, tool_use_id, idx) when is_atom(status) do
    status
    |> Atom.to_string()
    |> normalize_status(tool_use_id, idx)
  end

  defp normalize_status(_status, tool_use_id, idx),
    do: {:error, {:invalid_todo_status, tool_use_id, idx}}

  defp normalize_todo_id(id, _content, _idx) when is_binary(id) and id != "", do: id

  defp normalize_todo_id(_id, content, idx) do
    "todo-#{:erlang.phash2(content)}-#{idx}"
  end

  defp require_non_empty_string(value, _reason) when is_binary(value) and value != "",
    do: {:ok, value}

  defp require_non_empty_string(_value, reason), do: {:error, reason}

  defp ensure_unique_action_ids(actions) do
    actions
    |> Enum.reduce_while(MapSet.new(), fn action, seen ->
      case MapSet.member?(seen, action.tool_use_id) do
        true -> {:halt, {:duplicate_todo_action, action.tool_use_id}}
        false -> {:cont, MapSet.put(seen, action.tool_use_id)}
      end
    end)
    |> case do
      {:duplicate_todo_action, _tool_use_id} = reason -> {:error, reason}
      _seen -> :ok
    end
  end

  defp ensure_marker_coverage(actions, marker_index) do
    case Enum.find(actions, fn action -> not Map.has_key?(marker_index, action.tool_use_id) end) do
      nil -> :ok
      action -> {:error, {:missing_tool_use_marker, action.tool_use_id}}
    end
  end

  defp maybe_put_marker(
         %{kind: :tool_use, tool_use_id: tool_use_id},
         marker_index
       )
       when is_binary(tool_use_id) and tool_use_id != "" do
    case Map.has_key?(marker_index, tool_use_id) do
      true -> {:error, {:duplicate_tool_use_marker, tool_use_id}}
      false -> {:ok, Map.put(marker_index, tool_use_id, marker_id(tool_use_id))}
    end
  end

  defp maybe_put_marker(_line, marker_index), do: {:ok, marker_index}

  defp parse_action_block(%{"type" => "tool_use", "name" => @todo_tool_name} = block),
    do: parse_todo_tool_use(block)

  defp parse_action_block(%{"type" => "tool_use", "name" => @task_create_tool_name} = block),
    do: parse_task_create(block)

  defp parse_action_block(%{"type" => "tool_use", "name" => @task_update_tool_name} = block),
    do: parse_task_update(block)

  defp parse_action_block(_block), do: :skip

  defp parse_task_create(block) do
    with {:ok, tool_use_id} <- require_non_empty_string(block["id"], :missing_task_create_id),
         %{} = input <- block["input"],
         {:ok, subject} <-
           require_non_empty_string(input["subject"], {:missing_task_subject, tool_use_id}) do
      {:ok,
       %{
         tool_use_id: tool_use_id,
         marker_id: nil,
         action_type: :replace,
         todos: [
           %{
             id: "task-#{:erlang.phash2(subject)}",
             content: subject,
             status: "pending"
           }
         ]
       }}
    else
      nil -> {:error, {:missing_task_create_input, block["id"]}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_task_update(block) do
    with {:ok, tool_use_id} <- require_non_empty_string(block["id"], :missing_task_update_id),
         %{} = input <- block["input"],
         {:ok, task_id} <-
           require_non_empty_string(input["taskId"], {:missing_task_id, tool_use_id}),
         {:ok, status} <- normalize_task_update_status(input["status"], input, tool_use_id) do
      content = input["subject"] || task_id

      {:ok,
       %{
         tool_use_id: tool_use_id,
         marker_id: nil,
         action_type: :replace,
         todos: [
           %{
             id: task_id,
             content: content,
             status: status
           }
         ]
       }}
    else
      nil -> {:error, {:missing_task_update_input, block["id"]}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_task_update_status(status, _input, _tool_use_id)
       when status in @valid_statuses,
       do: {:ok, status}

  defp normalize_task_update_status("deleted", _input, _tool_use_id),
    do: {:ok, "completed"}

  defp normalize_task_update_status(nil, _input, _tool_use_id),
    do: {:ok, "pending"}

  defp normalize_task_update_status(_status, _input, tool_use_id),
    do: {:error, {:invalid_task_update_status, tool_use_id}}
end
