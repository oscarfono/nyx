import Config

config :logger, :default_formatter, format: "[$level] $message\n"

# The tests start no service. Each test starts the parts that it needs.
config :luna_core, start_services: config_env() != :test

if config_env() == :test do
  config :logger, level: :warning
end
