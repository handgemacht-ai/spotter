defmodule Spotter.Services.SkillFolderReaderTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.SkillFolderReader

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "skill_folder_reader_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  describe "classify_folder/1" do
    test "classifies .claude/agent-memory as :agent_memory" do
      assert SkillFolderReader.classify_folder(".claude/agent-memory") == :agent_memory
    end

    test "classifies .claude/skills/product as :product_skill" do
      assert SkillFolderReader.classify_folder(".claude/skills/product") == :product_skill
    end

    test "classifies .claude/skills/design as :design_skill" do
      assert SkillFolderReader.classify_folder(".claude/skills/design") == :design_skill
    end

    test "classifies .claude/rules as :claude_rules" do
      assert SkillFolderReader.classify_folder(".claude/rules") == :claude_rules
    end

    test "classifies unknown paths as :custom" do
      assert SkillFolderReader.classify_folder(".claude/skills/other") == :custom
      assert SkillFolderReader.classify_folder("some/random/path") == :custom
    end
  end

  describe "list_files/2" do
    test "lists files recursively sorted alphabetically by relative path", %{tmp_dir: tmp_dir} do
      folder = "skills"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(Path.join(base, "sub"))
      File.write!(Path.join(base, "zebra.md"), "z")
      File.write!(Path.join(base, "alpha.md"), "a")
      File.write!(Path.join([base, "sub", "nested.md"]), "n")

      assert {:ok, files} = SkillFolderReader.list_files(tmp_dir, folder)

      paths = Enum.map(files, & &1.relative_path)
      assert paths == ["skills/alpha.md", "skills/sub/nested.md", "skills/zebra.md"]

      assert Enum.all?(files, &Map.has_key?(&1, :filename))
      assert Enum.map(files, & &1.filename) == ["alpha.md", "nested.md", "zebra.md"]
    end

    test "filters files by allowed extensions only", %{tmp_dir: tmp_dir} do
      folder = "docs"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(base)
      File.write!(Path.join(base, "readme.md"), "ok")
      File.write!(Path.join(base, "config.toml"), "ok")
      File.write!(Path.join(base, "code.ex"), "ok")
      File.write!(Path.join(base, "image.png"), "binary")
      File.write!(Path.join(base, "data.bin"), "binary")

      assert {:ok, files} = SkillFolderReader.list_files(tmp_dir, folder)

      extensions = files |> Enum.map(& &1.filename) |> Enum.map(&Path.extname/1) |> Enum.sort()
      assert ".ex" in extensions
      assert ".md" in extensions
      assert ".toml" in extensions
      refute ".png" in extensions
      refute ".bin" in extensions
    end

    test "caps results at 50 files", %{tmp_dir: tmp_dir} do
      folder = "many"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(base)

      for i <- 1..60 do
        File.write!(Path.join(base, "file_#{String.pad_leading("#{i}", 3, "0")}.md"), "content")
      end

      assert {:ok, files} = SkillFolderReader.list_files(tmp_dir, folder)
      assert length(files) == 50
    end

    test "returns error for missing folder", %{tmp_dir: tmp_dir} do
      assert {:error, :not_found} = SkillFolderReader.list_files(tmp_dir, "nonexistent")
    end

    test "returns ok with empty list for empty folder", %{tmp_dir: tmp_dir} do
      folder = "empty"
      File.mkdir_p!(Path.join(tmp_dir, folder))

      assert {:ok, []} = SkillFolderReader.list_files(tmp_dir, folder)
    end
  end

  describe "render_folder/2" do
    test "renders markdown files as HTML via Earmark", %{tmp_dir: tmp_dir} do
      folder = "docs"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(base)
      File.write!(Path.join(base, "readme.md"), "# Hello\n\nSome **bold** text.")

      assert {:ok, [rendered]} = SkillFolderReader.render_folder(tmp_dir, folder)

      assert rendered.filename == "readme.md"
      assert rendered.relative_path == "docs/readme.md"
      assert rendered.raw_content == "# Hello\n\nSome **bold** text."
      assert rendered.html_content =~ "<h1>"
      assert rendered.html_content =~ "<strong>bold</strong>"
      assert is_integer(rendered.line_count)
    end

    test "renders non-markdown files in pre/code blocks with language class", %{tmp_dir: tmp_dir} do
      folder = "code"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(base)
      File.write!(Path.join(base, "example.ex"), "defmodule Foo do\nend")

      assert {:ok, [rendered]} = SkillFolderReader.render_folder(tmp_dir, folder)

      assert rendered.filename == "example.ex"
      assert rendered.html_content =~ "<pre><code"
      assert rendered.html_content =~ "language-elixir"
      assert rendered.raw_content == "defmodule Foo do\nend"
    end

    test "skips files larger than 100KB", %{tmp_dir: tmp_dir} do
      folder = "big"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(base)
      File.write!(Path.join(base, "small.md"), "ok")
      File.write!(Path.join(base, "huge.md"), String.duplicate("x", 100_001))

      assert {:ok, rendered} = SkillFolderReader.render_folder(tmp_dir, folder)

      filenames = Enum.map(rendered, & &1.filename)
      assert "small.md" in filenames
      refute "huge.md" in filenames
    end

    test "returns error for missing folder", %{tmp_dir: tmp_dir} do
      assert {:error, :not_found} = SkillFolderReader.render_folder(tmp_dir, "nonexistent")
    end

    test "sanitizes dangerous HTML from markdown output", %{tmp_dir: tmp_dir} do
      folder = "xss"
      base = Path.join(tmp_dir, folder)
      File.mkdir_p!(base)
      File.write!(Path.join(base, "evil.md"), "<script>alert('xss')</script>\n\nSafe content.")

      assert {:ok, [rendered]} = SkillFolderReader.render_folder(tmp_dir, folder)

      refute rendered.html_content =~ "<script"
      assert rendered.html_content =~ "Safe content"
    end
  end
end
