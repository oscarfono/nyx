defmodule LunaCore.Approvals do
  @moduledoc """
  Holds tier 2 actions until the owner approves them.

  A tier 2 tool calls request/4. The request goes to disk.
  Only the bot and the core API call approve/2 or deny/2, when the owner acts.
  The model has no path to approve/2 or deny/2.

  The GenServer takes each request from disk before its executor runs.
  Thus two approvals of one request cannot run the executor twice.
  """
  use GenServer

  @ttl_seconds 24 * 60 * 60

  defmodule Request do
    @moduledoc false
    defstruct [:id, :action, :params, :summary, :created]
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "Registers the executor of an action. The executor takes the params and returns text."
  def register(server \\ __MODULE__, action, executor) when is_function(executor, 1),
    do: GenServer.call(server, {:register, action, executor})

  @doc "Adds a function that gets each new request, for example to send a Matrix message."
  def notify(server \\ __MODULE__, fun) when is_function(fun, 1), do: GenServer.call(server, {:notify, fun})

  def request(server \\ __MODULE__, action, params, summary) do
    case GenServer.call(server, {:request, action, params, summary}) do
      {:ok, item, notifiers} ->
        Enum.each(notifiers, & &1.(item))
        {:ok, item}

      error ->
        error
    end
  end

  def get(server \\ __MODULE__, id), do: GenServer.call(server, {:get, id})
  def pending(server \\ __MODULE__), do: GenServer.call(server, :pending)

  @doc "Approves a request and runs its executor in the process of the caller."
  def approve(server \\ __MODULE__, id) do
    case GenServer.call(server, {:take, id}) do
      {:error, :none} ->
        "There is no request #{id}."

      {:ok, item, executor, audit} ->
        if expired?(item) do
          LunaCore.Audit.write(audit, "approval.expired", %{id: item.id, action: item.action})
          "The request #{item.id} expired. Ask LUNA again."
        else
          LunaCore.Audit.write(audit, "approval.approved", %{id: item.id, action: item.action})
          run(executor, item, audit)
        end
    end
  end

  def deny(server \\ __MODULE__, id) do
    case GenServer.call(server, {:take, id}) do
      {:error, :none} ->
        "There is no request #{id}."

      {:ok, item, _executor, audit} ->
        LunaCore.Audit.write(audit, "approval.denied", %{id: item.id, action: item.action})
        "Denied: #{item.summary}"
    end
  end

  # The owner must see each failure.
  defp run(executor, item, audit) do
    result = executor.(item.params)
    LunaCore.Audit.write(audit, "approval.done", %{id: item.id, action: item.action, result: result})
    result
  rescue
    error ->
      LunaCore.Audit.write(audit, "approval.failed", %{id: item.id, action: item.action, error: inspect(error)})
      "The action #{item.action} failed: #{Exception.message(error)}"
  end

  defp expired?(item) do
    {:ok, created, _} = DateTime.from_iso8601(item.created)
    DateTime.diff(DateTime.utc_now(), created) > @ttl_seconds
  end

  @impl true
  def init(opts) do
    {:ok, %{dir: Keyword.fetch!(opts, :dir), audit: Keyword.fetch!(opts, :audit), executors: %{}, notifiers: []}}
  end

  @impl true
  def handle_call({:register, action, executor}, _from, state),
    do: {:reply, :ok, put_in(state.executors[action], executor)}

  def handle_call({:notify, fun}, _from, state), do: {:reply, :ok, %{state | notifiers: state.notifiers ++ [fun]}}

  def handle_call({:request, action, params, summary}, _from, state) do
    if Map.has_key?(state.executors, action) do
      item = %Request{
        id: :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower),
        action: action,
        params: params,
        summary: summary,
        created: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      File.write!(path(state, item.id), item |> Map.from_struct() |> Jason.encode!())
      LunaCore.Audit.write(state.audit, "approval.requested", %{id: item.id, action: action, params: params})
      {:reply, {:ok, item, state.notifiers}, state}
    else
      {:reply, {:error, "No executor for the action #{action}."}, state}
    end
  end

  def handle_call({:get, id}, _from, state), do: {:reply, read(state, id), state}

  def handle_call(:pending, _from, state) do
    items =
      Path.wildcard(Path.join(state.dir, "*.json"))
      |> Enum.map(&decode(File.read!(&1)))
      |> Enum.sort_by(& &1.created)

    {:reply, items, state}
  end

  def handle_call({:take, id}, _from, state) do
    case read(state, id) do
      nil ->
        {:reply, {:error, :none}, state}

      item ->
        File.rm!(path(state, item.id))
        {:reply, {:ok, item, Map.get(state.executors, item.action), state.audit}, state}
    end
  end

  defp read(state, id) do
    with true <- valid_id?(id),
         {:ok, text} <- File.read(path(state, id)) do
      decode(text)
    else
      _ -> nil
    end
  end

  defp valid_id?(id), do: is_binary(id) and Regex.match?(~r/\A[[:alnum:]]+\z/, id)
  defp path(state, id), do: Path.join(state.dir, id <> ".json")

  defp decode(text) do
    map = Jason.decode!(text)
    %Request{id: map["id"], action: map["action"], params: map["params"], summary: map["summary"], created: map["created"]}
  end
end
