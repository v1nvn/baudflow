defmodule Baudflow.CredoChecks.BanNonReqHttp do
  @moduledoc false

  use Credo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Req is the only approved HTTP client. Do not use :httpc, HTTPoison, Tesla,
      or Application.ensure_all_started(:inets) for outbound calls.
      (See CLAUDE.md "HTTP".)
      """
    ]

  @banned_aliases [:HTTPoison, :Tesla]

  @impl Credo.Check
  def run(source_file, params) do
    issue_meta = Credo.IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # :httpc.request(...) — atom receiver
  defp traverse({{:., meta, [:httpc, :request]}, _, _args} = ast, issues, im) do
    {ast, [issue(im, "Use Req instead of :httpc", meta) | issues]}
  end

  # Application.ensure_all_started(:inets)
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Application]}, :ensure_all_started]}, _, [:inets]} = ast,
         issues,
         im
       ) do
    {ast, [issue(im, "Do not start :inets manually; use Req", meta) | issues]}
  end

  # Banned alias modules (HTTPoison/Tesla) — any call or reference
  defp traverse({:__aliases__, meta, [name]} = ast, issues, im) when name in @banned_aliases do
    {ast, [issue(im, "Use Req instead of #{name}", meta) | issues]}
  end

  # :httpc atom used as a bare reference (not just in a call)
  defp traverse({:httpc, meta, ctx} = ast, issues, im) when is_atom(ctx) do
    {ast, [issue(im, "Use Req instead of :httpc", meta) | issues]}
  end

  defp traverse(ast, issues, _im), do: {ast, issues}

  defp issue(im, message, meta) do
    format_issue(im, message: message, line_no: meta[:line])
  end
end
