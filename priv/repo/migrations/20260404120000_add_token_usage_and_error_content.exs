defmodule Spotter.Repo.Migrations.AddTokenUsageAndErrorContent do
  @moduledoc """
  Adds token usage fields + model to messages, and error_content to tool_call_runs.
  """
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add(:input_tokens, :integer)
      add(:output_tokens, :integer)
      add(:cache_read_input_tokens, :integer)
      add(:cache_creation_input_tokens, :integer)
      add(:model, :string)
    end

    alter table(:tool_call_runs) do
      add(:error_content, :string)
    end
  end
end
