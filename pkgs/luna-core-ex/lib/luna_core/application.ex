defmodule LunaCore.Application do
  @moduledoc "Starts the LUNA core. The services come in the later port steps."
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: LunaCore.Supervisor)
  end
end
