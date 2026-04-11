defmodule Spotter.Beads.BeadStructs do
  @moduledoc """
  Typed structs for bead data.

  Provides `Epic`, `Task`, and `Dependency` structs with `from_row/1`
  and `from_rows/1` helpers for converting raw result maps.
  """

  @doc false
  def structured_fields, do: [:design, :acceptance_criteria, :notes]

  @doc false
  def compose_description(row) do
    [
      row[:description],
      section("Design", row[:design]),
      section("Acceptance Criteria", row[:acceptance_criteria]),
      section("Notes", row[:notes])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp section(_heading, nil), do: nil
  defp section(_heading, ""), do: nil
  defp section(heading, body), do: "## #{heading}\n\n#{body}"

  defmodule Epic do
    @moduledoc "An epic issue from the beads database."

    @base_fields [
      :id,
      :title,
      :status,
      :priority,
      :issue_type,
      :description,
      :created_at,
      :updated_at,
      :closed_at,
      :assignee
    ]

    @all_fields @base_fields ++ [:task_count]

    @type t :: %__MODULE__{
            id: String.t(),
            title: String.t(),
            status: String.t(),
            priority: integer(),
            issue_type: String.t(),
            description: String.t() | nil,
            created_at: NaiveDateTime.t(),
            updated_at: NaiveDateTime.t() | nil,
            closed_at: NaiveDateTime.t() | nil,
            assignee: String.t() | nil,
            task_count: integer()
          }

    @enforce_keys [:id, :title, :status, :priority, :issue_type, :created_at]
    defstruct @base_fields ++ [task_count: 0]

    @spec from_row(map()) :: t()
    def from_row(row) when is_map(row) do
      row
      |> Map.put(:description, Spotter.Beads.BeadStructs.compose_description(row))
      |> Map.drop(Spotter.Beads.BeadStructs.structured_fields())
      |> Map.take(@all_fields)
      |> then(&struct!(__MODULE__, &1))
    end

    @spec from_rows([map()]) :: [t()]
    def from_rows(rows) when is_list(rows), do: Enum.map(rows, &from_row/1)
  end

  defmodule Task do
    @moduledoc "A task or child issue from the beads database."

    @fields [
      :id,
      :title,
      :status,
      :priority,
      :issue_type,
      :description,
      :created_at,
      :updated_at,
      :closed_at,
      :assignee
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            title: String.t(),
            status: String.t(),
            priority: integer(),
            issue_type: String.t(),
            description: String.t() | nil,
            created_at: NaiveDateTime.t(),
            updated_at: NaiveDateTime.t() | nil,
            closed_at: NaiveDateTime.t() | nil,
            assignee: String.t() | nil
          }

    @enforce_keys [:id, :title, :status, :priority, :issue_type, :created_at]
    defstruct @fields

    @spec from_row(map()) :: t()
    def from_row(row) when is_map(row) do
      row
      |> Map.put(:description, Spotter.Beads.BeadStructs.compose_description(row))
      |> Map.drop(Spotter.Beads.BeadStructs.structured_fields())
      |> Map.take(@fields)
      |> then(&struct!(__MODULE__, &1))
    end

    @spec from_rows([map()]) :: [t()]
    def from_rows(rows) when is_list(rows), do: Enum.map(rows, &from_row/1)
  end

  defmodule Dependency do
    @moduledoc "A dependency relationship between beads."

    @fields [:depends_on_id, :type, :created_at, :depends_on_title, :depends_on_status]

    @type t :: %__MODULE__{
            depends_on_id: String.t(),
            type: String.t(),
            created_at: NaiveDateTime.t(),
            depends_on_title: String.t() | nil,
            depends_on_status: String.t() | nil
          }

    @enforce_keys [:depends_on_id, :type, :created_at]
    defstruct @fields

    @spec from_row(map()) :: t()
    def from_row(row) when is_map(row), do: struct!(__MODULE__, Map.take(row, @fields))

    @spec from_rows([map()]) :: [t()]
    def from_rows(rows) when is_list(rows), do: Enum.map(rows, &from_row/1)
  end
end
