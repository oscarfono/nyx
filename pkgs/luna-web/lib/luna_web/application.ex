defmodule LunaWeb.Application do
  @moduledoc "Starts the database pool, the migrations and the web endpoint."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LunaWeb.Repo,
      # Run the migrations before the endpoint accepts a request.
      {Ecto.Migrator, repos: Application.fetch_env!(:luna_web, :ecto_repos)},
      {Phoenix.PubSub, name: LunaWeb.PubSub},
      LunaWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LunaWeb.Supervisor)
  end
end
