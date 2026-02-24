defmodule SpotterWeb.ReviewsChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.ReviewUpdates
  alias Spotter.Transcripts.{Annotation, Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id
    })
  end

  defp create_annotation(session, state) do
    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: "text-#{System.unique_integer([:positive])}",
      comment: "comment",
      state: state
    })
  end

  defp join_reviews_counts do
    {:ok, socket} = Phoenix.ChannelTest.connect(SpotterWeb.UserSocket, %{})
    Phoenix.ChannelTest.subscribe_and_join(socket, "reviews:counts", %{})
  end

  describe "join reviews:counts" do
    test "returns snapshot with zero counts when no data exists" do
      {:ok, payload, _socket} = join_reviews_counts()

      assert payload.total_open_count == 0
      assert payload.project_counts == []
    end

    test "returns snapshot with open annotation counts" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)
      create_annotation(session, :open)
      create_annotation(session, :closed)

      {:ok, payload, _socket} = join_reviews_counts()

      assert payload.total_open_count == 2

      assert [%{project_id: _, project_name: "alpha", open_count: 2}] =
               payload.project_counts
    end

    test "returns counts for multiple projects" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :open)

      {:ok, payload, _socket} = join_reviews_counts()

      assert payload.total_open_count == 3

      alpha = Enum.find(payload.project_counts, &(&1.project_name == "alpha"))
      beta = Enum.find(payload.project_counts, &(&1.project_name == "beta"))

      assert alpha.open_count == 1
      assert beta.open_count == 2
    end

    test "includes projects with zero open annotations" do
      create_project("empty")

      {:ok, payload, _socket} = join_reviews_counts()

      assert [%{project_name: "empty", open_count: 0}] = payload.project_counts
    end
  end

  describe "broadcast_counts/0" do
    test "broadcasts counts_updated event to reviews:counts" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _payload, _socket} = join_reviews_counts()

      ReviewUpdates.broadcast_counts()

      assert_broadcast("counts_updated", %{project_counts: counts})
      alpha = Enum.find(counts, &(&1.project_name == "alpha"))
      assert alpha.open_count == 1
    end

    test "broadcasts zero counts when no annotations exist" do
      {:ok, _payload, _socket} = join_reviews_counts()

      ReviewUpdates.broadcast_counts()

      assert_broadcast("counts_updated", %{total_open_count: 0, project_counts: []})
    end
  end
end
