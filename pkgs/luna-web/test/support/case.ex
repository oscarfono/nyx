defmodule LunaWeb.Case do
  @moduledoc "Each test gets a database transaction. The transaction rolls back at the end."
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      @endpoint LunaWeb.Endpoint
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(LunaWeb.Repo)
  end
end
