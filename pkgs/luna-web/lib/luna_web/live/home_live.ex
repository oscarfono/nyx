defmodule LunaWeb.HomeLive do
  @moduledoc """
  The stage E1 page. The page shows the login, the socket and the database.
  The panels come in stage E2. Until then, the Python app is at port 8444.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: LunaWeb.Audit.write("web.connect")
    {:ok, assign(socket, connected: connected?(socket), database: database())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>LUNA</h1>
      <dl>
        <dt>Login</dt>
        <dd>{@owner_login}</dd>
        <dt>Live socket</dt>
        <dd id="socket">{if @connected, do: "connected", else: "not connected"}</dd>
        <dt>Database</dt>
        <dd id="database">{@database}</dd>
      </dl>
      <p>This is stage E1. The panels come in stage E2.</p>
      <p>The Python panels are at port 8444 until then.</p>
    </main>
    """
  end

  defp database do
    case LunaWeb.Repo.query("SHOW server_version") do
      {:ok, %{rows: [[version]]}} -> "PostgreSQL #{version}"
      {:error, _} -> "not available"
    end
  end
end
