defmodule Spotter.Services.CommitContextBuilderTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitContextBuilder

  @sample_content Enum.map_join(1..200, "\n", fn i -> "line #{i} content" end)

  describe "build_windows/3" do
    test "builds a single window around a range" do
      windows = CommitContextBuilder.build_windows(@sample_content, [{50, 55}], context_lines: 5)

      assert length(windows) == 1
      window = hd(windows)
      assert window.line_start == 45
      assert window.line_end == 60
    end

    test "merges overlapping windows" do
      windows =
        CommitContextBuilder.build_windows(@sample_content, [{50, 55}, {58, 62}],
          context_lines: 5
        )

      assert length(windows) == 1
      window = hd(windows)
      assert window.line_start == 45
      assert window.line_end == 67
    end

    test "keeps non-overlapping windows separate" do
      windows =
        CommitContextBuilder.build_windows(@sample_content, [{10, 12}, {100, 102}],
          context_lines: 5
        )

      assert length(windows) == 2
      assert Enum.at(windows, 0).line_start == 5
      assert Enum.at(windows, 0).line_end == 17
      assert Enum.at(windows, 1).line_start == 95
      assert Enum.at(windows, 1).line_end == 107
    end

    test "clamps to file bounds" do
      windows = CommitContextBuilder.build_windows(@sample_content, [{1, 3}], context_lines: 10)

      assert length(windows) == 1
      assert hd(windows).line_start == 1
      assert hd(windows).line_end == 13
    end

    test "includes numbered lines in content" do
      short_content = "alpha\nbeta\ngamma\ndelta\nepsilon"
      windows = CommitContextBuilder.build_windows(short_content, [{2, 3}], context_lines: 0)

      assert length(windows) == 1
      assert windows |> hd() |> Map.get(:content) =~ "2: beta"
      assert windows |> hd() |> Map.get(:content) =~ "3: gamma"
    end

    test "handles empty ranges" do
      assert CommitContextBuilder.build_windows(@sample_content, [], context_lines: 5) == []
    end
  end

  describe "build_windows/3 splitting" do
    @large_content Enum.map_join(1..300, "\n", fn i -> "line #{i} content" end)

    test "splits oversized windows by max_window_lines" do
      windows =
        CommitContextBuilder.build_windows(@large_content, [{1, 200}],
          context_lines: 0,
          max_window_lines: 50,
          max_window_bytes: 20_000
        )

      assert length(windows) == 4
      assert hd(windows).line_start == 1
      assert hd(windows).line_end == 50
      assert List.last(windows).line_start == 151
      assert List.last(windows).line_end == 200
    end
  end

  describe "build_windows/3 byte truncation" do
    test "truncates content exceeding max_window_bytes" do
      big_line = String.duplicate("x", 30_000)
      file_content = big_line <> "\nshort line\nanother line"

      windows =
        CommitContextBuilder.build_windows(file_content, [{1, 1}],
          context_lines: 0,
          max_window_bytes: 200
        )

      assert length(windows) == 1
      window = hd(windows)
      assert window.content =~ "... (truncated)"
      assert byte_size(window.content) <= 200
    end
  end

  describe "build_windows/3 empty content" do
    test "returns no windows for empty content" do
      assert CommitContextBuilder.build_windows("", [{1, 1}], context_lines: 0) == []
    end
  end
end
