defmodule Spotter.Services.PromptPatternAgentTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.PromptPatternAgent

  describe "parse_response/2" do
    test "parses valid JSON with patterns" do
      raw =
        ~s|{"patterns":[{"needle":"fix the bug","label":"Bug fix requests","confidence":0.85,"examples":["fix the bug in login","please fix the bug"]}]}|

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert length(patterns) == 1

      [pattern] = patterns
      assert pattern["needle"] == "fix the bug"
      assert pattern["label"] == "Bug fix requests"
      assert pattern["confidence"] == 0.85
      assert length(pattern["examples"]) == 2
    end

    test "strips markdown fences and still parses" do
      raw = """
      ```json
      {"patterns":[{"needle":"add tests for","label":"Test requests","confidence":0.9,"examples":["add tests for auth"]}]}
      ```
      """

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert length(patterns) == 1
      assert hd(patterns)["needle"] == "add tests for"
    end

    test "rejects needles too short (< 6 chars)" do
      raw =
        ~s|{"patterns":[{"needle":"fix","label":"Short","confidence":0.5,"examples":["fix it"]}]}|

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert patterns == []
    end

    test "rejects needles too long (> 80 chars)" do
      long_needle = String.duplicate("a", 81)

      raw =
        Jason.encode!(%{
          "patterns" => [
            %{
              "needle" => long_needle,
              "label" => "Too long",
              "confidence" => 0.5,
              "examples" => ["example"]
            }
          ]
        })

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert patterns == []
    end

    test "rejects empty labels" do
      raw =
        ~s|{"patterns":[{"needle":"fix the bug","label":"","confidence":0.5,"examples":["example"]}]}|

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert patterns == []
    end

    test "rejects labels over 60 chars" do
      long_label = String.duplicate("x", 61)

      raw =
        Jason.encode!(%{
          "patterns" => [
            %{
              "needle" => "fix the bug",
              "label" => long_label,
              "confidence" => 0.5,
              "examples" => ["example"]
            }
          ]
        })

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert patterns == []
    end

    test "rejects invalid shapes (missing required fields)" do
      raw = ~s|{"patterns":[{"needle":"fix the bug"}]}|

      assert {:ok, patterns} = PromptPatternAgent.parse_response(raw)
      assert patterns == []
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_parse_error, _}} = PromptPatternAgent.parse_response("not json")
    end

    test "returns error when top-level shape is wrong" do
      raw = ~s|{"results":[]}|
      assert {:error, :invalid_response_shape} = PromptPatternAgent.parse_response(raw)
    end

    test "respects patterns_max limit" do
      patterns =
        for i <- 1..5 do
          %{
            "needle" => "pattern number #{i}",
            "label" => "Pattern #{i}",
            "confidence" => 0.8,
            "examples" => ["example"]
          }
        end

      raw = Jason.encode!(%{"patterns" => patterns})

      assert {:ok, result} = PromptPatternAgent.parse_response(raw, 3)
      assert length(result) == 3
    end

    test "caps examples at 5" do
      examples = for i <- 1..10, do: "example #{i}"

      raw =
        Jason.encode!(%{
          "patterns" => [
            %{
              "needle" => "fix the bug",
              "label" => "Bug fixes",
              "confidence" => 0.9,
              "examples" => examples
            }
          ]
        })

      assert {:ok, [pattern]} = PromptPatternAgent.parse_response(raw)
      assert length(pattern["examples"]) == 5
    end

    test "clamps confidence to 0..1 range" do
      raw =
        Jason.encode!(%{
          "patterns" => [
            %{
              "needle" => "fix the bug",
              "label" => "Bug fixes",
              "confidence" => 1.5,
              "examples" => ["example"]
            }
          ]
        })

      assert {:ok, [pattern]} = PromptPatternAgent.parse_response(raw)
      assert pattern["confidence"] == 1.0
    end

    test "handles null confidence" do
      raw =
        Jason.encode!(%{
          "patterns" => [
            %{
              "needle" => "fix the bug",
              "label" => "Bug fixes",
              "confidence" => nil,
              "examples" => ["example"]
            }
          ]
        })

      assert {:ok, [pattern]} = PromptPatternAgent.parse_response(raw)
      assert pattern["confidence"] == nil
    end
  end
end
