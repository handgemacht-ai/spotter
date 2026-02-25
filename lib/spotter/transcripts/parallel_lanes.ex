defmodule Spotter.Transcripts.ParallelLanes do
  @moduledoc "Cross-session lane extraction for team parallel transcript visualization."

  require OpenTelemetry.Tracer, as: Tracer
  require Ash.Query

  alias Spotter.Services.TranscriptRenderer
  alias Spotter.Transcripts.{ComputedLaneCache, Message, Team}

  # tool_use is embedded within :assistant content blocks, not stored as top-level rows.
  # thinking, progress, system, file_history_snapshot are non-renderable noise.
  @visible_types [:user, :assistant, :tool_result]

  @idle_threshold_seconds 60

  @spec compute(String.t()) :: {:ok, map()} | {:error, :not_found | term()}
  def compute(team_id) do
    Tracer.with_span "spotter.parallel_lanes.compute" do
      start_time = System.monotonic_time()
      Tracer.set_attribute("spotter.team_id", team_id)

      case Team |> Ash.Query.filter(id == ^team_id) |> Ash.read_one() do
        {:ok, nil} ->
          Tracer.set_status(:error, "not_found")

          :telemetry.execute(
            [:spotter, :parallel_lanes, :compute, :error],
            %{count: 1},
            %{team_id: team_id, reason: "not_found"}
          )

          {:error, :not_found}

        {:ok, team} ->
          team = Ash.load!(team, team_members: [:session])
          session_ids = Enum.map(team.team_members, & &1.session_id)

          messages_by_session =
            Message
            |> Ash.Query.filter(
              session_id in ^session_ids and
                is_sidechain == false and
                type in ^@visible_types
            )
            |> Ash.Query.sort(timestamp: :asc)
            |> Ash.read!()
            |> Enum.group_by(& &1.session_id)

          lanes =
            team.team_members
            |> Task.async_stream(
              fn member ->
                build_lane(member, Map.get(messages_by_session, member.session_id, []))
              end,
              ordered: true,
              max_concurrency: System.schedulers_online()
            )
            |> Enum.map(fn {:ok, lane} -> lane end)
            |> Enum.sort_by(& &1.started_at, &nil_safe_datetime_compare/2)

          timeline = compute_timeline(lanes)
          overlaps = overlap_regions(lanes)

          Tracer.set_attribute("spotter.lane_count", length(lanes))
          Tracer.set_attribute("spotter.overlap_count", length(overlaps))

          idle_period_count =
            lanes |> Enum.map(&length(Map.get(&1, :idle_periods, []))) |> Enum.sum()

          Tracer.set_attribute("spotter.idle_period_count", idle_period_count)

          Tracer.set_attribute(
            "spotter.message_count",
            lanes |> Enum.map(&length(&1.messages)) |> Enum.sum()
          )

          timeline_duration_ms =
            if timeline.earliest && timeline.latest do
              max(DateTime.diff(timeline.latest, timeline.earliest, :millisecond), 0)
            else
              0
            end

          Tracer.set_attribute("spotter.timeline_duration_ms", timeline_duration_ms)

          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:spotter, :parallel_lanes, :compute, :stop],
            %{duration: duration},
            %{team_id: team_id, lane_count: length(lanes)}
          )

          message_links = extract_message_links(lanes)
          received_link_targets = compute_received_link_targets(message_links, lanes)
          rows = align_rows(lanes)

          Tracer.set_attribute("spotter.message_link_count", length(message_links))
          Tracer.set_attribute("spotter.row_count", length(rows))

          {:ok,
           %{
             team: team,
             lanes: lanes,
             timeline: timeline,
             overlaps: overlaps,
             message_links: message_links,
             received_link_targets: received_link_targets,
             rows: rows
           }}

        {:error, error} ->
          Tracer.set_status(:error, inspect(error))

          :telemetry.execute(
            [:spotter, :parallel_lanes, :compute, :error],
            %{count: 1},
            %{team_id: team_id, reason: inspect(error)}
          )

          {:error, error}
      end
    end
  end

  @cache_version 1

  @doc """
  Compute lanes and persist the result in the database cache.

  Called by the `ComputeLanes` Oban worker after transcript sync.
  """
  @spec compute_and_cache(String.t()) :: {:ok, map()} | {:error, term()}
  def compute_and_cache(team_id) do
    Tracer.with_span "spotter.parallel_lanes.compute_and_cache" do
      Tracer.set_attribute("spotter.team_id", team_id)

      case compute(team_id) do
        {:ok, result} ->
          payload = :erlang.term_to_binary(serialize_result(result))

          Ash.create!(ComputedLaneCache, %{
            team_id: team_id,
            payload: payload,
            version: @cache_version,
            computed_at: DateTime.utc_now()
          })

          Tracer.set_attribute("spotter.cache_size_bytes", byte_size(payload))
          {:ok, result}

        error ->
          error
      end
    end
  end

  @doc """
  Load pre-computed lanes from the database cache.

  Returns `{:ok, result}` on cache hit, `{:miss, nil}` on cache miss or version mismatch.
  """
  @spec load_cached(String.t()) :: {:ok, map()} | {:miss, nil}
  def load_cached(team_id) do
    Tracer.with_span "spotter.parallel_lanes.load_cached" do
      Tracer.set_attribute("spotter.team_id", team_id)

      case ComputedLaneCache
           |> Ash.Query.filter(team_id == ^team_id and version == ^@cache_version)
           |> Ash.read_one() do
        {:ok, %ComputedLaneCache{payload: payload}} when is_binary(payload) ->
          result = payload |> :erlang.binary_to_term([:safe]) |> deserialize_result()
          Tracer.set_attribute("spotter.cache_hit", true)
          {:ok, result}

        _ ->
          Tracer.set_attribute("spotter.cache_hit", false)
          {:miss, nil}
      end
    end
  end

  # Convert the compute result into plain Elixir terms safe for term_to_binary.
  # Strips Ash structs; lanes component only needs maps with atom keys.
  defp serialize_result(result) do
    %{
      lanes: Enum.map(result.lanes, &serialize_lane/1),
      timeline: result.timeline,
      overlaps: result.overlaps,
      message_links: result.message_links,
      received_link_targets: result.received_link_targets,
      rows: Enum.map(result.rows, &serialize_row/1)
    }
  end

  defp serialize_lane(lane) do
    %{
      agent_name: lane.agent_name,
      session: %{id: lane.session.id, session_id: lane.session.session_id, cwd: lane.session.cwd},
      messages: Enum.map(lane.messages, &message_to_map/1),
      rendered_lines: lane.rendered_lines,
      idle_periods: lane.idle_periods,
      started_at: lane.started_at,
      ended_at: lane.ended_at
    }
  end

  defp serialize_row(%{timestamp: ts, cells: cells}) do
    serialized_cells =
      Map.new(cells, fn
        {agent_name, nil} -> {agent_name, nil}
        {agent_name, msg} -> {agent_name, message_to_map(msg)}
      end)

    %{timestamp: ts, cells: serialized_cells}
  end

  defp deserialize_result(data) do
    data
  end

  @doc "Compute time regions where two or more lanes overlap."
  @spec overlap_regions([map()]) :: [map()]
  def overlap_regions([]), do: []
  def overlap_regions([_]), do: []

  def overlap_regions(lanes) do
    valid_lanes = Enum.filter(lanes, &(&1.started_at && &1.ended_at))
    total_lanes = length(valid_lanes)

    if total_lanes < 2 do
      []
    else
      events =
        valid_lanes
        |> Enum.flat_map(fn lane ->
          [
            {:start, lane.started_at, lane.agent_name},
            {:stop, lane.ended_at, lane.agent_name}
          ]
        end)
        |> Enum.sort_by(fn {type, dt, _name} -> {dt, sort_key_for_type(type)} end)

      sweep(events, MapSet.new(), nil, [], total_lanes)
      |> Enum.reverse()
    end
  end

  # Process :stop before :start at same timestamp to avoid false zero-duration overlaps
  # at touching boundaries (lane A ends exactly when lane B starts).
  defp sort_key_for_type(:stop), do: 0
  defp sort_key_for_type(:start), do: 1

  defp sweep([], _active, _region_start, regions, _total_lanes) do
    # Stop events should have closed any open region; don't emit zero-duration leftovers
    regions
  end

  defp sweep([{type, dt, agent} | rest], active, region_start, regions, total_lanes) do
    new_active = update_active(type, active, agent)

    {new_start, new_regions} =
      handle_transition(active, new_active, region_start, dt, regions, total_lanes)

    sweep(rest, new_active, new_start, new_regions, total_lanes)
  end

  defp update_active(:start, active, agent), do: MapSet.put(active, agent)
  defp update_active(:stop, active, agent), do: MapSet.delete(active, agent)

  defp handle_transition(active, new_active, region_start, dt, regions, total_lanes) do
    prev_count = MapSet.size(active)
    new_count = MapSet.size(new_active)

    cond do
      prev_count < 2 and new_count >= 2 ->
        {dt, regions}

      prev_count >= 2 and new_count < 2 ->
        {nil, [build_region(region_start, dt, active, total_lanes) | regions]}

      prev_count >= 2 and new_count >= 2 and prev_count != new_count ->
        {dt, [build_region(region_start, dt, active, total_lanes) | regions]}

      true ->
        {region_start, regions}
    end
  end

  defp build_region(start_dt, end_dt, active_agents, total_lanes) do
    agents = MapSet.to_list(active_agents) |> Enum.sort()
    agent_count = length(agents)

    %{
      start: start_dt,
      end: end_dt,
      agents: agents,
      agent_count: agent_count,
      type: if(agent_count >= total_lanes, do: :full, else: :partial)
    }
  end

  defp build_lane(team_member, messages) do
    session = team_member.session
    first = List.first(messages)
    last = List.last(messages)
    render_messages = Enum.map(messages, &message_to_map/1)

    rendered_lines =
      Tracer.with_span "spotter.lanes.render_lane",
                       %{
                         attributes: %{
                           "session_id" => session.id,
                           "lane_agent_name" => team_member.agent_name,
                           "message_count" => length(messages)
                         }
                       } do
        opts = if session.cwd, do: [session_cwd: session.cwd], else: []
        TranscriptRenderer.render(render_messages, opts)
      end

    idle_periods = compute_idle_periods(messages)

    %{
      agent_name: team_member.agent_name,
      session: session,
      team_member: team_member,
      messages: messages,
      rendered_lines: rendered_lines,
      idle_periods: idle_periods,
      started_at: truncate_dt(session.started_at) || (first && first.timestamp),
      ended_at: truncate_dt(session.ended_at) || (last && last.timestamp)
    }
  end

  defp compute_idle_periods(messages) when length(messages) < 2, do: []

  defp compute_idle_periods(messages) do
    messages
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(&maybe_idle_gap/1)
  end

  defp maybe_idle_gap([%{timestamp: ts_a}, %{timestamp: ts_b}])
       when not is_nil(ts_a) and not is_nil(ts_b) do
    gap = DateTime.diff(ts_b, ts_a, :second)

    if gap > @idle_threshold_seconds,
      do: [%{start: ts_a, end: ts_b, duration_seconds: gap}],
      else: []
  end

  defp maybe_idle_gap(_pair), do: []

  defp extract_message_links(lanes) do
    lanes
    |> Enum.flat_map(fn lane ->
      lane.messages
      |> Enum.flat_map(fn msg ->
        extract_send_messages(msg, lane.agent_name)
      end)
    end)
    |> Enum.sort_by(& &1.timestamp, DateTime)
  end

  defp extract_send_messages(%{type: :assistant, content: content} = msg, sender_name)
       when is_map(content) do
    blocks = Map.get(content, "blocks", [])

    blocks
    |> Enum.filter(fn block ->
      Map.get(block, "type") == "tool_use" && Map.get(block, "name") == "SendMessage"
    end)
    |> Enum.map(fn block ->
      input = Map.get(block, "input", %{})

      %{
        sender: sender_name,
        recipient: Map.get(input, "recipient", "unknown"),
        timestamp: msg.timestamp,
        sender_message_uuid: msg.uuid,
        content_preview: String.slice(Map.get(input, "content", ""), 0, 80)
      }
    end)
  end

  defp extract_send_messages(_msg, _sender_name), do: []

  # Pre-compute which message UUID in each recipient lane should show each received badge.
  # For each link, find the first message in the recipient's lane at or after the link timestamp.
  defp compute_received_link_targets(links, lanes) when is_list(links) and is_list(lanes) do
    lane_messages =
      Map.new(lanes, fn lane ->
        {lane.agent_name, Enum.sort_by(lane.messages, & &1.timestamp, DateTime)}
      end)

    Enum.reduce(links, %{}, fn link, acc ->
      messages = Map.get(lane_messages, link.recipient, [])
      target_uuid = first_msg_uuid_at_or_after(messages, link.timestamp)

      if target_uuid do
        Map.put(acc, link_key(link), target_uuid)
      else
        acc
      end
    end)
  end

  defp compute_received_link_targets(_, _), do: %{}

  defp first_msg_uuid_at_or_after(messages, timestamp) do
    Enum.find_value(messages, fn msg ->
      if msg.timestamp && DateTime.compare(msg.timestamp, timestamp) != :lt, do: msg.uuid
    end)
  end

  defp link_key(link) do
    {link.sender, link.recipient, link.sender_message_uuid}
  end

  defp align_rows(lanes) do
    all_agent_names = Enum.map(lanes, & &1.agent_name)

    # Build {timestamp, agent_name, message} tuples from all lanes
    all_entries =
      lanes
      |> Enum.flat_map(fn lane ->
        Enum.map(lane.messages, fn msg ->
          {msg.timestamp, lane.agent_name, msg}
        end)
      end)
      |> Enum.sort_by(&elem(&1, 0), DateTime)

    # Group entries within 1 second into the same row
    all_entries
    |> Enum.reduce([], &merge_into_rows/2)
    |> Enum.reverse()
    |> Enum.map(fn row ->
      # Fill nil for agents without a message in this row
      filled_cells =
        Map.new(all_agent_names, fn name ->
          {name, Map.get(row.cells, name)}
        end)

      %{row | cells: filled_cells}
    end)
  end

  defp merge_into_rows({ts, agent, msg}, [%{timestamp: row_ts, cells: cells} = row | rest])
       when not is_nil(row_ts) and not is_nil(ts) do
    if abs(DateTime.diff(ts, row_ts, :millisecond)) <= 1000 && !Map.has_key?(cells, agent) do
      [%{row | cells: Map.put(cells, agent, msg)} | rest]
    else
      [%{timestamp: ts, cells: %{agent => msg}}, row | rest]
    end
  end

  defp merge_into_rows({ts, agent, msg}, rows) do
    [%{timestamp: ts, cells: %{agent => msg}} | rows]
  end

  defp message_to_map(%Message{} = msg) do
    %{
      id: msg.id,
      uuid: msg.uuid,
      type: msg.type,
      role: msg.role,
      content: msg.content,
      raw_payload: msg.raw_payload,
      timestamp: msg.timestamp,
      agent_id: msg.agent_id,
      content_preview: content_preview(msg.content),
      tools: extract_tools(msg.content)
    }
  end

  defp content_preview(nil), do: ""

  defp content_preview(content) when is_map(content) do
    text = extract_preview_text(content)
    if String.length(text) > 80, do: String.slice(text, 0, 80) <> "...", else: text
  end

  defp content_preview(content) when is_binary(content) do
    if String.length(content) > 80, do: String.slice(content, 0, 80) <> "...", else: content
  end

  defp content_preview(_), do: ""

  defp extract_preview_text(content) when is_map(content) do
    blocks = Map.get(content, "blocks", [])

    blocks
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
    |> case do
      "" -> Map.get(content, "text", "")
      text -> text
    end
  end

  defp extract_tools(nil), do: []

  defp extract_tools(content) when is_map(content) do
    blocks = Map.get(content, "blocks", [])

    tools =
      blocks
      |> Enum.flat_map(fn
        %{"type" => "tool_use", "name" => name} -> [name]
        _ -> []
      end)
      |> Enum.uniq()

    if length(tools) > 3, do: ["#{length(tools)} tools"], else: tools
  end

  defp extract_tools(_), do: []

  defp truncate_dt(nil), do: nil
  defp truncate_dt(dt), do: DateTime.truncate(dt, :millisecond)

  defp nil_safe_datetime_compare(nil, nil), do: true
  defp nil_safe_datetime_compare(nil, _), do: false
  defp nil_safe_datetime_compare(_, nil), do: true
  defp nil_safe_datetime_compare(a, b), do: DateTime.compare(a, b) != :gt

  defp compute_timeline([]), do: %{earliest: nil, latest: nil}

  defp compute_timeline(lanes) do
    starts = lanes |> Enum.map(& &1.started_at) |> Enum.reject(&is_nil/1)
    ends = lanes |> Enum.map(& &1.ended_at) |> Enum.reject(&is_nil/1)

    %{
      earliest: if(starts != [], do: Enum.min(starts, DateTime) |> DateTime.truncate(:second)),
      latest: if(ends != [], do: Enum.max(ends, DateTime) |> DateTime.truncate(:second))
    }
  end
end
