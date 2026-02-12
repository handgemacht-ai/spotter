defmodule Spotter.Services.WaitingSummary.SliceBuilderTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.WaitingSummary.SliceBuilder

  defp make_msg(role, text) do
    %{
      type: role,
      role: role,
      content: %{"text" => text},
      uuid: Ash.UUID.generate(),
      timestamp: DateTime.utc_now()
    }
  end

  describe "build/2" do
    test "returns empty result for empty messages" do
      {selected, meta} = SliceBuilder.build([])

      assert selected == []
      assert meta.head_messages == 0
      assert meta.tail_messages == 0
      assert meta.input_chars == 0
    end

    test "returns all messages when under budget" do
      messages = [
        make_msg(:user, "hello"),
        make_msg(:assistant, "hi there"),
        make_msg(:user, "thanks")
      ]

      {selected, meta} = SliceBuilder.build(messages, budget: 10_000)

      assert length(selected) == 3
      assert meta.input_chars > 0
    end

    test "preserves chronological order" do
      messages =
        for i <- 1..20 do
          make_msg(:user, "message #{i}")
        end

      {selected, _meta} = SliceBuilder.build(messages, budget: 500)

      texts = Enum.map(selected, &SliceBuilder.message_text/1)

      # Extract message numbers and verify ordering
      numbers =
        texts
        |> Enum.map(fn text ->
          case Regex.run(~r/message (\d+)/, text) do
            [_, n] -> String.to_integer(n)
            _ -> 0
          end
        end)

      assert numbers == Enum.sort(numbers)
    end

    test "avoids duplicate overlap on short transcripts" do
      messages = [
        make_msg(:user, "only two messages"),
        make_msg(:assistant, "response")
      ]

      {selected, _meta} = SliceBuilder.build(messages, budget: 10_000)

      uuids = Enum.map(selected, & &1.uuid)
      assert length(uuids) == length(Enum.uniq(uuids))
    end

    test "respects character budget" do
      messages =
        for i <- 1..100 do
          make_msg(:user, "message number #{i} with some padding text to use budget")
        end

      {_selected, meta} = SliceBuilder.build(messages, budget: 500)

      assert meta.input_chars <= 500
    end

    test "selects from both head and tail" do
      messages =
        for i <- 1..20 do
          make_msg(:user, "msg #{i}")
        end

      {selected, meta} = SliceBuilder.build(messages, budget: 300)

      assert meta.head_messages > 0
      assert meta.tail_messages > 0
      assert selected != []
    end

    test "handles single message transcript" do
      messages = [make_msg(:user, "solo")]

      {selected, meta} = SliceBuilder.build(messages, budget: 10_000)

      assert length(selected) == 1
      assert meta.input_chars > 0
    end

    test "handles budget smaller than first message" do
      messages = [make_msg(:user, String.duplicate("x", 100))]

      {selected, _meta} = SliceBuilder.build(messages, budget: 5)

      assert selected == []
    end
  end

  describe "message_text/1" do
    test "extracts text content" do
      msg = make_msg(:user, "hello world")
      assert SliceBuilder.message_text(msg) == "[user] hello world"
    end

    test "extracts tool_use blocks" do
      msg = %{
        type: :assistant,
        role: :assistant,
        content: %{
          "blocks" => [
            %{"type" => "text", "text" => "Let me check"},
            %{"type" => "tool_use", "name" => "Bash"}
          ]
        }
      }

      text = SliceBuilder.message_text(msg)
      assert text =~ "Let me check"
      assert text =~ "[tool: Bash]"
    end

    test "handles nil content" do
      msg = %{type: :system, role: nil, content: nil}
      assert SliceBuilder.message_text(msg) =~ "system"
    end
  end

  describe "message_char_size/1" do
    test "returns string length of message text" do
      msg = make_msg(:user, "test")
      size = SliceBuilder.message_char_size(msg)
      assert size == String.length("[user] test")
    end
  end
end
