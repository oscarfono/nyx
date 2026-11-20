defmodule LunaWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :luna_web,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [test: ["ecto.create --quiet", "test"]],
      releases: [luna_web: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [mod: {LunaWeb.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # No dependency is for one environment only. Then one fetchMixDeps hash
  # serves the release and the tests.
  defp deps do
    [
      {:bandit, "~> 1.15"},
      {:ecto_sql, "~> 3.14"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.4"},
      {:phoenix_live_view, "~> 1.2"},
      {:postgrex, "~> 0.22"},
      {:req, "~> 0.7"}
    ]
  end
end
