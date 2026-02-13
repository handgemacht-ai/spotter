defmodule Spotter.Services.FileBlameParserTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.FileBlame

  # Porcelain output must not have leading whitespace
  @porcelain_fixture "abc1234567890abc1234567890abc123456789ab 1 1 3\nauthor Alice\nauthor-mail <alice@example.com>\nauthor-time 1700000000\nauthor-tz +0000\ncommitter Alice\ncommitter-mail <alice@example.com>\ncommitter-time 1700000000\ncommitter-tz +0000\nsummary Initial commit\nfilename lib/hello.ex\n\tdefmodule Hello do\nabc1234567890abc1234567890abc123456789ab 2 2\n\t  def greet, do: :world\ndef567890123456789012345678901234567abcd 3 3 1\nauthor Bob\nauthor-mail <bob@example.com>\nauthor-time 1700100000\nauthor-tz +0000\ncommitter Bob\ncommitter-mail <bob@example.com>\ncommitter-time 1700100000\ncommitter-tz +0000\nsummary Add end keyword\nfilename lib/hello.ex\n\tend\n"

  describe "parse_porcelain/1" do
    test "parses line numbers, hashes, authors, summaries, and text" do
      rows = FileBlame.parse_porcelain(@porcelain_fixture)

      assert length(rows) == 3

      [first, second, third] = rows

      assert first.line_no == 1
      assert first.commit_hash == "abc1234567890abc1234567890abc123456789ab"
      assert first.author == "Alice"
      assert first.summary == "Initial commit"
      assert first.text == "defmodule Hello do"

      assert second.line_no == 2
      assert second.commit_hash == "abc1234567890abc1234567890abc123456789ab"
      assert second.author == "Alice"
      assert second.summary == "Initial commit"
      assert second.text == "  def greet, do: :world"

      assert third.line_no == 3
      assert third.commit_hash == "def567890123456789012345678901234567abcd"
      assert third.author == "Bob"
      assert third.summary == "Add end keyword"
      assert third.text == "end"
    end

    test "handles empty input" do
      assert FileBlame.parse_porcelain("") == []
    end
  end
end
