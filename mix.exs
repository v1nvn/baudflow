defmodule Baudflow.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :baudflow,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Baudflow.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Web
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_html, "~> 4.0"},
      {:bandit, "~> 1.5"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:live_debugger, "~> 1.0", only: :dev},

      # Database
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},

      # Background jobs
      {:oban, "~> 2.18"},

      # Cron expression parsing (for dynamic schedule matching)
      {:crontab, "~> 1.1"},

      # Assets
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},

      # JSON
      {:jason, "~> 1.4"},

      # HTTP client
      {:req, "~> 0.5"},

      # Telemetry
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Test
      # Throwaway Postgres in Docker - hermetic, no local PG install needed
      {:testcontainers, "~> 2.3", only: :test},

      # Lint / static analysis (compile-time only, never shipped in the release)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Phoenix-focused security scanner
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      # Dependency CVE scanning
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Automated versioning via conventional commits
      {:git_ops, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      # ecto.create is a no-op against the container's pre-created DB, but keeps
      # the alias usable against a plain local PG too.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind baudflow", "esbuild baudflow"],
      "assets.deploy": [
        "tailwind baudflow --minify",
        "esbuild baudflow --minify",
        "phx.digest"
      ],
      # Lint/typecheck/security gate - no DB required
      lint: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "deps.audit",
        "compile --warnings-as-errors",
        "credo --strict",
        "sobelow --config",
        "dialyzer"
      ],
      # Full gate: lint + tests in a throwaway Postgres
      check: ["lint", "testcontainers.run --database postgres test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
