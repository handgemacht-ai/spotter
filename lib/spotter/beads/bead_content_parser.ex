defmodule Spotter.Beads.BeadContentParser do
  @moduledoc """
  Parses bead description markdown into structured data.

  Extracts `## Heading` sections, ```mermaid``` code blocks,
  and GIVEN/WHEN/THEN acceptance criteria tables.
  """

  @type acceptance_row :: %{given: String.t(), when: String.t(), then: String.t()}

  @doc "Extracts all ## heading names from a markdown description."
  @spec extract_headings(String.t() | nil) :: [String.t()]
  def extract_headings(nil), do: []

  def extract_headings(text) when is_binary(text) do
    ~r/^##\s+(.+)$/m
    |> Regex.scan(text)
    |> Enum.map(fn [_full, heading] -> String.trim(heading) end)
  end

  @doc "Splits a markdown description into a map of heading => body content."
  @spec extract_sections(String.t() | nil) :: %{String.t() => String.t()}
  def extract_sections(nil), do: %{}

  def extract_sections(text) when is_binary(text) do
    text |> extract_sections_ordered() |> Map.new()
  end

  @doc "Like `extract_sections/1` but returns an ordered list of `{heading, body}` tuples."
  @spec extract_sections_ordered(String.t() | nil) :: [{String.t(), String.t()}]
  def extract_sections_ordered(nil), do: []

  def extract_sections_ordered(text) when is_binary(text) do
    parts = Regex.split(~r/^##\s+/m, text, trim: true)
    headings = extract_headings(text)

    sections =
      if String.match?(text, ~r/\A\s*##\s+/m), do: parts, else: tl(parts)

    headings
    |> Enum.zip(sections)
    |> Enum.map(fn {heading, body} ->
      body_text =
        body
        |> String.replace(~r/\A.*\n?/, "")
        |> String.trim()

      {heading, body_text}
    end)
  end

  @doc "Extracts mermaid code block contents from a markdown description."
  @spec extract_mermaid_blocks(String.t() | nil) :: [String.t()]
  def extract_mermaid_blocks(nil), do: []

  def extract_mermaid_blocks(text) when is_binary(text) do
    ~r/```mermaid\r?\n(.*?)```/s
    |> Regex.scan(text)
    |> Enum.map(fn [_full, content] -> String.trim(content) end)
  end

  @doc "Parses GIVEN/WHEN/THEN markdown tables into structured rows."
  @spec extract_acceptance_table(String.t() | nil) :: [acceptance_row()]
  def extract_acceptance_table(nil), do: []

  def extract_acceptance_table(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> find_gwt_table_rows()
    |> Enum.map(&parse_gwt_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp find_gwt_table_rows(lines) do
    lines
    |> Enum.reduce({:seeking_header, []}, fn line, {state, acc} ->
      advance_gwt_state(state, line, acc)
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp advance_gwt_state(:seeking_header, line, acc) do
    if gwt_header?(line), do: {:skip_separator, acc}, else: {:seeking_header, acc}
  end

  defp advance_gwt_state(:skip_separator, line, acc) do
    if separator_row?(line), do: {:collecting, acc}, else: {:seeking_header, acc}
  end

  defp advance_gwt_state(:collecting, line, acc) do
    if table_row?(line), do: {:collecting, [line | acc]}, else: {:seeking_header, acc}
  end

  defp gwt_header?(line) do
    normalized = line |> String.downcase() |> String.replace(~r/\s+/, "")
    normalized =~ "|given|" and normalized =~ "|when|" and normalized =~ "|then|"
  end

  defp separator_row?(line), do: String.match?(line, ~r/^\s*\|[-| ]+\|\s*$/)

  defp table_row?(line), do: String.match?(line, ~r/^\s*\|.+\|\s*$/)

  @doc "Renders a markdown section body to HTML via Earmark."
  @spec render_section_body(String.t() | nil) :: String.t()
  def render_section_body(nil), do: ""
  def render_section_body(""), do: ""

  def render_section_body(body) when is_binary(body) do
    case Earmark.as_html(body, %Earmark.Options{code_class_prefix: "language-"}) do
      {:ok, html, _warnings} -> sanitize_html(html)
      {:error, _, _} -> Phoenix.HTML.html_escape(body) |> Phoenix.HTML.safe_to_string()
    end
  end

  @doc "Extracts classification key-value pairs from a Classification section."
  @spec extract_classification(String.t() | nil) :: [{String.t(), String.t() | [String.t()]}]
  def extract_classification(nil), do: []

  def extract_classification(text) when is_binary(text) do
    text
    |> find_section("Classification")
    |> parse_classification_body()
  end

  defp parse_classification_body(nil), do: []

  defp parse_classification_body(body) do
    body
    |> String.split("\n")
    |> Enum.filter(&String.match?(String.trim(&1), ~r/^- /))
    |> Enum.flat_map(fn line ->
      case parse_classification_line(line) do
        nil -> []
        pair -> [pair]
      end
    end)
  end

  @doc "Classifies a section heading into a content type atom."
  @spec classify_section(String.t()) :: :acceptance | :classification | :mermaid | :narrative
  def classify_section(heading) when is_binary(heading) do
    normalized = String.downcase(heading)

    cond do
      normalized =~ "acceptance" or normalized =~ "criteria" ->
        :acceptance

      normalized =~ "classification" ->
        :classification

      normalized =~ "diagram" or normalized =~ "data model" or normalized =~ "architecture" ->
        :mermaid

      true ->
        :narrative
    end
  end

  @dangerous_tags ~r/<\s*\/?\s*(script|style|iframe|object|embed|form)\b[^>]*>/i
  defp sanitize_html(html), do: Regex.replace(@dangerous_tags, html, "")

  defp find_section(text, heading) do
    text
    |> extract_sections()
    |> Map.get(heading)
  end

  defp parse_classification_line(line) do
    stripped =
      line
      |> String.trim()
      |> String.trim_leading("- ")
      |> String.replace(~r/\*\*(.+?)\*\*/, "\\1")

    case String.split(stripped, ": ", parts: 2) do
      [key, value] ->
        parsed_value =
          if key =~ ~r/boundaries/i,
            do: value |> String.split(",") |> Enum.map(&String.trim/1),
            else: value

        {String.trim(key), parsed_value}

      _ ->
        nil
    end
  end

  defp parse_gwt_row(line) do
    cells =
      line
      |> String.split("|")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case cells do
      [given, when_val, then_val | _] ->
        %{given: given, when: when_val, then: then_val}

      _ ->
        nil
    end
  end
end
