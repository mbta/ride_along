defmodule RideAlong.MixProject do
  use Mix.Project

  def project do
    [
      app: :ride_along,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        tool: ExCoveralls
      ],
      aliases: aliases(),
      preferred_cli_env: [
        "checks.test": :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test
      ],
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {RideAlong.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
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
      {:bandit, "~> 1.2"},
      {:calendar, "~> 1.0.0"},
      {:cachex, "~> 4.0"},
      {:credo, "~> 1.7.7-rc", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:dns_cluster, "~> 0.1.1"},
      {:ehmon, github: "paulswartz/ehmon"},
      {:emqtt_failover, "~> 0.3.0"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:excoveralls, "~> 0.18.3", only: :test},
      {:exgboost, "~> 0.5"},
      {:explorer, "~> 0.9"},
      {:faker, "~> 0.18"},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.20"},
      # https://github.com/tailwindlabs/heroicons/releases
      {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false},
      {:jason, "~> 1.2"},
      {:jsonapi, "~> 1.8"},
      {:lasso, "~> 0.1", only: :test},
      {:logster, "~> 2.0-rc"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:polyline, "~> 1.4"},
      {:req, "~> 0.4"},
      {:sobelow, "~> 0.13.0", only: :dev, runtime: false},
      {:stream_data, "~> 1.0", only: :test},
      {:styler, "~> 1.2"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:tds, "~> 2.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:tzdata, "~> 1.1"},
      {:ueberauth_oidcc, "~> 0.4"},
      {:vincenty, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    sentry_dsn_define =
      if (sentry_dsn = System.get_env("SENTRY_DSN", "")) == "" do
        "--define:SENTRY_DSN=false"
      else
        "--define:SENTRY_DSN='\"#{sentry_dsn}\"'"
      end

    [
      setup: ["deps.get", "assets.setup", "assets.build", "phx.gen.cert"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind ride_along", "esbuild ride_along #{sentry_dsn_define}"],
      "assets.deploy": [
        "tailwind ride_along --minify",
        "esbuild ride_along --minify #{sentry_dsn_define}",
        "phx.digest"
      ],
      "checks.dev": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow -i Config.HTTPS,Config.Headers --skip --exit",
        "dialyzer"
      ],
      "checks.test": ["test --cover"]
    ]
  end
end
