defmodule Spotter.Services.CommitHotspotAgentTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitHotspotAgent

  describe "parse_main_response/1" do
    test "parses valid main response" do
      json =
        ~s({"hotspots":[{"relative_path":"lib/foo.ex","symbol_name":"run/2","line_start":10,"line_end":25,"snippet":"def run do","reason":"complex logic","overall_score":78.5,"rubric":{"complexity":80,"change_risk":85}}]})

      assert {:ok, hotspots} = CommitHotspotAgent.parse_main_response(json)
      assert length(hotspots) == 1

      h = hd(hotspots)
      assert h.relative_path == "lib/foo.ex"
      assert h.symbol_name == "run/2"
      assert h.overall_score == 78.5
      assert h.rubric["complexity"] == 80.0
    end

    test "clamps scores to 0-100" do
      json =
        ~s({"hotspots":[{"relative_path":"a.ex","line_start":1,"line_end":5,"overall_score":150,"rubric":{"x":-10}}]})

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(json)
      assert h.overall_score == 100.0
      assert h.rubric["x"] == 0.0
    end

    test "returns error for missing hotspots key" do
      assert {:error, :invalid_main_response} =
               CommitHotspotAgent.parse_main_response(~s({"results":[]}))
    end

    test "accepts a decoded map" do
      map = %{"hotspots" => [%{"relative_path" => "a.ex", "line_start" => 1, "line_end" => 5}]}
      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(map)
      assert h.relative_path == "a.ex"
    end
  end

  describe "dedupe_hotspots/1" do
    test "keeps hotspot with highest score when duplicated" do
      hotspots = [
        %{
          relative_path: "a.ex",
          line_start: 1,
          line_end: 10,
          symbol_name: "foo",
          overall_score: 70.0
        },
        %{
          relative_path: "a.ex",
          line_start: 1,
          line_end: 10,
          symbol_name: "foo",
          overall_score: 85.0
        },
        %{
          relative_path: "b.ex",
          line_start: 1,
          line_end: 5,
          symbol_name: nil,
          overall_score: 60.0
        }
      ]

      result = CommitHotspotAgent.dedupe_hotspots(hotspots)
      assert length(result) == 2
      a_hotspot = Enum.find(result, &(&1.relative_path == "a.ex"))
      assert a_hotspot.overall_score == 85.0
    end

    test "returns empty list for empty input" do
      assert CommitHotspotAgent.dedupe_hotspots([]) == []
    end
  end

  describe "extract_tool_counts/1" do
    test "counts tool invocations from assistant messages" do
      tool_name = "mcp__spotter-hotspots__repo_read_file_at_commit"

      messages = [
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => tool_name, "id" => "1"},
              %{"type" => "tool_use", "name" => tool_name, "id" => "2"}
            ]
          }
        },
        %{type: "user", message: %{content: "result"}},
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => tool_name, "id" => "3"}
            ]
          }
        }
      ]

      counts = CommitHotspotAgent.extract_tool_counts(messages)
      assert counts[tool_name] == 3
    end

    test "ignores non-allowed tools" do
      messages = [
        %{
          type: "assistant",
          message: %{
            content: [
              %{"type" => "tool_use", "name" => "some_other_tool", "id" => "1"}
            ]
          }
        }
      ]

      assert CommitHotspotAgent.extract_tool_counts(messages) == %{}
    end

    test "returns empty map for empty messages" do
      assert CommitHotspotAgent.extract_tool_counts([]) == %{}
    end

    test "returns empty map for non-list input" do
      assert CommitHotspotAgent.extract_tool_counts(nil) == %{}
      assert CommitHotspotAgent.extract_tool_counts("bad") == %{}
    end

    test "handles unexpected message shapes without crashing" do
      messages = [
        %{type: "assistant", message: nil},
        %{type: "assistant", message: %{content: "string_not_list"}},
        %{type: "assistant"},
        nil,
        42
      ]

      assert CommitHotspotAgent.extract_tool_counts(messages) == %{}
    end
  end

  describe "run/2 input normalization" do
    test "returns error for missing required keys" do
      assert {:error, {:invalid_input, keys}} = CommitHotspotAgent.run(%{project_id: "p1"})
      assert :commit_hash in keys
    end

    test "returns error for empty string required keys" do
      assert {:error, {:invalid_input, _}} =
               CommitHotspotAgent.run(%{
                 project_id: "",
                 commit_hash: "abc",
                 commit_subject: "s",
                 diff_stats: %{},
                 patch_files: [],
                 git_cwd: "/tmp"
               })
    end

    test "string-key input passes normalization" do
      alias Spotter.Observability.AgentRunInput

      input = %{
        "project_id" => "p1",
        "commit_hash" => String.duplicate("a", 40),
        "commit_subject" => "test",
        "diff_stats" => %{},
        "patch_files" => [],
        "git_cwd" => "/nonexistent"
      }

      required = ~w(project_id commit_hash commit_subject diff_stats patch_files git_cwd)a
      assert {:ok, normalized} = AgentRunInput.normalize(input, required, [:run_id])
      assert normalized.project_id == "p1"
      assert normalized.commit_hash == String.duplicate("a", 40)
    end
  end

  describe "parse_main_response/1 shape hardening" do
    test "non-map hotspot items are filtered out" do
      map = %{
        "hotspots" => [
          %{"relative_path" => "a.ex", "line_start" => 1, "line_end" => 5},
          "not a map",
          nil,
          42
        ]
      }

      assert {:ok, hotspots} = CommitHotspotAgent.parse_main_response(map)
      assert length(hotspots) == 1
      assert hd(hotspots).relative_path == "a.ex"
    end

    test "hotspots with missing fields get defaults" do
      map = %{"hotspots" => [%{}]}
      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(map)
      assert h.relative_path == ""
      assert h.line_start == 0
      assert h.overall_score == 0.0
      assert h.rubric == %{}
    end

    test "invalid JSON returns error" do
      assert {:error, {:json_parse_error, _}} =
               CommitHotspotAgent.parse_main_response("not json {")
    end
  end

  # -- Scoring V2 --

  defp make_hotspot(overrides \\ %{}) do
    Map.merge(
      %{
        relative_path: "lib/foo.ex",
        symbol_name: "process",
        line_start: 10,
        line_end: 25,
        snippet: "def process(x), do: x",
        reason: "complex logic",
        overall_score: 50.0,
        llm_adjustment: 5.0,
        rubric: %{"complexity" => 80.0}
      },
      overrides
    )
  end

  defp make_metrics(overrides \\ %{}) do
    Map.merge(
      %{
        relative_path: "lib/foo.ex",
        line_start: 10,
        line_end: 25,
        symbol_name: "process",
        metrics: %{
          complexity_score: 60.0,
          change_churn_score: 40.0,
          blast_radius_score: 30.0,
          test_exposure_score: 70.0,
          fan_in_estimate: 3,
          module_spread_estimate: 2,
          blast_radius_confidence: "high"
        }
      },
      overrides
    )
  end

  describe "apply_scoring_v2/2" do
    test "computes weighted base_score + llm_adjustment" do
      hotspot = make_hotspot(%{llm_adjustment: 5.0})
      metrics = make_metrics()

      {[scored], v2_meta} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      # base = 0.30*60 + 0.25*40 + 0.30*30 + 0.15*70 = 18+10+9+10.5 = 47.5
      # final = 47.5 + 5.0 = 52.5
      assert scored.overall_score == 52.5
      assert v2_meta.scoring_version == "hotspot_v2"
    end

    test "clamps final score to 0..100" do
      hotspot = make_hotspot(%{llm_adjustment: 10.0})

      metrics =
        make_metrics(%{
          metrics: %{
            complexity_score: 100.0,
            change_churn_score: 100.0,
            blast_radius_score: 100.0,
            test_exposure_score: 100.0,
            fan_in_estimate: 10,
            module_spread_estimate: 5,
            blast_radius_confidence: "high"
          }
        })

      {[scored], _} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      assert scored.overall_score == 100.0
    end

    test "includes deterministic_metrics and base_score in output" do
      hotspot = make_hotspot()
      metrics = make_metrics()

      {[scored], _} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      assert is_map(scored.deterministic_metrics)
      assert is_float(scored.base_score)
    end

    test "hotspot without matching metrics keeps original score" do
      hotspot = make_hotspot(%{relative_path: "lib/unmatched.ex"})
      metrics = make_metrics()

      {[scored], _} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      assert scored.overall_score == 50.0
    end

    test "matches overlapping line ranges" do
      hotspot = make_hotspot(%{line_start: 12, line_end: 20})
      metrics = make_metrics(%{line_start: 10, line_end: 25})

      {[scored], _} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      # Should have found the overlapping match and applied scoring
      assert scored.overall_score != 50.0
      assert Map.has_key?(scored, :deterministic_metrics)
    end
  end

  describe "enforce_snippet_constraints/1" do
    test "rejects candidates with span > 80 lines" do
      oversized = make_hotspot(%{line_start: 1, line_end: 100})
      normal = make_hotspot(%{line_start: 10, line_end: 25})

      {kept, rejected_count} = CommitHotspotAgent.enforce_snippet_constraints([oversized, normal])

      assert length(kept) == 1
      assert hd(kept).line_start == 10
      assert rejected_count == 1
    end

    test "rejects whole-file ranges when file > 120 LOC" do
      whole_file = make_hotspot(%{line_start: 1, line_end: 200})
      normal = make_hotspot(%{line_start: 10, line_end: 25})

      {kept, rejected_count} =
        CommitHotspotAgent.enforce_snippet_constraints([whole_file, normal])

      assert length(kept) == 1
      assert rejected_count == 1
    end

    test "allows whole-file ranges for small files (<= 120 LOC)" do
      small_file = make_hotspot(%{line_start: 1, line_end: 50})

      {kept, rejected_count} = CommitHotspotAgent.enforce_snippet_constraints([small_file])

      assert length(kept) == 1
      assert rejected_count == 0
    end

    test "truncates snippet to 12 lines" do
      long_snippet = Enum.map_join(1..20, "\n", &"line #{&1}")
      hotspot = make_hotspot(%{snippet: long_snippet})

      {[trimmed], _} = CommitHotspotAgent.enforce_snippet_constraints([hotspot])

      lines = String.split(trimmed.snippet, "\n")
      assert length(lines) == 12
    end
  end

  describe "compute_base_score/1" do
    test "weighted formula: 0.30*complexity + 0.25*churn + 0.30*blast + 0.15*test" do
      metrics = %{
        complexity_score: 60.0,
        change_churn_score: 40.0,
        blast_radius_score: 30.0,
        test_exposure_score: 70.0
      }

      score = CommitHotspotAgent.compute_base_score(metrics)

      expected = 0.30 * 60 + 0.25 * 40 + 0.30 * 30 + 0.15 * 70
      assert_in_delta score, expected, 0.01
    end

    test "returns 0 for empty metrics" do
      assert CommitHotspotAgent.compute_base_score(%{}) == 0.0
    end
  end

  describe "parse_main_response/1 with llm_adjustment" do
    test "parses llm_adjustment field" do
      json =
        ~s({"hotspots":[{"relative_path":"lib/foo.ex","line_start":1,"line_end":5,"snippet":"x","reason":"y","overall_score":50,"llm_adjustment":7.5,"rubric":{"complexity":80}}]})

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(json)
      assert h.llm_adjustment == 7.5
    end

    test "clamps llm_adjustment to [-10, 10]" do
      json =
        ~s({"hotspots":[{"relative_path":"a.ex","line_start":1,"line_end":5,"snippet":"x","reason":"y","overall_score":50,"llm_adjustment":25,"rubric":{}}]})

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(json)
      assert h.llm_adjustment == 10.0
    end

    test "defaults llm_adjustment to 0 when missing" do
      map = %{
        "hotspots" => [
          %{"relative_path" => "a.ex", "line_start" => 1, "line_end" => 5}
        ]
      }

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(map)
      assert h.llm_adjustment == 0.0
    end
  end

  # -- Regression: ranking behavior --

  describe "ranking regression" do
    test "candidate A (high complexity + blast) ranks above B (high churn + low blast)" do
      # A: complexity=80, churn=30, blast=70, test=50
      # base_A = 0.30*80 + 0.25*30 + 0.30*70 + 0.15*50 = 24+7.5+21+7.5 = 60.0
      metrics_a = %{
        complexity_score: 80.0,
        change_churn_score: 30.0,
        blast_radius_score: 70.0,
        test_exposure_score: 50.0,
        fan_in_estimate: 5,
        module_spread_estimate: 3,
        blast_radius_confidence: "high"
      }

      # B: complexity=20, churn=90, blast=10, test=50
      # base_B = 0.30*20 + 0.25*90 + 0.30*10 + 0.15*50 = 6+22.5+3+7.5 = 39.0
      metrics_b = %{
        complexity_score: 20.0,
        change_churn_score: 90.0,
        blast_radius_score: 10.0,
        test_exposure_score: 50.0,
        fan_in_estimate: 1,
        module_spread_estimate: 1,
        blast_radius_confidence: "medium"
      }

      hotspot_a =
        make_hotspot(%{
          relative_path: "lib/a.ex",
          line_start: 10,
          line_end: 25,
          llm_adjustment: 0.0
        })

      hotspot_b =
        make_hotspot(%{
          relative_path: "lib/b.ex",
          line_start: 5,
          line_end: 20,
          llm_adjustment: 0.0
        })

      candidate_a =
        make_metrics(%{
          relative_path: "lib/a.ex",
          line_start: 10,
          line_end: 25,
          metrics: metrics_a
        })

      candidate_b =
        make_metrics(%{
          relative_path: "lib/b.ex",
          line_start: 5,
          line_end: 20,
          metrics: metrics_b
        })

      {scored, _meta} =
        CommitHotspotAgent.apply_scoring_v2([hotspot_a, hotspot_b], [candidate_a, candidate_b])

      score_a = Enum.find(scored, &(&1.relative_path == "lib/a.ex")).overall_score
      score_b = Enum.find(scored, &(&1.relative_path == "lib/b.ex")).overall_score

      assert score_a > score_b,
             "Expected A (#{score_a}) to rank above B (#{score_b})"
    end

    test "llm_adjustment can change relative ranking within bounds" do
      metrics = %{
        complexity_score: 50.0,
        change_churn_score: 50.0,
        blast_radius_score: 50.0,
        test_exposure_score: 50.0,
        fan_in_estimate: 3,
        module_spread_estimate: 2,
        blast_radius_confidence: "high"
      }

      # Same deterministic scores, but different LLM adjustments
      hotspot_a =
        make_hotspot(%{
          relative_path: "lib/a.ex",
          line_start: 1,
          line_end: 20,
          llm_adjustment: -10.0
        })

      hotspot_b =
        make_hotspot(%{
          relative_path: "lib/b.ex",
          line_start: 1,
          line_end: 20,
          llm_adjustment: 10.0
        })

      candidate_a =
        make_metrics(%{relative_path: "lib/a.ex", line_start: 1, line_end: 20, metrics: metrics})

      candidate_b =
        make_metrics(%{relative_path: "lib/b.ex", line_start: 1, line_end: 20, metrics: metrics})

      {scored, _} =
        CommitHotspotAgent.apply_scoring_v2([hotspot_a, hotspot_b], [candidate_a, candidate_b])

      score_a = Enum.find(scored, &(&1.relative_path == "lib/a.ex")).overall_score
      score_b = Enum.find(scored, &(&1.relative_path == "lib/b.ex")).overall_score

      assert score_b > score_a
      assert score_b - score_a == 20.0
    end
  end

  # -- Regression: metadata contract --

  describe "metadata contract" do
    test "scored hotspot includes deterministic_metrics with all required keys" do
      hotspot = make_hotspot()
      metrics = make_metrics()

      {[scored], meta} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      assert meta.scoring_version == "hotspot_v2"
      assert is_map(scored.deterministic_metrics)

      required_keys = [
        :complexity_score,
        :change_churn_score,
        :blast_radius_score,
        :test_exposure_score,
        :fan_in_estimate,
        :module_spread_estimate,
        :blast_radius_confidence
      ]

      for key <- required_keys do
        assert Map.has_key?(scored.deterministic_metrics, key),
               "Missing key: #{key}"
      end
    end

    test "base_score is included as a float" do
      hotspot = make_hotspot()
      metrics = make_metrics()

      {[scored], _} = CommitHotspotAgent.apply_scoring_v2([hotspot], [metrics])

      assert is_float(scored.base_score)
      assert scored.base_score >= 0.0
      assert scored.base_score <= 100.0
    end
  end

  # -- Regression: backward compatibility --

  describe "backward compatibility" do
    test "legacy rubric fields still parse correctly" do
      json =
        ~s({"hotspots":[{"relative_path":"lib/old.ex","line_start":1,"line_end":5,"snippet":"x","reason":"y","overall_score":50,"llm_adjustment":0,"rubric":{"complexity":80,"duplication":30,"error_handling":40,"test_coverage":60,"change_risk":70}}]})

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(json)
      assert h.rubric["complexity"] == 80.0
      assert h.rubric["duplication"] == 30.0
      assert h.rubric["error_handling"] == 40.0
      assert h.rubric["test_coverage"] == 60.0
      assert h.rubric["change_risk"] == 70.0
    end

    test "hotspot without llm_adjustment still parses (defaults to 0)" do
      map = %{
        "hotspots" => [
          %{
            "relative_path" => "lib/old.ex",
            "line_start" => 1,
            "line_end" => 5,
            "snippet" => "x",
            "reason" => "y",
            "overall_score" => 50,
            "rubric" => %{"complexity" => 80}
          }
        ]
      }

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(map)
      assert h.llm_adjustment == 0.0
      assert h.overall_score == 50.0
      assert h.rubric["complexity"] == 80.0
    end

    test "dedupe still works with llm_adjustment field present" do
      hotspots = [
        make_hotspot(%{overall_score: 70.0, llm_adjustment: 5.0}),
        make_hotspot(%{overall_score: 85.0, llm_adjustment: -2.0}),
        make_hotspot(%{relative_path: "lib/other.ex", overall_score: 60.0})
      ]

      result = CommitHotspotAgent.dedupe_hotspots(hotspots)
      assert length(result) == 2

      foo_hotspot = Enum.find(result, &(&1.relative_path == "lib/foo.ex"))
      assert foo_hotspot.overall_score == 85.0
    end
  end
end
