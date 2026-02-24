defmodule Spotter.Transcripts.ParallelLanes do
  @moduledoc "Cross-session lane extraction for team parallel transcript visualization."

  require OpenTelemetry.Tracer, as: Tracer
  require Ash.Query

  alias Spotter.Services.TranscriptRenderer
  alias Spotter.Transcripts.{Message, Team}

  # tool_use is embedded within :assistant content blocks, not stored as top-level rows.
  # thinking, progress, system, file_history_snapshot are non-renderable noise.
  @visible_types [:user, :assistant, :tool_result]

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
            |> Enum.map(&build_lane(&1, Map.get(messages_by_session, &1.session_id, [])))
            |> Enum.sort_by(& &1.started_at, &nil_safe_datetime_compare/2)

          timeline = compute_timeline(lanes)
          overlaps = overlap_regions(lanes)

          Tracer.set_attribute("spotter.lane_count", length(lanes))
          Tracer.set_attribute("spotter.overlap_count", length(overlaps))

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

          {:ok, %{team: team, lanes: lanes, timeline: timeline, overlaps: overlaps}}

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

    %{
      agent_name: team_member.agent_name,
      session: session,
      team_member: team_member,
      messages: messages,
      rendered_lines: rendered_lines,
      started_at: truncate_dt(session.started_at) || (first && first.timestamp),
      ended_at: truncate_dt(session.ended_at) || (last && last.timestamp)
    }
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
      agent_id: msg.agent_id
    }
  end

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
