defmodule Spotter.Transcripts.Project.OpenReviewAnnotationCount do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def strict_loads?, do: false

  @impl true
  def load(_query, _opts, _context) do
    [:annotations]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.annotations do
        %Ash.NotLoaded{} -> 0
        annotations -> Enum.count(annotations, &(&1.state == :open and &1.purpose == :review))
      end
    end)
  end
end
