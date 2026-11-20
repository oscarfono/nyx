defmodule LunaCore.Audit do
  @moduledoc """
  Writes one JSON line for each event to the append-only audit log.
  The file has the attribute +a, so the core can only add lines.
  """

  @doc "Writes one event. The keys are in sorted order, as in the Python core."
  def write(path, event, fields \\ %{}) when is_binary(event) do
    record =
      fields
      |> Map.new(fn {k, v} -> {to_string(k), json_safe(v)} end)
      |> Map.merge(%{"time" => DateTime.utc_now() |> DateTime.to_iso8601(), "event" => event})
      |> Enum.sort()
      |> Jason.OrderedObject.new()

    line = Jason.encode!(record) <> "\n"
    {:ok, file} = File.open(path, [:append, :binary])

    try do
      :ok = IO.binwrite(file, line)
      :ok = :file.datasync(file)
    after
      File.close(file)
    end
  end

  # The Python core wrote str() of a value that JSON cannot hold.
  defp json_safe(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp json_safe(v) when is_atom(v), do: Atom.to_string(v)
  defp json_safe(v) when is_list(v), do: Enum.map(v, &json_safe/1)
  defp json_safe(%{__struct__: _} = v), do: inspect(v)
  defp json_safe(v) when is_map(v), do: Map.new(v, fn {k, x} -> {to_string(k), json_safe(x)} end)
  defp json_safe(v), do: inspect(v)
end
