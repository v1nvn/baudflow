defmodule Baudflow.CredoChecks.BanRepoOutsideContexts do
  @moduledoc false

  use Credo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      All database access must go through the context modules:
      lib/baudflow/measurements/measurements.ex, lib/baudflow/runs/runs.ex,
      lib/baudflow/scheduling/scheduling.ex, lib/baudflow/settings/settings.ex.
      Workers and LiveViews call context functions instead of importing
      Ecto.Query or calling Repo directly. (See CLAUDE.md "Layering & contexts".)
      """
    ]

  @context_files ~w(
    lib/baudflow/measurements/measurements.ex
    lib/baudflow/runs/runs.ex
    lib/baudflow/scheduling/scheduling.ex
    lib/baudflow/settings/settings.ex
  )

  @impl Credo.Check
  def run(%{filename: filename} = source_file, params) do
    # The layering rule governs production code (workers/LiveViews). Test code
    # legitimately queries the DB to assert on state, so it is out of scope.
    if context_file?(filename) or not in_lib?(filename) do
      []
    else
      issue_meta = Credo.IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  # import Ecto.Query
  defp traverse({:import, meta, [{:__aliases__, _, [:Ecto, :Query]} | _]} = ast, issues, im) do
    issue =
      format_issue(im,
        message: "import Ecto.Query belongs only in context modules (use a context function)",
        line_no: meta[:line]
      )

    {ast, [issue | issues]}
  end

  # Baudflow.Repo.<fun>(...)
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Baudflow, :Repo]}, _fun]}, _, _args} = ast,
         issues,
         im
       ) do
    issue =
      format_issue(im,
        message: "Repo calls belong only in context modules (use a context function)",
        line_no: meta[:line]
      )

    {ast, [issue | issues]}
  end

  # Repo.<fun>(...) (bare alias)
  defp traverse({{:., meta, [{:__aliases__, _, [:Repo]}, _fun]}, _, _args} = ast, issues, im) do
    issue =
      format_issue(im,
        message: "Repo calls belong only in context modules (use a context function)",
        line_no: meta[:line]
      )

    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _im), do: {ast, issues}

  defp context_file?(nil), do: false

  defp context_file?(filename) do
    Enum.any?(@context_files, &String.ends_with?(filename, &1))
  end

  defp in_lib?(filename) when is_binary(filename), do: String.starts_with?(filename, "lib/")
  defp in_lib?(_), do: false
end
