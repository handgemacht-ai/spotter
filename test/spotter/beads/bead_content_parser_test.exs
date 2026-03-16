defmodule Spotter.Beads.BeadContentParserTest do
  use ExUnit.Case, async: true

  alias Spotter.Beads.BeadContentParser

  @sample_description """
  ## Overview

  Plans Navigation feature for Spotter.

  ## Architecture

  ```mermaid
  graph TD
    A[Browser] --> B[LiveView]
    B --> C[BeadQueries]
    C --> D[Dolt DB]
  ```

  ## Acceptance Criteria

  | GIVEN | WHEN | THEN |
  |-------|------|------|
  | A project with epics | User opens plans page | Epic list is displayed |
  | An epic is selected | User clicks epic | Epic detail with children shown |

  ## Implementation Notes

  Use MyXQL for Dolt queries.
  """

  describe "extract_headings/1" do
    test "extracts all ## headings from description" do
      headings = BeadContentParser.extract_headings(@sample_description)

      assert headings == [
               "Overview",
               "Architecture",
               "Acceptance Criteria",
               "Implementation Notes"
             ]
    end

    test "returns empty list for nil description" do
      assert [] == BeadContentParser.extract_headings(nil)
    end

    test "returns empty list for description without headings" do
      assert [] == BeadContentParser.extract_headings("Just plain text with no headings.")
    end

    test "handles mixed heading levels" do
      content = """
      # Top Level
      ## Second Level
      ### Third Level
      ## Another Second
      """

      headings = BeadContentParser.extract_headings(content)

      assert "Second Level" in headings
      assert "Another Second" in headings
    end
  end

  describe "extract_sections/1" do
    test "splits description into sections by ## headings" do
      sections = BeadContentParser.extract_sections(@sample_description)

      assert is_map(sections)
      assert Map.has_key?(sections, "Overview")
      assert Map.has_key?(sections, "Architecture")
      assert Map.has_key?(sections, "Acceptance Criteria")
      assert Map.has_key?(sections, "Implementation Notes")
    end

    test "section content does not include the heading itself" do
      sections = BeadContentParser.extract_sections(@sample_description)

      overview = Map.get(sections, "Overview")
      refute overview =~ "## Overview"
      assert overview =~ "Plans Navigation feature"
    end

    test "returns empty map for nil" do
      assert %{} == BeadContentParser.extract_sections(nil)
    end
  end

  describe "extract_mermaid_blocks/1" do
    test "extracts mermaid code blocks from description" do
      blocks = BeadContentParser.extract_mermaid_blocks(@sample_description)

      assert length(blocks) == 1
      [block] = blocks
      assert block =~ "graph TD"
      assert block =~ "A[Browser]"
    end

    test "returns empty list when no mermaid blocks" do
      assert [] == BeadContentParser.extract_mermaid_blocks("No diagrams here.")
    end

    test "returns empty list for nil" do
      assert [] == BeadContentParser.extract_mermaid_blocks(nil)
    end

    test "extracts multiple mermaid blocks" do
      content = """
      ## Diagram 1

      ```mermaid
      graph LR
        A --> B
      ```

      ## Diagram 2

      ```mermaid
      sequenceDiagram
        Client->>Server: Request
      ```
      """

      blocks = BeadContentParser.extract_mermaid_blocks(content)
      assert length(blocks) == 2
    end
  end

  describe "render_section_body/1" do
    test "converts markdown to HTML with code_class_prefix" do
      markdown = """
      This is **bold** and `inline code`.

      ```elixir
      def hello, do: :world
      ```
      """

      html = BeadContentParser.render_section_body(markdown)

      assert html =~ "<strong>bold</strong>"
      assert html =~ "<code class=\"inline\">inline code</code>"
      assert html =~ ~r/<pre><code class="elixir language-elixir">/
      assert html =~ "def hello, do: :world"
    end

    test "returns escaped HTML on Earmark error" do
      # Simulate a case where the input is already not valid for rendering
      # but the function should not crash — it should return escaped HTML
      result = BeadContentParser.render_section_body("<script>alert('xss')</script>")

      refute result =~ "<script>"
      assert is_binary(result)
    end

    test "handles nil input" do
      assert "" == BeadContentParser.render_section_body(nil)
    end

    test "handles empty string" do
      assert "" == BeadContentParser.render_section_body("")
    end
  end

  describe "extract_classification/1" do
    test "parses key-value pairs from classification section" do
      text = """
      ## Classification

      - **Type**: Feature
      - **Priority**: High
      - **Complexity**: Medium
      """

      classification = BeadContentParser.extract_classification(text)

      assert {"Type", "Feature"} in classification
      assert {"Priority", "High"} in classification
      assert {"Complexity", "Medium"} in classification
    end

    test "parses list values for Affected Boundaries" do
      text = """
      ## Classification

      - **Affected Boundaries**: BeadContentParser, PlanDetailLive, PlanComponents
      """

      classification = BeadContentParser.extract_classification(text)

      {_key, value} =
        Enum.find(classification, fn {k, _v} -> k == "Affected Boundaries" end)

      assert is_list(value)
      assert "BeadContentParser" in value
      assert "PlanDetailLive" in value
      assert "PlanComponents" in value
    end

    test "returns empty list when no Classification section" do
      text = """
      ## Overview

      Just an overview, no classification here.
      """

      assert [] == BeadContentParser.extract_classification(text)
    end

    test "returns empty list for nil" do
      assert [] == BeadContentParser.extract_classification(nil)
    end
  end

  describe "classify_section/1" do
    test "returns :acceptance for acceptance criteria headings" do
      assert :acceptance == BeadContentParser.classify_section("Acceptance Criteria")
      assert :acceptance == BeadContentParser.classify_section("acceptance criteria")
    end

    test "returns :classification for classification headings" do
      assert :classification == BeadContentParser.classify_section("Classification")
      assert :classification == BeadContentParser.classify_section("classification")
    end

    test "returns :mermaid for architecture/diagram headings" do
      assert :mermaid == BeadContentParser.classify_section("Architecture")
      assert :mermaid == BeadContentParser.classify_section("Diagram")
    end

    test "returns :narrative for other headings" do
      assert :narrative == BeadContentParser.classify_section("Overview")
      assert :narrative == BeadContentParser.classify_section("Implementation Notes")
      assert :narrative == BeadContentParser.classify_section("Some Custom Section")
    end
  end

  describe "extract_acceptance_table/1" do
    test "parses GIVEN/WHEN/THEN table from description" do
      rows = BeadContentParser.extract_acceptance_table(@sample_description)

      assert length(rows) == 2

      [first, second] = rows
      assert first.given == "A project with epics"
      assert first.when == "User opens plans page"
      assert first.then == "Epic list is displayed"

      assert second.given == "An epic is selected"
      assert second.when == "User clicks epic"
      assert second.then == "Epic detail with children shown"
    end

    test "returns empty list when no GIVEN/WHEN/THEN table" do
      assert [] == BeadContentParser.extract_acceptance_table("No table here.")
    end

    test "returns empty list for nil" do
      assert [] == BeadContentParser.extract_acceptance_table(nil)
    end

    test "handles table with extra whitespace in cells" do
      content = """
      | GIVEN | WHEN | THEN |
      |-------|------|------|
      |  Spaced input  |  Spaced action  |  Spaced result  |
      """

      rows = BeadContentParser.extract_acceptance_table(content)
      assert length(rows) == 1
      [row] = rows
      assert row.given == "Spaced input"
      assert row.when == "Spaced action"
      assert row.then == "Spaced result"
    end
  end
end
