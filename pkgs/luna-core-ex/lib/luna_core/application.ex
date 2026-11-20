defmodule LunaCore.Application do
  @moduledoc """
  Starts the LUNA core from the environment. The tests set start_services to
  false and start the parts that they need.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:luna_core, :start_services, true),
        do: LunaCore.Main.children(LunaCore.Config.load()),
        else: []

    # A crash of one part restarts that part only. The Matrix bot and the agent
    # wait 30 s and more between starts, as the Python unit did.
    Supervisor.start_link(children, strategy: :one_for_one, name: LunaCore.Supervisor, max_restarts: 10, max_seconds: 600)
  end
end
