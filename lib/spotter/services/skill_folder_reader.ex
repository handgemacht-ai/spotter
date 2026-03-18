defmodule Spotter.Services.SkillFolderReader do
  @moduledoc "Service for detecting, listing, and rendering skill/memory folder contents."

  alias Spotter.Services.FileDetail

  require OpenTelemetry.Tracer

  @known_folders %{
    agent_memory: ".claude/agent-memory",
    product_skill: ".claude/skills/product",
    design_skill: ".claude/skills/design",
    claude_rules: ".claude/rules"
  }

  @known_labels %{
    agent_memory: "Agent Memory",
    product_skill: "Product Skill",
    design_skill: "Design Skill",
    claude_rules: "Claude Rules"
  }

  @extension_whitelist ~w(.md .txt .toml .yaml .yml .json .ex .exs .js .ts .css)
  @max_file_size 100_000
  @max_file_count 50

  @dangerous_tags ~r/<\s*\/?\s*(script|style|iframe|object|embed|form|svg|math)\b[^>]*>/i
  @event_handlers ~r/\s+on\w+\s*=\s*"[^"]*"/i
  @dangerous_uris ~r/(href|src)\s*=\s*"(javascript|data):[^"]*"/i

  @doc """
  Detects which known skill/memory folders exist for a project.

  Returns `{:ok, [folder_info]}` or `{:error, reason}`.
  """
  @spec detect_folders(String.t()) :: {:ok, list(map())} | {:error, term()}
  def detect_folders(project_id) do
    OpenTelemetry.Tracer.with_span "spotter.skill_folder.detect_folders",
                                   %{attributes: %{"project.id" => project_id}} do
      case FileDetail.resolve_repo_root(project_id) do
        {:ok, repo_root} ->
          folders =
            @known_folders
            |> Enum.filter(fn {_type, rel_path} ->
              File.dir?(Path.join(repo_root, rel_path))
            end)
            |> Enum.map(fn {type, rel_path} ->
              file_count = count_files(repo_root, rel_path)

              %{
                type: type,
                relative_path: rel_path,
                file_count: file_count,
                label: Map.fetch!(@known_labels, type)
              }
            end)

          OpenTelemetry.Tracer.set_attribute("folder.count", length(folders))
          {:ok, folders}

        {:error, _} ->
          OpenTelemetry.Tracer.set_status(:error, "no_repo_root")
          {:error, :no_repo_root}
      end
    end
  end

  @doc """
  Lists files recursively in a folder, filtered by extension whitelist.

  Returns `{:ok, [file_entry]}` or `{:error, :not_found}`.
  """
  @spec list_files(String.t(), String.t()) :: {:ok, list(map())} | {:error, :not_found}
  def list_files(repo_root, relative_folder) do
    full_path = Path.join(repo_root, relative_folder) |> Path.expand()

    OpenTelemetry.Tracer.with_span "spotter.skill_folder.list_files",
                                   %{attributes: %{"folder.path" => relative_folder}} do
      if path_within?(full_path, repo_root) and File.dir?(full_path) do
        files =
          full_path
          |> list_files_recursive(relative_folder)
          |> Enum.sort_by(& &1.relative_path)
          |> Enum.take(@max_file_count)

        OpenTelemetry.Tracer.set_attribute("file.count", length(files))
        {:ok, files}
      else
        OpenTelemetry.Tracer.set_status(:error, "not_found")
        {:error, :not_found}
      end
    end
  end

  @doc """
  Renders all files in a folder with markdown converted to HTML.

  Returns `{:ok, [rendered_file]}` or `{:error, :not_found}`.
  """
  @spec render_folder(String.t(), String.t()) :: {:ok, list(map())} | {:error, :not_found}
  def render_folder(repo_root, relative_folder) do
    OpenTelemetry.Tracer.with_span "spotter.skill_folder.render_folder",
                                   %{attributes: %{"folder.path" => relative_folder}} do
      case list_files(repo_root, relative_folder) do
        {:ok, files} ->
          rendered =
            files
            |> Enum.map(&render_file(repo_root, &1))
            |> Enum.reject(&is_nil/1)

          OpenTelemetry.Tracer.set_attribute("file.count", length(rendered))
          {:ok, rendered}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Classifies a relative path into a known folder type.

  Returns an atom: `:agent_memory`, `:product_skill`, `:design_skill`, `:claude_rules`, or `:custom`.
  """
  @spec classify_folder(String.t()) :: atom()
  def classify_folder(relative_path) do
    normalized = String.trim_trailing(relative_path, "/")

    match =
      Enum.find(@known_folders, fn {_type, known_path} ->
        normalized == known_path or String.starts_with?(normalized, known_path <> "/")
      end)

    case match do
      {type, _} -> type
      nil -> :custom
    end
  end

  defp count_files(repo_root, relative_folder) do
    repo_root
    |> Path.join(relative_folder)
    |> list_files_recursive(relative_folder)
    |> length()
  end

  defp list_files_recursive(full_path, relative_base) do
    case File.ls(full_path) do
      {:ok, entries} ->
        Enum.flat_map(entries, &expand_entry(full_path, relative_base, &1))

      {:error, _} ->
        []
    end
  end

  defp expand_entry(parent_full, parent_rel, entry) do
    entry_full = Path.join(parent_full, entry)
    entry_rel = Path.join(parent_rel, entry)

    case File.lstat(entry_full) do
      {:ok, %{type: :directory}} ->
        list_files_recursive(entry_full, entry_rel)

      {:ok, %{type: :regular}} ->
        if allowed_extension?(entry),
          do: [%{relative_path: entry_rel, filename: entry}],
          else: []

      _ ->
        []
    end
  end

  defp path_within?(full_path, root) do
    expanded_root = Path.expand(root)
    String.starts_with?(full_path, expanded_root <> "/") or full_path == expanded_root
  end

  defp allowed_extension?(filename) do
    Path.extname(filename) in @extension_whitelist
  end

  defp render_file(repo_root, %{relative_path: rel_path, filename: filename}) do
    full_path = Path.join(repo_root, rel_path)

    with {:ok, %{size: size}} when size <= @max_file_size <- File.stat(full_path),
         {:ok, content} <- File.read(full_path) do
      %{
        relative_path: rel_path,
        filename: filename,
        raw_content: content,
        html_content: render_content(filename, content),
        line_count: content |> String.split("\n") |> length()
      }
    else
      _ -> nil
    end
  end

  defp render_content(filename, content) do
    case Path.extname(filename) do
      ".md" -> render_markdown(content)
      _ -> render_code(filename, content)
    end
  end

  defp render_markdown(content) do
    case Earmark.as_html(content, %Earmark.Options{code_class_prefix: "language-"}) do
      {:ok, html, _warnings} -> sanitize_html(html)
      {:error, _, _} -> Phoenix.HTML.html_escape(content) |> Phoenix.HTML.safe_to_string()
    end
  end

  defp render_code(filename, content) do
    lang = filename |> FileDetail.language_class() |> html_escape()
    escaped = html_escape(content)
    "<pre><code class=\"language-#{lang}\">#{escaped}</code></pre>"
  end

  defp html_escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp sanitize_html(html) do
    html
    |> sanitize_pattern(@dangerous_tags)
    |> sanitize_pattern(@event_handlers)
    |> sanitize_pattern(@dangerous_uris)
  end

  defp sanitize_pattern(html, pattern), do: Regex.replace(pattern, html, "")
end
