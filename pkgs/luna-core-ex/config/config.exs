import Config

config :logger, :default_formatter, format: "[$level] $message\n"

# The owner time zone. tz bundles the IANA data and does not fetch updates.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# The tests start no service. Each test starts the parts that it needs.
config :luna_core, start_services: config_env() != :test

if config_env() == :test do
  config :logger, level: :warning
end
