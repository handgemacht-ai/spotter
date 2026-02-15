defmodule Spotter.Transcripts.AnnotationFileRef do
  @moduledoc "Links an annotation to a specific file path and line range."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "annotation_file_refs"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:annotation_id, :project_id, :relative_path, :line_start, :line_end]
    end
  end

  validations do
    validate compare(:line_start, greater_than: 0)
    validate compare(:line_end, greater_than: 0)
    validate {Spotter.Transcripts.AnnotationFileRef.LineRangeValidation, []}
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :relative_path, :string, allow_nil?: false, public?: true
    attribute :line_start, :integer, allow_nil?: false, public?: true
    attribute :line_end, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :annotation, Spotter.Transcripts.Annotation do
      allow_nil? false
    end

    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_annotation_file_ref, [:annotation_id, :relative_path, :line_start, :line_end]
  end
end

defmodule Spotter.Transcripts.AnnotationFileRef.LineRangeValidation do
  @moduledoc false
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    line_start = Ash.Changeset.get_attribute(changeset, :line_start)
    line_end = Ash.Changeset.get_attribute(changeset, :line_end)

    if is_integer(line_start) and is_integer(line_end) and line_end < line_start do
      {:error, field: :line_end, message: "must be greater than or equal to line_start"}
    else
      :ok
    end
  end
end
