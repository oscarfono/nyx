import Config

config :luna_web, ecto_repos: [LunaWeb.Repo]

config :luna_web, LunaWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: LunaWeb.ErrorHTML], layout: false],
  pubsub_server: LunaWeb.PubSub,
  live_view: [signing_salt: "luna-live"]

config :phoenix, :json_library, Jason

config :logger, :default_formatter, format: "[$level] $message\n"

if config_env() == :test do
  config :luna_web, :owner_login, "owner@example.com"

  config :luna_web, LunaWeb.Endpoint,
    url: [scheme: "https", host: "luna.example.ts.net", port: 8443],
    check_origin: ["https://luna.example.ts.net:8443"],
    secret_key_base: String.duplicate("test", 16),
    server: false

  # The check starts a PostgreSQL server in the build directory.
  config :luna_web, LunaWeb.Repo,
    socket_dir: System.get_env("PGHOST"),
    username: System.get_env("PGUSER", "postgres"),
    database: "luna_web_test",
    pool: Ecto.Adapters.SQL.Sandbox

  config :logger, level: :warning
end
