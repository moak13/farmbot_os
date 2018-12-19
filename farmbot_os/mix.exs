defmodule Farmbot.OS.MixProject do
  use Mix.Project
  @target System.get_env("MIX_TARGET") || "host"
  @version Path.join([__DIR__, "..", "VERSION"]) |> File.read!() |> String.trim()
  @branch System.cmd("git", ~w"rev-parse --abbrev-ref HEAD") |> elem(0) |> String.trim()
  @commit System.cmd("git", ~w"rev-parse --verify HEAD") |> elem(0) |> String.trim()
  System.put_env("NERVES_FW_VCS_IDENTIFIER", @commit)
  System.put_env("NERVES_FW_MISC", @branch)
  @elixir_version Path.join([__DIR__, "..", "ELIXIR_VERSION"]) |> File.read!() |> String.trim()

  def project do
    [
      app: :farmbot_os,
      elixir: @elixir_version,
      target: @target,
      version: @version,
      branch: @branch,
      commig: @commit,
      archives: [nerves_bootstrap: "~> 1.0"],
      deps_path: "deps/#{@target}",
      build_path: "_build/#{@target}",
      lockfile: "mix.lock.#{@target}",
      start_permanent: Mix.env() == :prod,
      aliases: [loadconfig: [&bootstrap/1]],
      elixirc_paths: elixirc_paths(Mix.env(), @target),
      deps: deps()
    ]
  end

  # Starting nerves_bootstrap adds the required aliases to Mix.Project.config()
  # Aliases are only added if MIX_TARGET is set.
  def bootstrap(args) do
    Application.start(:nerves_bootstrap)
    Mix.Task.run("loadconfig", args)
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Farmbot.OS, []},
      extra_applications: [:logger, :runtime_tools, :eex],
      included_applications: [:farmbot_core, :farmbot_ext]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nerves, "~> 1.3", runtime: false},
      {:shoehorn, "~> 0.4"},

      {:farmbot_core, path: "../farmbot_core", env: Mix.env()},
      {:farmbot_ext, path: "../farmbot_ext", env: Mix.env()},
      {:logger_backend_sqlite, "~> 2.1"},
      {:dialyxir, "~> 1.0.0-rc.3", runtime: false, override: true},
      {:nerves_hub_cli, "~> 0.5", runtime: false}
    ] ++ deps(@target)
  end

  # Specify target specific dependencies
  defp deps("host"), do: [
    {:excoveralls, "~> 0.9", only: [:test]},
    {:ex_doc, "~> 0.19", only: [:dev], runtime: false},
  ]

  defp deps(target) do
    [
      # Configurator
      {:cowboy, "~> 2.5"},
      {:plug, "~> 1.6"},
      {:cors_plug, "~> 1.5"},
      {:phoenix_html, "~> 2.12"},

      # AMQP hacks
      {:jsx, "~> 2.9", override: true},
      {:ranch, "~> 1.6", override: true},
      {:ranch_proxy_protocol, "~> 2.1", override: true},
      # End hacks

      {:nerves_runtime, "~> 0.8"},
      {:nerves_network, "~> 0.3"},
      {:nerves_firmware, "~> 0.4"},
      {:nerves_time, "~> 0.2"},
      {:nerves_hub, "~> 0.2"},
      {:dhcp_server, "~> 0.6"},
      {:mdns, "~> 1.0"},
      {:nerves_firmware_ssh, "~> 0.3"},
      {:nerves_init_gadget, "~> 0.5", only: :dev},
      {:elixir_ale, "~> 1.1"},
    ] ++ system(target)
  end

  defp elixirc_paths(:test, "host") do
    ["./lib", "./platform/host", "./test/support"]
  end

  defp elixirc_paths(_, "host") do
    ["./lib", "./platform/host"]
  end

  defp elixirc_paths(_env, _target) do
    ["./lib", "./platform/target"]
  end

  defp system("rpi3"), do: [{:farmbot_system_rpi3, "1.5.1-farmbot.1", runtime: false}]
  defp system("rpi0"), do: [{:farmbot_system_rpi0, "1.5.1-farmbot.0", runtime: false}]
  defp system("rpi"), do: [{:farmbot_system_rpi, "1.5.1-farmbot.0", runtime: false}]
  defp system(target), do: Mix.raise("Unknown MIX_TARGET: #{target}")
end
