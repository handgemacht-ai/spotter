defmodule Spotter.Transcripts.RetroItem.Relationships.SessionThrough do
  @moduledoc """
  Manual relationship that loads sessions for retro items
  by joining through their retro submissions.
  """

  use Ash.Resource.ManualRelationship
  require Ash.Query

  @impl true
  def load(retro_items, _opts, %{query: query, domain: domain} = _context) do
    submission_ids =
      retro_items
      |> Enum.map(& &1.retro_submission_id)
      |> Enum.uniq()

    with {:ok, submissions} <-
           Spotter.Transcripts.RetroSubmission
           |> Ash.Query.filter(id in ^submission_ids)
           |> Ash.read(domain: domain),
         session_ids = submissions |> Enum.map(& &1.session_id) |> Enum.uniq(),
         {:ok, sessions_list} <-
           query
           |> Ash.Query.filter(id in ^session_ids)
           |> Ash.read(domain: domain) do
      sessions = Map.new(sessions_list, &{&1.id, &1})

      submission_to_session =
        Map.new(submissions, fn sub -> {sub.id, sessions[sub.session_id]} end)

      {:ok,
       Map.new(retro_items, fn item ->
         {item.id, submission_to_session[item.retro_submission_id]}
       end)}
    end
  end
end
