defmodule Spotter.Beads.BeadStructs do
  @moduledoc """
  Typed structs for bead data returned by Dolt queries.

  Provides `Epic`, `Task`, and `Dependency` structs with `from_row/1`
  and `from_rows/1` helpers for converting raw MyXQL result maps.
  """

  defmodule Epic do
    @moduledoc "An epic issue from the beads database."

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
    def from_row(row) when is_map(row), do: struct!(__MODULE__, Map.take(row, @fields))

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
    def from_row(row) when is_map(row), do: struct!(__MODULE__, Map.take(row, @fields))

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
