defmodule Spotter.Transcripts.SessionPresenterTest do
  use ExUnit.Case, async: true

  alias Spotter.Transcripts.Session
  alias Spotter.Transcripts.SessionPresenter

  defp session(attrs) do
    struct!(Session, attrs)
  end

  describe "primary_label/1" do
    test "prefers custom_title" do
      s =
        session(
          custom_title: "My Title",
          summary: "Summary",
          slug: "my-slug",
          first_prompt: "Do something",
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "My Title"
    end

    test "falls back to summary when custom_title is nil" do
      s =
        session(
          custom_title: nil,
          summary: "Summary text",
          slug: "my-slug",
          first_prompt: "Do something",
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "Summary text"
    end

    test "falls back to slug when custom_title and summary are nil" do
      s =
        session(
          custom_title: nil,
          summary: nil,
          slug: "my-slug",
          first_prompt: "Do something",
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "my-slug"
    end

    test "falls back to truncated first_prompt when title, summary, slug are nil" do
      s =
        session(
          custom_title: nil,
          summary: nil,
          slug: nil,
          first_prompt: "Help me fix this bug",
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "Help me fix this bug"
    end

    test "truncates first_prompt at 72 chars" do
      long_prompt = String.duplicate("a", 100)

      s =
        session(
          custom_title: nil,
          summary: nil,
          slug: nil,
          first_prompt: long_prompt,
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      result = SessionPresenter.primary_label(s)
      # 71 chars + ellipsis
      assert String.length(result) == 72
      assert String.ends_with?(result, "\u2026")
    end

    test "normalizes whitespace in first_prompt" do
      s =
        session(
          custom_title: nil,
          summary: nil,
          slug: nil,
          first_prompt: "Hello\n  world\t\there",
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "Hello world here"
    end

    test "falls back to short session_id when all fields are nil" do
      s =
        session(
          custom_title: nil,
          summary: nil,
          slug: nil,
          first_prompt: nil,
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "aaaaaaaa"
    end

    test "skips blank strings in precedence" do
      s =
        session(
          custom_title: "  ",
          summary: "",
          slug: nil,
          first_prompt: nil,
          session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )

      assert SessionPresenter.primary_label(s) == "aaaaaaaa"
    end
  end

  describe "secondary_label/1" do
    test "shows slug and short id" do
      s = session(slug: "my-slug", session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
      assert SessionPresenter.secondary_label(s) == "slug:my-slug \u00b7 id:aaaaaaaa"
    end

    test "shows dash for nil slug" do
      s = session(slug: nil, session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
      assert SessionPresenter.secondary_label(s) == "slug:\u2014 \u00b7 id:aaaaaaaa"
    end
  end

  describe "started_display/2" do
    @now ~U[2026-01-15 12:00:00Z]

    test "returns nil for nil input" do
      assert SessionPresenter.started_display(nil) == nil
    end

    test "shows seconds ago" do
      dt = DateTime.add(@now, -30, :second)
      result = SessionPresenter.started_display(dt, @now)
      assert result.relative == "30s ago"
      assert result.absolute == "2026-01-15 11:59"
    end

    test "shows minutes ago" do
      dt = DateTime.add(@now, -300, :second)
      result = SessionPresenter.started_display(dt, @now)
      assert result.relative == "5m ago"
    end

    test "shows hours ago" do
      dt = DateTime.add(@now, -7200, :second)
      result = SessionPresenter.started_display(dt, @now)
      assert result.relative == "2h ago"
    end

    test "shows days ago" do
      dt = DateTime.add(@now, -172_800, :second)
      result = SessionPresenter.started_display(dt, @now)
      assert result.relative == "2d ago"
    end

    test "absolute format is UTC Y-m-d H:M" do
      dt = ~U[2026-01-15 09:05:00Z]
      result = SessionPresenter.started_display(dt, @now)
      assert result.absolute == "2026-01-15 09:05"
    end
  end
end
