defmodule RideAlong.MixProject do
  use Mix.Project

  def project do
    [
      app: :ride_along,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        summary: [threshold: 45]
      ],
      aliases: aliases(),
      preferred_cli_env: ["checks.test": :test],
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {RideAlong.Application, []},
      extra_applications: [:logger, :runtime_tools]
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
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:req, "~> 0.4"},
      {:tzdata, "~> 1.1"},
      {:emqtt_failover, "~> 0.3.0"},
      {:tds, "~> 2.3"},
      {:calendar, "~> 1.0.0"},
      {:faker, "~> 0.18"},
      {:ueberauth_oidcc, "~> 0.4"},
      {:stream_data, "~> 1.0", only: :test},
      {:credo, "~> 1.7.7-rc", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:sobelow, "~> 0.13.0", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build", "phx.gen.cert"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind ride_along", "esbuild ride_along"],
      "assets.deploy": [
        "tailwind ride_along --minify",
        "esbuild ride_along --minify",
        "phx.digest"
      ],
      "checks.dev": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow -i Config.HTTPS --skip --exit",
        "dialyzer"
      ],
      "checks.test": ["test --cover"]
    ]
  end
end
