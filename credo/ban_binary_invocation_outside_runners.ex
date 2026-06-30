defmodule Baudflow.CredoChecks.BanBinaryInvocationOutsideRunners do
  @moduledoc false

  use Credo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Invoking a test binary (`System.cmd` / `Port.open`) belongs only in a
      TestRunner impl (lib/baudflow/test_runners/). The RunnerWorker resolves
      the impl by test_type and owns the pipeline; the binary invocation is the
      impl's job, so a new backend is one impl file with zero edits to workers.
      (See ARCHITECTURE.md.)
      """
    ]

  @impl Credo.Check
  def run(%{filename: filename} = source_file, params) do
    if in_lib?(filename) and not runner_impl?(filename) do
      issue_meta = Credo.IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  # System.cmd(...)
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:System]}, :cmd]}, _, _args} = ast,
         issues,
         im
       ) do
    {ast,
     [
       issue(im, "Binary invocation (System.cmd) belongs only in a TestRunner impl", meta)
       | issues
     ]}
  end

  # Port.open(...)
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Port]}, :open]}, _, _args} = ast,
         issues,
         im
       ) do
    {ast,
     [issue(im, "Binary invocation (Port.open) belongs only in a TestRunner impl", meta) | issues]}
  end

  defp traverse(ast, issues, _im), do: {ast, issues}

  defp issue(im, message, meta) do
    format_issue(im, message: message, line_no: meta[:line])
  end

  defp in_lib?(filename) when is_binary(filename), do: String.starts_with?(filename, "lib/")
  defp in_lib?(_), do: false

  # Only reached after `in_lib?/1` short-circuits true, so `filename` is a binary.
  defp runner_impl?(filename), do: String.starts_with?(filename, "lib/baudflow/test_runners/")
end
