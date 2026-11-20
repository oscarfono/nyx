import Config

# The systemd unit sets these values. Refer to modules/luna/web.nix.
if config_env() == :prod do
  env = fn name ->
    case System.get_env(name) do
      value when value in [nil, ""] -> raise "LUNA: set the environment variable #{name}."
      value -> value
    end
  end

  origin = env.("LUNA_WEB_ORIGIN")
  uri = URI.parse(origin)

  config :luna_web, :owner_login, env.("LUNA_OWNER_LOGIN")
  config :luna_web, :core_socket, env.("LUNA_CORE_SOCKET")
  config :luna_web, :voice, stt: env.("LUNA_STT_URI"), tts: env.("LUNA_TTS_URI")

  config :luna_web, LunaWeb.Endpoint,
    server: true,
    url: [scheme: uri.scheme, host: uri.host, port: uri.port],
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(env.("LUNA_WEB_PORT"))],
    check_origin: [origin],
    secret_key_base: env.("LUNA_WEB_SECRET_FILE") |> File.read!() |> String.trim()

  config :luna_web, LunaWeb.Repo,
    socket_dir: env.("LUNA_DB_SOCKET_DIR"),
    username: env.("LUNA_DB_USER"),
    database: env.("LUNA_DB_NAME"),
    pool_size: 5
end
