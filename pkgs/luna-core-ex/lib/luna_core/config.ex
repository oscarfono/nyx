defmodule LunaCore.Config do
  @moduledoc """
  Reads the LUNA configuration from the environment and from the systemd
  credentials. The names are the same as for the Python core, so the unit
  in core.nix serves both.
  """

  @doc "The configuration map. Raises when a required setting is missing."
  def load(env \\ System.get_env()) do
    state_dir = Map.get(env, "LUNA_STATE_DIR", "/var/lib/luna")

    %{
      state_dir: state_dir,
      homeserver: required(env, "LUNA_HOMESERVER"),
      matrix_user: required(env, "LUNA_MATRIX_USER"),
      owner: required(env, "LUNA_OWNER"),
      owner_timezone: Map.get(env, "LUNA_OWNER_TIMEZONE", "Etc/UTC") |> zone(),
      brief_time: Map.get(env, "LUNA_BRIEF_TIME", "07:00") |> brief_time(),
      model: Map.get(env, "LUNA_MODEL", "claude-opus-5-5"),
      effort: Map.get(env, "LUNA_EFFORT", "medium"),
      anthropic_api_key: credential(env, "anthropic_api_key") || raise("LUNA: the setting anthropic_api_key is missing."),
      matrix_password: credential(env, "matrix_password") || raise("LUNA: the setting matrix_password is missing."),
      telegram_token: credential(env, "telegram_token"),
      telegram_chat_id: credential(env, "telegram_chat_id"),
      money_enabled: Map.get(env, "LUNA_MONEY", "0") == "1",
      api_socket: Map.get(env, "LUNA_API_SOCKET", "/run/luna-api/api.sock"),
      wise_json: Map.get(env, "LUNA_WISE", ~s({"mode": "off"})),
      wise_token: credential(env, "wise_api_token"),
      memory_dir: Path.join(state_dir, "memory"),
      approvals_dir: Path.join(state_dir, "approvals"),
      inbox_dir: Path.join(state_dir, "inbox"),
      audit_file: Path.join([state_dir, "audit", "audit.jsonl"]),
      payments_log: Path.join(state_dir, "payments.jsonl")
    }
  end

  defp required(env, name) do
    case Map.get(env, name) do
      value when value in [nil, ""] -> raise "LUNA: the setting #{name} is missing."
      value -> value
    end
  end

  # A secret from $CREDENTIALS_DIRECTORY, or from the environment for a local test.
  defp credential(env, name) do
    from_file =
      with dir when is_binary(dir) <- Map.get(env, "CREDENTIALS_DIRECTORY"),
           {:ok, text} <- File.read(Path.join(dir, name)) do
        String.trim(text)
      else
        _ -> nil
      end

    from_file || Map.get(env, "LUNA_" <> String.upcase(name))
  end

  # The Python core accepted "UTC". tz names it "Etc/UTC".
  defp zone("UTC"), do: "Etc/UTC"
  defp zone(name), do: name

  defp brief_time(text) do
    [h, m] = text |> String.split(":") |> Enum.map(&String.to_integer/1)
    Time.new!(h, m, 0)
  end
end
