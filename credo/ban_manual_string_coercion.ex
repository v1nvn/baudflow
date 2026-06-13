defmodule Baudflow.CredoChecks.BanManualStringCoercion do
  @moduledoc false

  use Credo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      String.to_integer/1 and String.to_float/1 raise on malformed input and have no
      fallback. String.to_float/1 even raises on integer-looking strings (e.g. "1").

      Use the Settings typed accessors instead — get_integer/2, get_float/2,
      get_boolean/1, get_integer_list/1 — which coerce safely and return a default.
      (See CLAUDE.md "Settings".)
      """
    ]

  @allowed_files ~w(
    lib/baudflow/settings/settings.ex
  )

  @impl Credo.Check
  def run(%{filename: filename} = source_file, params) do
    if allowed_file?(filename) do
      []
    else
      issue_meta = Credo.IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  # String.to_integer/1
  defp traverse(
         {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, meta, _args} = ast,
         issues,
         im
       ) do
    {ast,
     [
       format_issue(im,
         message: "Use Settings.get_integer/2 instead of String.to_integer/1",
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  # String.to_float/1
  defp traverse(
         {{:., _, [{:__aliases__, _, [:String]}, :to_float]}, meta, _args} = ast,
         issues,
         im
       ) do
    {ast,
     [
       format_issue(im,
         message: "Use Settings.get_float/2 instead of String.to_float/1",
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  defp traverse(ast, issues, _im), do: {ast, issues}

  defp allowed_file?(nil), do: false

  defp allowed_file?(filename) do
    Enum.any?(@allowed_files, &String.ends_with?(filename, &1))
  end
end
