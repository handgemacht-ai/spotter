defmodule Spotter.Transcripts.Project.SessionCount do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def strict_loads?, do: false

  @impl true
  def load(_query, _opts, _context) do
    [:sessions]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      length(record.sessions)
    end)
  end
end
