defmodule LunaCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :luna_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [luna_core: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [mod: {LunaCore.Application, []}, extra_applications: [:logger, :crypto]]
  end

  # No dependency is for one environment only, so one fetchMixDeps hash
  # serves the release and the tests.
  defp deps do
    [
      {:bandit, "~> 1.15"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.18"},
      {:req, "~> 0.7"},
      {:tz, "~> 0.28"}
    ]
  end
end
