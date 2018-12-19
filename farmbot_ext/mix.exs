defmodule Farmbot.Ext.MixProject do
  use Mix.Project
  @version Path.join([__DIR__, "..", "VERSION"]) |> File.read!() |> String.trim()
  @elixir_version Path.join([__DIR__, "..", "ELIXIR_VERSION"]) |> File.read!() |> String.trim()

  def project do
    [
      app: :farmbot_ext,
      version: @version,
      elixir: @elixir_version,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: ["lib", "vendor"],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Farmbot.Ext, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:farmbot_core, path: "../farmbot_core", env: Mix.env()},
      {:ranch, "~> 1.5", override: true},
      {:ranch_proxy_protocol, "~> 2.0", override: true},
      {:tesla, "~> 1.2"},
      {:hackney, "~> 1.14"},
      {:uuid, "~> 1.1"},
      {:amqp, "~> 1.0"},
      {:excoveralls, "~> 0.10", only: [:test]},
      {:dialyxir, "~> 1.0.0-rc.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.19", only: [:docs], runtime: false}
    ]
  end
end
