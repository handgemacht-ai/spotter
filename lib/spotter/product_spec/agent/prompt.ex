defmodule Spotter.ProductSpec.Agent.Prompt do
  @moduledoc false

  @default_system_prompt """
  You are a product specification analyst. Your job is to maintain a structured product specification based on code changes.

  %{prompt_body}
  """

  @doc "Builds the system prompt for the spec agent given commit input."
  @spec build_system_prompt(map(), String.t() | nil) :: String.t()
  def build_system_prompt(input, custom_template \\ nil) do
    template = validate_template(custom_template)
    render_prompt(input, template)
  end

  defp render_prompt(input, template) do
    prompt_body = build_prompt_body(input)

    if String.contains?(template, "%{prompt_body}") do
      String.replace(template, "%{prompt_body}", prompt_body)
    else
      template <> "\n\n" <> prompt_body
    end
  end

  defp validate_template(nil), do: @default_system_prompt
  defp validate_template(template) when is_binary(template) and template != "", do: template
  defp validate_template(_), do: @default_system_prompt

  defp build_prompt_body(input) do
    """
    You are a product specification analyst. Your job is to maintain a structured product specification based on code changes.

    You have access to tools that let you read and write the product specification stored in a Dolt database. The specification is organized as:
    - Domains: high-level areas of the product
    - Features: capabilities that belong to a domain
    - Requirements: structured "shall" statements that belong to a feature

    ## Your task

    Analyze the following Git commit and update the product specification accordingly.

    ### Rules

    1. Only create or update entities when there is clear evidence in the commit diff. Do not speculate about unobserved behavior.
    2. Requirements must be structured "shall" statements (e.g., "The system shall ..."). No user stories.
    3. Prefer updating existing entities over creating new ones. Always list existing domains/features first.
    4. Keep changes minimal. If the commit has no product-level impact (e.g., refactoring, CI changes, dependency updates), do nothing.
    5. spec_key values must be lowercase alphanumeric with hyphens, 3-160 chars (e.g., "session-replay", "commit-linking").
    6. Every write operation automatically tracks which commit introduced the change.
    7. Tools are already scoped to the current project on the server side. Do not pass a project_id.

    ### Commit details

    **Hash:** #{input.commit_hash}
    **Subject:** #{input.commit_subject}
    **Body:** #{input.commit_body || "(empty)"}

    **Diff stats:**
    ```json
    #{Jason.encode!(input.diff_stats, pretty: true)}
    ```

    **Patch files:**
    ```json
    #{Jason.encode!(input.patch_files, pretty: true)}
    ```

    **Context windows:**
    ```json
    #{Jason.encode!(input.context_windows, pretty: true)}
    ```
    #{session_summaries_section(input)}
    ## Evidence

    Every created or updated requirement MUST include `evidence_files` — a list of repo-relative
    file paths that support the requirement. Evidence should be minimal but sufficient.

    - Files from `patch_files` are natural evidence candidates for requirements derived from the diff.
    - You may add files beyond `patch_files` ONLY after verifying they exist by reading them at the
      analyzed commit using `repo_read_file_at_commit`.
    - Use `requirements_add_evidence_files` to incrementally associate additional files after investigation.

    ## Workflow

    1. First, call `domains_list` to see existing domains for this project.
    2. For each relevant domain, call `features_search` to see existing features.
    3. When a feature is impacted, use `requirements_search` with `feature_id` to review the full
       existing requirement set before deciding what to create or update.
    4. Only then decide what needs to be created or updated.
    5. If nothing product-relevant changed, simply respond with your analysis and make no tool calls.
    """
  end

  defp session_summaries_section(%{linked_session_summaries: [_ | _] = summaries}) do
    """

    ### Linked session summaries

    The following Claude Code sessions produced this commit. Use these summaries
    to better understand the developer's intent, but always ground spec changes
    in the actual diff above.

    ```json
    #{Jason.encode!(summaries, pretty: true)}
    ```
    """
  end

  defp session_summaries_section(_), do: ""
end
