defmodule Spotter.ImageStore do
  @moduledoc false

  require OpenTelemetry.Tracer, as: Tracer

  @callback store(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback fetch(String.t()) :: {:ok, binary()} | {:error, :not_found}
  @callback delete(String.t()) :: :ok | {:error, term()}

  def store(image_binary, annotation_id) do
    Tracer.with_span "spotter.image_store.store" do
      Tracer.set_attribute("image_store.annotation_id", annotation_id)
      Tracer.set_attribute("image_store.size_bytes", byte_size(image_binary))
      adapter().store(image_binary, annotation_id)
    end
  end

  def fetch(reference) do
    Tracer.with_span "spotter.image_store.fetch" do
      Tracer.set_attribute("image_store.reference", reference)
      adapter().fetch(reference)
    end
  end

  def delete(reference) do
    Tracer.with_span "spotter.image_store.delete" do
      Tracer.set_attribute("image_store.reference", reference)
      adapter().delete(reference)
    end
  end

  defp adapter do
    Application.get_env(:spotter, __MODULE__, [])
    |> Keyword.get(:adapter, Spotter.ImageStore.SqliteAdapter)
  end
end
