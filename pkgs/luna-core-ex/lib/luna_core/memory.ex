defmodule LunaCore.Memory do
  @moduledoc """
  Reads, searches and appends to the org-mode memory in git.

  One GenServer runs each git operation in turn. Thus the chat and the
  morning brief cannot change the working copy at the same time.
  """
  use GenServer

  @allowed_suffixes [".org", ".journal"]
  @max_read_chars 200_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def files(server \\ __MODULE__), do: GenServer.call(server, :files)
  def read(server \\ __MODULE__, path), do: GenServer.call(server, {:read, path}, :timer.seconds(60))
  def search(server \\ __MODULE__, query, limit \\ 40), do: GenServer.call(server, {:search, query, limit}, :timer.seconds(60))
  def sync(server \\ __MODULE__), do: GenServer.call(server, :sync, :timer.seconds(60))

  def append(server \\ __MODULE__, path, heading, body, now),
    do: GenServer.call(server, {:append, path, heading, body, now}, :timer.seconds(60))

  @doc "Commits the files at the paths, then pushes. Does nothing when no file changed."
  def commit(server \\ __MODULE__, paths, message), do: GenServer.call(server, {:commit, paths, message}, :timer.seconds(60))

  @doc """
  Returns the absolute path for a path relative to the memory root, or an error.
  The path must stay in the root, must not touch .git, must not pass a symlink,
  and must end in .org or .journal.
  """
  def resolve(root, relative) do
    expanded = Path.expand(relative, root)

    cond do
      Path.type(relative) != :relative ->
        {:error, "Use a path that is relative to the memory root."}

      expanded != root and not String.starts_with?(expanded, root <> "/") ->
        {:error, "The path is outside the memory."}

      ".git" in Path.split(Path.relative_to(expanded, root)) or ".git" in Path.split(relative) ->
        {:error, "The path is outside the memory."}

      Path.extname(expanded) not in @allowed_suffixes ->
        {:error, "LUNA can open .org and .journal files only."}

      symlink_on_path?(root, expanded) ->
        {:error, "The path is outside the memory."}

      true ->
        {:ok, expanded}
    end
  end

  defp symlink_on_path?(root, path) do
    path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.scan(root, &Path.join(&2, &1))
    |> Enum.any?(fn p -> match?({:ok, %File.Stat{type: :symlink}}, File.lstat(p)) end)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       root: opts |> Keyword.fetch!(:root) |> Path.expand(),
       audit: Keyword.fetch!(opts, :audit),
       remote: Keyword.get(opts, :remote, true)
     }}
  end

  @impl true
  def handle_call(:files, _from, s), do: {:reply, list_files(s), s}
  def handle_call(:sync, _from, s), do: {:reply, do_sync(s), s}

  def handle_call({:read, relative}, _from, s) do
    reply =
      with :ok <- do_sync(s),
           {:ok, path} <- resolve(s.root, relative),
           {:ok, text} <- read_file(path, relative) do
        if String.length(text) > @max_read_chars,
          do: {:ok, String.slice(text, 0, @max_read_chars) <> "\n[LUNA: the file is longer. The text stops here.]"},
          else: {:ok, text}
      end

    {:reply, reply, s}
  end

  def handle_call({:search, query, limit}, _from, s) do
    reply =
      with :ok <- do_sync(s) do
        needle = String.downcase(query)

        hits =
          list_files(s)
          |> Stream.flat_map(fn rel ->
            Path.join(s.root, rel)
            |> File.read!()
            |> String.split("\n")
            |> Stream.with_index(1)
            |> Stream.filter(fn {line, _} -> String.contains?(String.downcase(line), needle) end)
            |> Stream.map(fn {line, n} -> "#{rel}:#{n}: #{String.trim(line)}" end)
          end)
          |> Enum.take(limit)

        {:ok, hits}
      end

    {:reply, reply, s}
  end

  def handle_call({:append, relative, heading, body, now}, _from, s) do
    reply =
      with :ok <- do_sync(s),
           {:ok, path} <- resolve(s.root, relative) do
        File.mkdir_p!(Path.dirname(path))
        stamp = Calendar.strftime(now, "[%Y-%m-%d %a %H:%M]")
        title = heading |> String.replace("\n", " ") |> String.trim()
        File.write!(path, "\n* #{title}\n:PROPERTIES:\n:CREATED: #{stamp}\n:END:\n#{String.trim_trailing(body)}\n", [:append])
        rel = Path.relative_to(path, s.root)

        with {:ok, _} <- git(s, ["add", "--", rel]),
             {:ok, _} <- git(s, ["commit", "--quiet", "-m", "LUNA: add '#{title}' to #{rel}"]),
             :ok <- push(s) do
          LunaCore.Audit.write(s.audit, "memory.append", %{file: rel, heading: title})
          {:ok, "Added '#{title}' to #{rel}."}
        end
      end

    {:reply, reply, s}
  end

  def handle_call({:commit, paths, message}, _from, s) do
    reply =
      with {:ok, _} <- git(s, ["add", "--" | paths]),
           {:ok, status} <- git(s, ["status", "--porcelain", "--" | paths]) do
        if String.trim(status) == "" do
          :ok
        else
          with {:ok, _} <- git(s, ["commit", "--quiet", "-m", message, "--" | paths]), do: push(s)
        end
      end

    {:reply, reply, s}
  end

  defp list_files(s) do
    Path.wildcard(Path.join(s.root, "**/*"))
    |> Enum.filter(&(Path.extname(&1) in @allowed_suffixes))
    |> Enum.map(&Path.relative_to(&1, s.root))
    |> Enum.reject(&(".git" in Path.split(&1)))
    |> Enum.sort()
  end

  defp read_file(path, relative) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, :enoent} -> {:error, "The file #{relative} does not exist."}
      {:error, reason} -> {:error, "LUNA cannot read #{relative}: #{reason}"}
    end
  end

  defp do_sync(%{remote: false}), do: :ok
  defp do_sync(s), do: with({:ok, _} <- git(s, ["pull", "--rebase", "--quiet"]), do: :ok)

  defp push(%{remote: false}), do: :ok
  defp push(s), do: with({:ok, _} <- git(s, ["push", "--quiet", "origin", "HEAD:main"]), do: :ok)

  defp git(s, [command | _] = args) do
    case System.cmd("git", ["-C", s.root | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, "git #{command} failed: #{String.trim(out)}"}
    end
  end
end
