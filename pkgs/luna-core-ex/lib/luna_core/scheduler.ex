defmodule LunaCore.Scheduler do
  @moduledoc """
  The scheduled jobs: the morning brief and the memory sync.
  Each job is a GenServer. A failure goes to the audit log, and the job
  goes on. The Wise watcher comes with the money port (step 7).
  """

  @brief_prompt """
  Write the morning brief for today. First read roster.org, money.org,
  projects.org and travel.org. Then give, in this order and in less than 200 words:
  1. Where Coops is in the roster, and the days to the next change.
  2. Money: the safe-to-spend number and any cost due in the next 14 days.
  3. The SHIP project: one next step for today.
  4. One action for the next off-swing, if the next off-swing is in 30 days or less.
  If a file has no data yet, say which data you need. Write the brief to
  briefs/<YYYY>.org with the heading "Brief <YYYY-MM-DD>".
  """

  def brief_prompt, do: @brief_prompt

  @doc "The next time at the hour and minute, in the zone of now. Today if it is still to come."
  def next_run(%DateTime{} = now, %Time{} = at) do
    today = at_time(DateTime.to_date(now), at, now.time_zone)

    if DateTime.compare(today, now) == :gt,
      do: today,
      else: at_time(Date.add(DateTime.to_date(now), 1), at, now.time_zone)
  end

  defp at_time(date, at, zone) do
    case DateTime.new(date, Time.new!(at.hour, at.minute, 0), zone) do
      {:ok, dt} -> dt
      # A daylight-saving change: take the first valid time.
      {:ambiguous, first, _} -> first
      {:gap, _, after_gap} -> after_gap
    end
  end

  @doc """
  The text of the brief. The system notice comes first. On Monday, the money
  summary comes last: code makes those numbers, not the model.
  """
  def compose(text, notice, money_summary) do
    [notice, text, money_summary] |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
  end

  defmodule Brief do
    @moduledoc """
    The morning brief. Options: :at (Time), :zone, :audit, and functions:
    :ask (prompt -> text, in a fresh conversation), :send (text -> any),
    :notice (date -> nil or text), :money (nil, or a function -> text).
    """
    use GenServer

    alias LunaCore.{Audit, Scheduler}

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

    @doc "Runs the brief now, in the process of the caller. For tests and for a manual run."
    def run_once(opts) do
      now = DateTime.now!(Keyword.get(opts, :zone, "Etc/UTC"))
      text = Keyword.fetch!(opts, :ask).(Scheduler.brief_prompt())
      notice = Keyword.get(opts, :notice, fn _ -> nil end).(DateTime.to_date(now))
      money = Keyword.get(opts, :money)
      summary = if money != nil and Date.day_of_week(now) == 1, do: money.(), else: nil
      Keyword.fetch!(opts, :send).(Scheduler.compose(text, notice, summary))
      Audit.write(Keyword.fetch!(opts, :audit), "brief.sent")
      :ok
    rescue
      error ->
        Audit.write(Keyword.fetch!(opts, :audit), "brief.error", %{error: Exception.message(error)})
        :error
    end

    @impl true
    def init(opts), do: {:ok, schedule(opts)}

    @impl true
    def handle_info(:run, opts) do
      # The brief can take minutes. It runs in a task, so a crash cannot stop the job.
      Task.start(fn -> run_once(opts) end)
      {:noreply, schedule(opts)}
    end

    defp schedule(opts) do
      now = DateTime.now!(Keyword.get(opts, :zone, "Etc/UTC"))
      next = Scheduler.next_run(now, Keyword.fetch!(opts, :at))
      # One minute more, so that a clock that runs early cannot run the brief twice.
      Process.send_after(self(), :run, DateTime.diff(next, now, :millisecond) + 60_000)
      opts
    end
  end

  defmodule Sync do
    @moduledoc "Pulls the memory hub into the working copy, each five minutes. Options: :memory, :audit, :every (ms)."
    use GenServer

    alias LunaCore.{Audit, Memory}

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

    def run_once(opts) do
      case Memory.sync(Keyword.fetch!(opts, :memory)) do
        :ok -> :ok
        {:error, message} -> Audit.write(Keyword.fetch!(opts, :audit), "memory.sync_error", %{error: message})
      end
    end

    @impl true
    def init(opts) do
      Process.send_after(self(), :run, Keyword.get(opts, :every, :timer.minutes(5)))
      {:ok, opts}
    end

    @impl true
    def handle_info(:run, opts) do
      run_once(opts)
      Process.send_after(self(), :run, Keyword.get(opts, :every, :timer.minutes(5)))
      {:noreply, opts}
    end
  end
end
