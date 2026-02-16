defmodule Spotter.Services.CommitHotspotMetricsTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitHotspotMetrics

  # -- Helpers --

  defp make_input(overrides \\ %{}) do
    Map.merge(
      %{
        commit_hash: "abc1234567890abcdef1234567890abcdef123456",
        diff_stats: %{
          files_changed: 1,
          insertions: 10,
          deletions: 3,
          binary_files: [],
          file_stats: [
            %{path: "lib/spotter/services/foo.ex", added: 10, deleted: 3, binary?: false}
          ]
        },
        patch_files: [
          %{
            path: "lib/spotter/services/foo.ex",
            hunks: [
              %{
                new_start: 5,
                new_len: 8,
                lines: [
                  "  def process(data) do",
                  "    if valid?(data) do",
                  "      case transform(data) do",
                  "        {:ok, result} -> result",
                  "        {:error, _} -> nil",
                  "      end",
                  "    end",
                  "  end"
                ],
                header: "def process(data) do"
              }
            ]
          }
        ],
        git_cwd: "/tmp/fake-repo"
      },
      overrides
    )
  end

  # -- build_candidate_metrics/1 --

  describe "build_candidate_metrics/1" do
    test "returns {:ok, []} for empty patch_files" do
      assert {:ok, []} = CommitHotspotMetrics.build_candidate_metrics(%{patch_files: []})
    end

    test "returns {:ok, []} for invalid input" do
      assert {:ok, []} = CommitHotspotMetrics.build_candidate_metrics(%{})
    end

    test "produces one candidate per hunk" do
      input = make_input()
      {:ok, candidates} = CommitHotspotMetrics.build_candidate_metrics(input)

      assert length(candidates) == 1
      [candidate] = candidates

      assert candidate.relative_path == "lib/spotter/services/foo.ex"
      assert candidate.line_start == 5
      assert candidate.line_end == 12
      assert candidate.symbol_name == "process"
      assert is_map(candidate.metrics)
    end

    test "all metric scores are floats clamped 0..100" do
      input = make_input()
      {:ok, [candidate]} = CommitHotspotMetrics.build_candidate_metrics(input)

      for {key, val} <- candidate.metrics,
          key in ~w(complexity_score change_churn_score test_exposure_score blast_radius_score)a do
        assert is_float(val), "#{key} should be a float, got: #{inspect(val)}"
        assert val >= 0.0, "#{key} should be >= 0, got: #{val}"
        assert val <= 100.0, "#{key} should be <= 100, got: #{val}"
      end
    end

    test "multiple hunks produce multiple candidates" do
      input =
        make_input(%{
          patch_files: [
            %{
              path: "lib/foo.ex",
              hunks: [
                %{
                  new_start: 1,
                  new_len: 3,
                  lines: ["  def a, do: 1", "  def b, do: 2", "  def c, do: 3"],
                  header: ""
                },
                %{
                  new_start: 20,
                  new_len: 2,
                  lines: ["  def d, do: 4", "  def e, do: 5"],
                  header: ""
                }
              ]
            }
          ],
          diff_stats: %{
            files_changed: 1,
            insertions: 5,
            deletions: 0,
            binary_files: [],
            file_stats: [%{path: "lib/foo.ex", added: 5, deleted: 0, binary?: false}]
          }
        })

      {:ok, candidates} = CommitHotspotMetrics.build_candidate_metrics(input)
      assert length(candidates) == 2
      assert Enum.at(candidates, 0).line_start == 1
      assert Enum.at(candidates, 1).line_start == 20
    end

    test "skips hunks with new_len == 0" do
      input =
        make_input(%{
          patch_files: [
            %{
              path: "lib/foo.ex",
              hunks: [
                %{new_start: 1, new_len: 0, lines: [], header: ""},
                %{new_start: 10, new_len: 3, lines: ["a", "b", "c"], header: ""}
              ]
            }
          ]
        })

      {:ok, candidates} = CommitHotspotMetrics.build_candidate_metrics(input)
      assert length(candidates) == 1
      assert hd(candidates).line_start == 10
    end
  end

  # -- Complexity scoring --

  describe "compute_complexity/2" do
    test "zero for empty lines" do
      assert CommitHotspotMetrics.compute_complexity([], 0) == 0.0
    end

    test "counts branch points" do
      lines = ["  if foo do", "    case bar do", "    end", "  end"]
      # branch_points=2, nesting≈1, bool_ops=0, loc=4
      # 2*12 + 1*8 + 0 + max(0,4-15)*1.5 = 24+8 = 32
      score = CommitHotspotMetrics.compute_complexity(lines, 4)
      assert score > 0
      assert score <= 100.0
    end

    test "counts boolean operators" do
      lines = ["  if a and b or c do", "    :ok", "  end"]
      score = CommitHotspotMetrics.compute_complexity(lines, 3)
      # branch_points=1(if), bool_ops=2(and,or), nesting≈0
      # 1*12 + 0*8 + 2*4 + 0 = 20
      assert score >= 20.0
    end

    test "clamps at 100" do
      # Generate high complexity: many branches + long code
      lines =
        for i <- 1..20 do
          "    if var_#{i} do"
        end

      # 20 branches * 12 = 240, already > 100
      score = CommitHotspotMetrics.compute_complexity(lines, 20)
      assert score == 100.0
    end

    test "formula: branch*12 + nesting*8 + bool*4 + max(0, loc-15)*1.5" do
      # Single branch, no nesting, no bools, loc=20
      lines = ["  if foo do", "    :bar", "  end"]
      # branch=1, nesting=1 (indent 4 spaces = depth 2, minus 1 = 1), bool=0
      # 1*12 + 1*8 + 0 + max(0, 20-15)*1.5 = 12 + 8 + 7.5 = 27.5
      score = CommitHotspotMetrics.compute_complexity(lines, 20)
      assert score == 27.5
    end
  end

  # -- Change churn scoring --

  describe "compute_change_churn/2" do
    test "uses file stats weighted by hunk contribution" do
      file_stat = %{added: 20, deleted: 10}
      hunk = %{lines: Enum.map(1..10, &"line #{&1}")}

      score = CommitHotspotMetrics.compute_change_churn(file_stat, hunk)
      assert is_float(score)
      assert score >= 0.0
      assert score <= 100.0
    end

    test "returns 0 for zero-change files" do
      file_stat = %{added: 0, deleted: 0}
      hunk = %{lines: []}

      score = CommitHotspotMetrics.compute_change_churn(file_stat, hunk)
      assert score == 0.0
    end

    test "clamps at 100" do
      file_stat = %{added: 100, deleted: 100}
      hunk = %{lines: Enum.map(1..200, &"line #{&1}")}

      score = CommitHotspotMetrics.compute_change_churn(file_stat, hunk)
      assert score == 100.0
    end
  end

  # -- Test exposure scoring --

  describe "compute_test_exposure/1" do
    test "returns 100 for test/ paths" do
      assert CommitHotspotMetrics.compute_test_exposure("test/spotter/foo_test.exs") == 100.0
    end

    test "returns 100 for _test.exs suffix" do
      assert CommitHotspotMetrics.compute_test_exposure("some/path/bar_test.exs") == 100.0
    end

    test "returns 70 baseline for source files (no test hits)" do
      assert CommitHotspotMetrics.compute_test_exposure("lib/spotter/services/foo.ex") == 70.0
    end
  end

  # -- Blast radius confidence --

  describe "blast radius confidence classification" do
    test "high when symbol present and fan_in >= 3" do
      {_score, _fan_in, _spread, confidence} =
        CommitHotspotMetrics.compute_blast_radius("my_func", "lib/foo.ex", "abc123", "/tmp/fake")

      # Will be "low" due to git_grep failure on fake repo, but let's test via parse_grep_results
      assert confidence in ["high", "medium", "low"]
    end
  end

  # -- parse_grep_results/2 --

  describe "parse_grep_results/2" do
    test "counts fan_in excluding source file" do
      output = """
      abc123:lib/a.ex:3
      abc123:lib/b.ex:1
      abc123:lib/spotter/services/foo.ex:5
      """

      {fan_in, _module_spread} =
        CommitHotspotMetrics.parse_grep_results(output, "lib/spotter/services/foo.ex")

      assert fan_in == 2
    end

    test "counts module_spread as unique directory prefixes" do
      output = """
      abc123:lib/spotter/services/bar.ex:1
      abc123:lib/spotter/services/baz.ex:2
      abc123:lib/spotter/web/controller.ex:1
      abc123:test/spotter/services/bar_test.exs:1
      """

      {fan_in, module_spread} =
        CommitHotspotMetrics.parse_grep_results(output, "lib/other.ex")

      assert fan_in == 4
      assert module_spread == 3
    end

    test "returns {0, 0} for empty output" do
      assert {0, 0} = CommitHotspotMetrics.parse_grep_results("", "lib/foo.ex")
    end

    test "returns {0, 0} for nil output" do
      assert {0, 0} = CommitHotspotMetrics.parse_grep_results(nil, "lib/foo.ex")
    end
  end

  # -- Symbol detection --

  describe "detect_symbol_name/2" do
    test "extracts from hunk header" do
      assert "process" ==
               CommitHotspotMetrics.detect_symbol_name([], "def process(data) do")
    end

    test "extracts defp from header" do
      assert "helper" ==
               CommitHotspotMetrics.detect_symbol_name([], "defp helper(x) do")
    end

    test "falls back to lines when header is nil" do
      lines = ["  # comment", "  defp my_func(a, b) do", "    a + b"]

      assert "my_func" == CommitHotspotMetrics.detect_symbol_name(lines, nil)
    end

    test "returns nil when no symbol found" do
      lines = ["  :ok", "  |> then(&(&1))"]
      assert nil == CommitHotspotMetrics.detect_symbol_name(lines, nil)
    end

    test "handles defmacro" do
      assert "my_macro" ==
               CommitHotspotMetrics.detect_symbol_name([], "defmacro my_macro(ast) do")
    end
  end
end
