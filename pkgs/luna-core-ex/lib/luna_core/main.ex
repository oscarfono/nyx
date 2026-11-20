defmodule LunaCore.Main do
  @moduledoc """
  The supervision tree of the LUNA core: the same parts as main.py of the
  Python core. children/1 is a pure function of the configuration, so a test
  can start the whole core against fake services.
  """

  alias LunaCore.{Agent, Api, Approvals, Audit, Matrix, Memory, Money, Payments, Scheduler, Sysinfo, Telegram, Tools}

  def children(config) do
    audit = config.audit_file
    zone = config.owner_timezone
    today = fn -> DateTime.now!(zone) |> DateTime.to_date() end
    wise = Payments.settings(config.wise_json)
    nudge = fn text -> Telegram.nudge(config.telegram_token, config.telegram_chat_id, text, audit) end

    money =
      if config.money_enabled,
        do: %{root: config.memory_dir, memory: Memory, inbox: config.inbox_dir, audit: audit, today: today},
        else: nil

    payments =
      if wise.mode != "off" do
        %{settings: wise, log: config.payments_log, audit: audit, today: today, now: &DateTime.utc_now/0,
          # In draft mode, LUNA tells the owner in Matrix about each draft.
          notify: fn text -> Matrix.Bot.send_owner(text) end,
          wise: if(config.wise_token, do: [token: config.wise_token] ++ Map.get(config, :wise_opts, []), else: nil)}
      end

    agent_opts = [
      api_key: config.anthropic_api_key, model: config.model, effort: config.effort, zone: zone, audit: audit
    ] ++ Map.get(config, :agent_opts, [])

    base_tools = Tools.memory_tools(Memory, audit, fn -> DateTime.now!(zone) end)
    money_tools = if money, do: Money.tools(money), else: []

    [
      {Memory, root: config.memory_dir, audit: audit, remote: Map.get(config, :remote, true)},
      {Approvals, dir: config.approvals_dir, audit: audit},
      # The chat agent gets the payment tool after the approvals start. Refer to init_payments/1.
      {Agent, agent_opts ++ [tools: base_tools ++ money_tools]},
      Supervisor.child_spec({Task, fn -> init_payments(payments) end}, id: :init_payments),
      {Api,
       socket: config.api_socket,
       core: [
         agent: {Agent, Agent},
         approvals: Approvals,
         audit: audit,
         money: if(money, do: {Money, money}, else: nil),
         settings: %{model: config.model, money: config.money_enabled, wise_mode: wise.mode, wise_sandbox: wise.sandbox},
         memory_root: config.memory_dir,
         started: DateTime.utc_now()
       ]},
      {Matrix.Bot,
       homeserver: config.homeserver, user: config.matrix_user, owner: config.owner, password: config.matrix_password,
       state_dir: config.state_dir, audit: audit, agent: {Agent, Agent}, approvals: Approvals, nudge: nudge},
      {Scheduler.Brief,
       at: config.brief_time, zone: zone, audit: audit,
       # A fresh agent with no payment tool: a scheduled job cannot ask for a
       # tier 2 action when no human is present (backlog #10).
       ask: fn prompt -> brief_ask(agent_opts ++ [tools: base_tools ++ money_tools], prompt) end,
       send: &Matrix.Bot.send_owner/1,
       notice: &Sysinfo.update_notice/1,
       money: if(money, do: fn -> Money.summary(money) end, else: nil)},
      {Scheduler.Sync, memory: Memory, audit: audit}
    ] ++
      if(payments && wise.mode == "draft", do: [{Scheduler.Watch, payments: payments, audit: audit}], else: []) ++
      [Supervisor.child_spec({Task, fn -> Audit.write(audit, "luna.start", %{model: config.model, core: "elixir"}) end}, id: :start_event)]
  end

  defp init_payments(nil), do: :ok

  defp init_payments(payments) do
    Agent.add_tools(Agent, Payments.tools(payments, Approvals))
    Audit.write(payments.audit, "payments.ready", %{mode: payments.settings.mode, sandbox: payments.settings.sandbox,
                                                     payees: payments.settings.payees |> Map.keys() |> Enum.sort()})
  end

  defp brief_ask(opts, prompt) do
    {:ok, pid} = Agent.start_link(Keyword.put(opts, :name, nil))

    try do
      Agent.ask(pid, prompt)
    after
      GenServer.stop(pid)
    end
  end
end
