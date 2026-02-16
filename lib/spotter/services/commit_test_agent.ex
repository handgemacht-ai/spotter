defmodule Spotter.Services.CommitTestAgent do
  @moduledoc """
  Runs the Claude Agent SDK to sync test records for a single file.

  The agent inspects the diff and current file content, then uses CRUD
  tools to create/update/delete test case records in the database.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Agents.TestToolServer
  alias Spotter.Observability.ClaudeAgentFlow
  alias Spotter.Observability.FlowKeys
  alias Spotter.Services.ClaudeCode.ResultExtractor
  alias Spotter.Services.CommitTestPermissions

  @default_model "sonnet"
  @default_max_turns 8
  @default_timeout_ms 180_000

  @ext_to_lang %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".js" => "javascript",
    ".jsx" => "javascript",
    ".ts" => "typescript",
    ".tsx" => "typescript",
    ".py" => "python",
    ".rb" => "ruby",
    ".rs" => "rust",
    ".go" => "go",
    ".java" => "java",
    ".kt" => "kotlin",
    ".swift" => "swift"
  }

  @doc """
  Runs the agent for a single file.

  ## Input

  - `project_id` - Project UUID
  - `commit_hash` - 40-hex commit hash
  - `relative_path` - File path relative to project root
  - `file_content` - Current file content at this commit
  - `file_diff` - Unified diff for this file
  - `opts` - Optional: `model` (default "sonnet"), `max_turns` (default 8)

  ## Returns

  - `{:ok, %{model_used: String.t(), tool_counts: map(), final_text: String.t() | nil}}`
  - `{:error, term()}`
  """
  @spec run_file(map()) :: {:ok, map()} | {:error, term()}
  def run_file(
        %{
          project_id: project_id,
          commit_hash: commit_hash,
          relative_path: relative_path,
          file_content: file_content,
          file_diff: file_diff
        } = input
      ) do
    opts = Map.get(input, :opts, %{})
    model = opts[:model] || @default_model
    max_turns = opts[:max_turns] || @default_max_turns

    Tracer.with_span "spotter.commit_tests.agent.run_file" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)
      Tracer.set_attribute("spotter.relative_path", relative_path)
      Tracer.set_attribute("spotter.model_requested", model)
      Tracer.set_attribute("spotter.diff_bytes", byte_size(file_diff))
      Tracer.set_attribute("spotter.file_bytes", byte_size(file_content))

      prompt =
        build_prompt(%{
          project_id: project_id,
          commit_hash: commit_hash,
          relative_path: relative_path,
          file_content: file_content,
          file_diff: file_diff
        })

      server = TestToolServer.create_server()

      sdk_opts =
        %ClaudeAgentSDK.Options{
          model: model,
          max_turns: max_turns,
          timeout_ms: @default_timeout_ms,
          permission_mode: :dont_ask,
          tools: [],
          mcp_servers: %{"spotter-tests" => server},
          allowed_tools: TestToolServer.allowed_tools(),
          can_use_tool: &CommitTestPermissions.can_use_tool/1
        }
        |> ClaudeAgentFlow.build_opts()

      flow_keys = [FlowKeys.project(project_id), FlowKeys.commit(commit_hash)]

      try do
        messages =
          prompt
          |> ClaudeAgentSDK.query(sdk_opts)
          |> ClaudeAgentFlow.wrap_stream(flow_keys: flow_keys)
          |> Enum.to_list()

        model_used = ResultExtractor.extract_model_used(messages) || model
        Tracer.set_attribute("spotter.model_used", model_used)
        tool_counts = extract_tool_counts(messages)
        final_text = extract_final_text(messages)

        {:ok, %{model_used: model_used, tool_counts: tool_counts, final_text: final_text}}
      rescue
        e ->
          reason = Exception.message(e)
          Tracer.set_status(:error, reason)
          {:error, reason}
      end
    end
  end

  @doc "Builds the prompt string for the agent."
  @spec build_prompt(map()) :: String.t()
  def build_prompt(%{
        project_id: project_id,
        commit_hash: commit_hash,
        relative_path: relative_path,
        file_content: file_content,
        file_diff: file_diff
      }) do
    lang = lang_for_path(relative_path)

    """
    Commit: #{commit_hash}
    File: #{relative_path}
    Project ID: #{project_id}

    ## Instructions

    1. Call `mcp__spotter-tests__list_tests` with project_id="#{project_id}" and relative_path="#{relative_path}" to see currently stored tests for this file.
    2. Review the diff below to understand what changed.
    3. Review the current file content below.
    4. Ensure the database mirrors the actual tests in the file by calling create_test, update_test, and delete_test tools as needed.
    5. For each test, set given, when, and then lists (empty lists are allowed if not inferable from context).
    6. IMPORTANT: Every create_test and update_test call MUST include source_commit_hash="#{commit_hash}".
    7. End by printing a short JSON summary (no markdown fences):
       { "recognized_tests": N, "created": n, "updated": n, "deleted": n }

    ## Diff

    ```diff
    #{file_diff}
    ```

    ## Current file content

    ```#{lang}
    #{file_content}
    ```
    """
  end

  @doc "Extracts tool invocation counts from SDK messages."
  @spec extract_tool_counts([map()]) :: map()
  def extract_tool_counts(messages) do
    allowed = MapSet.new(TestToolServer.allowed_tools())

    messages
    |> Enum.flat_map(&extract_tool_names/1)
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> Enum.frequencies()
  end

  defp extract_tool_names(%{type: "assistant", message: %{content: content}})
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(%{type: "assistant", message: %{"content" => content}})
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(%ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{content: content}}
       })
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(%ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(_), do: []

  defp extract_final_text(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      case ClaudeAgentSDK.ContentExtractor.extract_text(msg) do
        nil -> nil
        "" -> nil
        text -> text
      end
    end)
  rescue
    _ -> nil
  end

  defp lang_for_path(path) do
    ext = Path.extname(path)
    Map.get(@ext_to_lang, ext, "text")
  end
end
