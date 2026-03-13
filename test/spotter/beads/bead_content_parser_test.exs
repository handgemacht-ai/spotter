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
