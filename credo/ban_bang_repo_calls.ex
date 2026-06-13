defmodule Baudflow.CredoChecks.BanBangRepoCalls do
  @moduledoc false

  use Credo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Bang Repo mutation calls (Repo.update!/insert!/delete!) raise on a
      constraint/validation failure, which crashes a worker. Mutations must go
      through a changeset plus the non-bang Repo.update/insert/delete so a
      failure returns {:error, changeset}.
      (See CLAUDE.md "Schemas & Ecto".)
      """
    ]

  @bang_mutations [:update!, :insert!, :delete!]

  @impl Credo.Check
  def run(%{filename: filename} = source_file, params) do
    if in_lib?(filename) do
      issue_meta = Credo.IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  # Baudflow.Repo.<bang_mutation>(...) and Repo.<bang_mutation>(...) (bare alias)
  defp traverse({{:., meta, [{:__aliases__, _, alias_parts}, fun]}, _, _args} = ast, issues, im)
       when fun in @bang_mutations and alias_parts in [[:Baudflow, :Repo], [:Repo]] do
    {ast,
     [
       issue(
         im,
         "Use a non-bang Repo mutation (via a changeset) so failures return {:error, _}",
         meta
       )
       | issues
     ]}
  end

  defp traverse(ast, issues, _im), do: {ast, issues}

  defp issue(im, message, meta) do
    format_issue(im, message: message, line_no: meta[:line])
  end

  defp in_lib?(filename) when is_binary(filename), do: String.starts_with?(filename, "lib/")
  defp in_lib?(_), do: false
end
