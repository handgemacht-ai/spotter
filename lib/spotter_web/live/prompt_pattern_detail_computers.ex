# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule SpotterWeb.Live.PromptPatternDetailComputers do
  @moduledoc "AshComputer definitions for the prompt pattern detail page."
  use AshComputer

  computer :pattern_detail do
    input :pattern_id do
      initial nil
    end

    val :pattern do
      compute(fn
        %{pattern_id: nil} ->
          nil

        %{pattern_id: pattern_id} ->
          case Ash.get(Spotter.Transcripts.PromptPattern, pattern_id, load: [:run]) do
            {:ok, pattern} -> pattern
            _ -> nil
          end
      end)

      depends_on([:pattern_id])
    end

    val :matches do
      compute(fn
        %{pattern: nil} ->
          []

        %{pattern: pattern} ->
          require Ash.Query

          Spotter.Transcripts.PromptPatternMatch
          |> Ash.Query.filter(pattern_id == ^pattern.id)
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.Query.load([:message, session: [:project]])
          |> Ash.read!()
      end)

      depends_on([:pattern])
    end

    val :error_state do
      compute(fn
        %{pattern_id: nil} -> :not_found
        %{pattern: nil} -> :not_found
        _ -> nil
      end)

      depends_on([:pattern_id, :pattern])
    end
  end
end
