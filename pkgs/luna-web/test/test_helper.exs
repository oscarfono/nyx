:ok = LunaWeb.FakeCore.start()
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(LunaWeb.Repo, :manual)
