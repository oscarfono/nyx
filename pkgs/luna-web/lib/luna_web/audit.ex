defmodule LunaWeb.Audit do
  @moduledoc """
  Writes events to the table audit_events.
  A trigger in the database refuses UPDATE, DELETE and TRUNCATE on that table.
  """
  require Logger

  @doc "Writes one event. A database fault goes to the log. The request continues."
  def write(event, data \\ %{}) when is_binary(event) and is_map(data) do
    LunaWeb.Repo.query!("INSERT INTO audit_events (event, data) VALUES ($1, $2)", [event, data])
    :ok
  rescue
    error ->
      Logger.error("LUNA: the audit log did not write #{event}: #{Exception.message(error)}")
      :error
  end
end
