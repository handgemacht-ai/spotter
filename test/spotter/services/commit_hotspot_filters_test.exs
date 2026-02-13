defmodule Spotter.Services.CommitHotspotFiltersTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitHotspotFilters

  import CommitHotspotFilters, only: [eligible_path?: 1]

  describe "eligible_path?/1 with defaults" do
    test "blocks .beads/ paths" do
      refute eligible_path?(".beads/issues.jsonl")
    end

    test "blocks _build/ paths" do
      refute eligible_path?("_build/dev/lib/foo.beam")
    end

    test "blocks deps/ paths" do
      refute eligible_path?("deps/some_dep/lib/x.ex")
    end

    test "blocks node_modules/ paths" do
      refute eligible_path?("node_modules/foo/index.js")
    end

    test "blocks .git/ paths" do
      refute eligible_path?(".git/config")
    end

    test "blocks tmp/ paths" do
      refute eligible_path?("tmp/cache.dat")
    end

    test "blocks priv/static/ paths" do
      refute eligible_path?("priv/static/assets/app.js")
    end

    test "blocks test/fixtures/ paths" do
      refute eligible_path?("test/fixtures/sample.json")
    end

    test "blocks files by extension" do
      refute eligible_path?("data/export.jsonl")
      refute eligible_path?("some.db")
      refute eligible_path?("some.db-wal")
      refute eligible_path?("some.db-shm")
      refute eligible_path?("mix.lock")
      refute eligible_path?("app.log")
      refute eligible_path?("logo.png")
      refute eligible_path?("photo.jpg")
      refute eligible_path?("photo.jpeg")
      refute eligible_path?("anim.gif")
      refute eligible_path?("doc.pdf")
      refute eligible_path?("font.woff")
      refute eligible_path?("font.woff2")
      refute eligible_path?("font.ttf")
      refute eligible_path?("font.eot")
      refute eligible_path?("archive.zip")
      refute eligible_path?("archive.tar")
      refute eligible_path?("archive.gz")
    end

    test "extension matching is case-insensitive" do
      refute eligible_path?("image.PNG")
      refute eligible_path?("image.Jpg")
    end

    test "allows regular source files" do
      assert eligible_path?("lib/spotter/services/commit_hotspot_agent.ex")
      assert eligible_path?("test/spotter/services/some_test.exs")
      assert eligible_path?("lib/spotter_web/live/session_live.ex")
      assert eligible_path?("mix.exs")
      assert eligible_path?("config/config.exs")
    end
  end

  describe "eligible_path?/1 with env override for prefixes" do
    setup do
      prev = System.get_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_PREFIXES")
      System.put_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_PREFIXES", ".beads/")

      on_exit(fn ->
        if prev,
          do: System.put_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_PREFIXES", prev),
          else: System.delete_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_PREFIXES")
      end)

      :ok
    end

    test "overridden prefixes replace defaults" do
      # .beads/ still blocked
      refute eligible_path?(".beads/issues.jsonl")

      # deps/ no longer blocked by prefix (but .ex extension is allowed)
      assert eligible_path?("deps/some_dep/lib/x.ex")
    end
  end

  describe "eligible_path?/1 with env override for extensions" do
    setup do
      prev = System.get_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_EXTENSIONS")
      System.put_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_EXTENSIONS", "jsonl")

      on_exit(fn ->
        if prev,
          do: System.put_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_EXTENSIONS", prev),
          else: System.delete_env("SPOTTER_COMMIT_HOTSPOT_BLOCKLIST_EXTENSIONS")
      end)

      :ok
    end

    test "normalizes extensions without leading dot" do
      refute eligible_path?("data/export.jsonl")
    end

    test "overridden extensions replace defaults" do
      # .png no longer blocked since we only specified jsonl
      assert eligible_path?("logo.png")
    end
  end
end
