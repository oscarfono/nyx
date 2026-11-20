defmodule LunaWeb.Repo do
  @moduledoc "The PostgreSQL database. The connection uses the unix socket and peer authentication."
  use Ecto.Repo, otp_app: :luna_web, adapter: Ecto.Adapters.Postgres
end
