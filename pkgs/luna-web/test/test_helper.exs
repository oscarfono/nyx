:ok = LunaWeb.FakeCore.start()
:ok = LunaWeb.FakeWyoming.start()
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(LunaWeb.Repo, :manual)
