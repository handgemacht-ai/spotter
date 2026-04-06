defmodule Mix.Tasks.Spotter.Transcripts.Audit do
  @moduledoc "Compare raw JSONL against imported data to detect import gaps."
  @shortdoc "Audit transcript import completeness"
  use Mix.Task

  alias Spotter.Transcripts.{JsonlParser, Message, Session}

  require Ash.Query

  @switches [
    session: :string,
    file: :string,
    project: :string,
    limit: :integer,
    format: :string
  ]

  @impl true
  def run(args) do
    if "--help" in args do
      print_usage()
    else
      do_run(args)
    end
  end

  defp do_run(args) do
    Mix.Tasks.Spotter.CliHelpers.start_app_without_server()

    opts = Mix.Tasks.Spotter.CliHelpers.parse_args!(args, @switches, &print_usage/0)

    format = opts[:format] || "table"

    cond do
      opts[:file] ->
        audit_file(opts[:file], format)

      opts[:session] ->
        audit_session(opts[:session], format)

      opts[:project] ->
        audit_project(opts[:project], opts[:limit] || 20, format)

      true ->
        print_usage()
    end
  end

  defp audit_file(path, format) do
    expanded = Path.expand(path)

    unless File.exists?(expanded) do
      Mix.shell().error("File not found: #{expanded}")
      System.halt(1)
    end

    jsonl_lines = count_jsonl_lines(expanded)
    parsed_types = parse_jsonl_types(expanded)
    session_id = extract_session_id(expanded)

    db_messages =
      if session_id do
        case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!() do
          nil -> nil
          session -> load_db_messages(session)
        end
      end

    print_audit(path, jsonl_lines, parsed_types, db_messages, format)
  end

  defp audit_session(session_id, format) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!() do
      nil ->
        Mix.shell().error("Session not found: #{session_id}")

      session ->
        db_messages = load_db_messages(session)
        jsonl_path = find_jsonl_path(session)

        if jsonl_path do
          jsonl_lines = count_jsonl_lines(jsonl_path)
          parsed_types = parse_jsonl_types(jsonl_path)
          print_audit(jsonl_path, jsonl_lines, parsed_types, db_messages, format)
        else
          Mix.shell().info(
            "Session #{session_id}: #{length(db_messages)} messages in DB (JSONL file not found)"
          )
        end
    end
  end

  defp audit_project(project_id, limit, format) do
    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(limit)
      |> Ash.read!()

    if sessions == [] do
      Mix.shell().error("No sessions found for project #{project_id}")
    else
      Enum.each(sessions, fn session ->
        audit_session(session.session_id, format)
        Mix.shell().info("")
      end)
    end
  end

  defp load_db_messages(session) do
    Message
    |> Ash.Query.filter(session_id == ^session.id and is_nil(subagent_id))
    |> Ash.read!()
  end

  defp extract_session_id(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{"sessionId" => sid}} when is_binary(sid) -> sid
        _ -> nil
      end
    end)
  end

  defp count_jsonl_lines(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.count()
  end

  defp parse_jsonl_types(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.reduce(%{types: %{}, parse_errors: 0, with_usage: 0, unknown_types: []}, fn line,
                                                                                        acc ->
      classify_line(line, acc)
    end)
  end

  defp classify_line(line, acc) do
    case Jason.decode(line) do
      {:ok, data} -> classify_parsed_line(data, acc)
      {:error, _} -> update_in(acc, [:parse_errors], &(&1 + 1))
    end
  end

  defp classify_parsed_line(data, acc) do
    raw_type = data["type"] || "null"
    {_normalized, known?} = JsonlParser.classify_type(raw_type)
    has_usage = get_in(data, ["message", "usage"]) != nil

    acc
    |> update_in([:types, raw_type], &((&1 || 0) + 1))
    |> update_in([:with_usage], &(&1 + if(has_usage, do: 1, else: 0)))
    |> maybe_record_unknown(raw_type, known?)
  end

  defp maybe_record_unknown(acc, _raw_type, true), do: acc

  defp maybe_record_unknown(acc, raw_type, false),
    do: update_in(acc, [:unknown_types], &[raw_type | &1])

  defp find_jsonl_path(session) do
    transcript_roots = Spotter.Transcripts.Config.read!().transcript_roots

    Enum.find_value(transcript_roots, fn root ->
      root
      |> Path.join("**")
      |> Path.join("#{session.session_id}.jsonl")
      |> Path.wildcard()
      |> List.first()
    end)
  end

  defp print_audit(path, jsonl_lines, parsed, db_messages, _format) do
    db_stats = compute_db_stats(db_messages)
    missing = jsonl_lines - db_stats.count
    pct = if jsonl_lines > 0, do: Float.round(missing / jsonl_lines * 100, 1), else: 0.0
    unknown_types = Enum.uniq(parsed.unknown_types)

    print_header(path, jsonl_lines, db_stats.count, missing, pct, parsed.parse_errors)
    print_jsonl_types(parsed.types)
    if db_messages, do: print_db_stats(db_stats)
    if unknown_types != [], do: print_unknown_types(unknown_types)
  end

  defp compute_db_stats(nil),
    do: %{count: 0, types: %{}, with_tokens: 0, with_model: 0, norm: %{}}

  defp compute_db_stats(messages) do
    %{
      count: length(messages),
      types: messages |> Enum.map(& &1.type) |> Enum.frequencies(),
      with_tokens: Enum.count(messages, & &1.input_tokens),
      with_model: Enum.count(messages, & &1.model),
      norm: messages |> Enum.map(& &1.normalization_status) |> Enum.frequencies()
    }
  end

  defp print_header(path, jsonl_lines, db_count, missing, pct, parse_errors) do
    missing_text = if missing > 0, do: "#{missing} (#{pct}%)", else: "0 ✓"

    Mix.shell().info("Session: #{Path.basename(path, ".jsonl")}")
    Mix.shell().info("  File: #{path}")
    Mix.shell().info("  JSONL lines:       #{jsonl_lines}")
    Mix.shell().info("  Imported messages: #{db_count}")
    Mix.shell().info("  MISSING:           #{missing_text}")
    Mix.shell().info("  Parse errors:      #{parse_errors}")
  end

  defp print_jsonl_types(types) do
    Mix.shell().info("")
    Mix.shell().info("  JSONL types:")

    types
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.each(fn {type, count} ->
      Mix.shell().info("    #{String.pad_trailing(type, 25)} #{count}")
    end)
  end

  defp print_db_stats(stats) do
    Mix.shell().info("")
    Mix.shell().info("  DB types:")

    stats.types
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.each(fn {type, count} ->
      Mix.shell().info("    #{String.pad_trailing(to_string(type), 25)} #{count}")
    end)

    Mix.shell().info("")
    Mix.shell().info("  Token data:        #{stats.with_tokens} messages with usage")
    Mix.shell().info("  Model data:        #{stats.with_model} messages with model")
    Mix.shell().info("  Normalization:     #{inspect(stats.norm)}")
  end

  defp print_unknown_types(types) do
    Mix.shell().info("")
    Mix.shell().info("  ⚠ Unknown types:  #{inspect(types)}")
  end

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.audit [options]

    Compare raw JSONL against imported data to detect import gaps.

    Options:
      --file <path>         Audit a specific JSONL file
      --session <id>        Audit by session ID (looks up JSONL file from transcript roots)
      --project <id>        Audit recent sessions in a project
      --limit <n>           Max sessions to audit (default: 20, with --project)
      --format <fmt>        Output format: table (default) or json
    """)
  end
end
