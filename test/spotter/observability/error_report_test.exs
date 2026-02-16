defmodule Spotter.Observability.ErrorReportTest do
  use ExUnit.Case, async: true

  alias Spotter.Observability.ErrorReport

  describe "trace_error/3" do
    test "returns required contract keys" do
      result = ErrorReport.trace_error("my_error", "something failed", "my.module")

      assert result["error.type"] == "my_error"
      assert result["error.message"] == "something failed"
      assert result["error.source"] == "my.module"
    end

    test "merges extra attributes" do
      result =
        ErrorReport.trace_error("my_error", "failed", "my.module", %{
          "job_id" => 42,
          "attempt" => 3
        })

      assert result["error.type"] == "my_error"
      assert result["error.message"] == "failed"
      assert result["error.source"] == "my.module"
      assert result["job_id"] == 42
      assert result["attempt"] == 3
    end

    test "extras can override base keys" do
      result =
        ErrorReport.trace_error("my_error", "failed", "my.module", %{
          "error.source" => "overridden"
        })

      assert result["error.source"] == "overridden"
    end
  end

  describe "hook_flow_error/5" do
    test "returns all required hook error keys" do
      result =
        ErrorReport.hook_flow_error("bad_input", "invalid data", 400, "PostToolUse", "hook.sh")

      assert result["error.type"] == "bad_input"
      assert result["error.message"] == "invalid data"
      assert result["error.source"] == "hooks_controller"
      assert result["http.status_code"] == 400
      assert result["hook_event"] == "PostToolUse"
      assert result["hook_script"] == "hook.sh"
    end

    test "merges extra attributes" do
      result =
        ErrorReport.hook_flow_error("bad_input", "invalid", 400, "PostToolUse", "hook.sh", %{
          "session_id" => "abc"
        })

      assert result["session_id"] == "abc"
      assert result["error.type"] == "bad_input"
    end
  end

  describe "set_trace_error/3" do
    test "returns :ok and does not raise" do
      assert :ok == ErrorReport.set_trace_error("test_error", "test message", "test.module")
    end

    test "handles non-string extras gracefully" do
      assert :ok ==
               ErrorReport.set_trace_error("test_error", "msg", "test.module", %{
                 "count" => 42,
                 "flag" => true
               })
    end
  end
end
