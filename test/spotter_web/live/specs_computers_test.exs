defmodule SpotterWeb.Live.SpecsComputersTest do
  use ExUnit.Case, async: true

  alias AshComputer.Info
  alias SpotterWeb.Live.SpecsComputers

  @computer_name :specs_view

  describe "computer definition" do
    test "defines :specs_view computer" do
      assert @computer_name in Info.computer_names(SpecsComputers)
    end
  end

  describe "inputs have correct defaults" do
    setup do
      computer = Info.computer(SpecsComputers, @computer_name)
      inputs = Map.new(computer.inputs, &{&1.name, &1.initial})
      %{inputs: inputs}
    end

    test "project_id defaults to nil", %{inputs: inputs} do
      assert inputs[:project_id] == nil
    end

    test "commit_id defaults to nil", %{inputs: inputs} do
      assert inputs[:commit_id] == nil
    end

    test "artifact defaults to :product", %{inputs: inputs} do
      assert inputs[:artifact] == :product
    end

    test "spec_view defaults to :diff", %{inputs: inputs} do
      assert inputs[:spec_view] == :diff
    end

    test "search_query defaults to empty string", %{inputs: inputs} do
      assert inputs[:search_query] == ""
    end

    test "commit_cursor defaults to nil", %{inputs: inputs} do
      assert inputs[:commit_cursor] == nil
    end
  end

  describe "val dependencies" do
    setup do
      computer = Info.computer(SpecsComputers, @computer_name)
      vals = Map.new(computer.vals, &{&1.name, &1})
      %{vals: vals}
    end

    test "project depends only on project_id", %{vals: vals} do
      assert vals[:project].depends_on == [:project_id]
    end

    test "commit_rows depends only on project_id", %{vals: vals} do
      assert vals[:commit_rows].depends_on == [:project_id]
    end

    test "selected_commit depends only on commit_id", %{vals: vals} do
      assert vals[:selected_commit].depends_on == [:commit_id]
    end

    test "active_detail depends on artifact and both detail vals", %{vals: vals} do
      deps = vals[:active_detail].depends_on
      assert :artifact in deps
      assert :product_detail in deps
      assert :tests_detail in deps
    end

    test "product_detail depends on selected_commit, project_id, spec_view, product_dolt_available",
         %{vals: vals} do
      deps = vals[:product_detail].depends_on
      assert :selected_commit in deps
      assert :project_id in deps
      assert :spec_view in deps
      assert :product_dolt_available in deps
    end

    test "tests_detail depends on selected_commit, project_id, spec_view, tests_dolt_available",
         %{vals: vals} do
      deps = vals[:tests_detail].depends_on
      assert :selected_commit in deps
      assert :project_id in deps
      assert :spec_view in deps
      assert :tests_dolt_available in deps
    end

    test "error_state depends on project_id, commit_id, selected_commit", %{vals: vals} do
      deps = vals[:error_state].depends_on
      assert :project_id in deps
      assert :commit_id in deps
      assert :selected_commit in deps
    end
  end

  describe "required val nodes exist" do
    setup do
      computer = Info.computer(SpecsComputers, @computer_name)
      val_names = Enum.map(computer.vals, & &1.name)
      %{val_names: val_names}
    end

    test "has all required val nodes", %{val_names: val_names} do
      required = [
        :project,
        :commit_rows,
        :selected_commit,
        :product_dolt_available,
        :tests_dolt_available,
        :product_detail,
        :tests_detail,
        :active_detail,
        :error_state
      ]

      for name <- required do
        assert name in val_names, "missing val node: #{name}"
      end
    end
  end
end
