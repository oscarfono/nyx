defmodule LunaWeb.Core do
  @moduledoc """
  The client of the core API. Refer to "Build: the core API" in LUNA.org.

  The core API is JSON over HTTP on a unix socket. Each function returns
  {:ok, value} or {:error, message}. The message is for the owner.
  """

  @image_types ~w(image/jpeg image/png image/webp)
  @max_image_bytes 5 * 1024 * 1024
  # The agent can use tools for some minutes before it replies.
  @chat_timeout :timer.minutes(10)

  def history do
    with {:ok, %{"messages" => messages}} <- request(:get, "/api/history"), do: {:ok, messages}
  end

  @doc "Sends a message and an optional image. The image is checked before the request."
  def chat(text, image) when is_binary(text) do
    text = String.trim(text)

    with {:ok, image} <- check_image(image),
         :ok <- check_message(text, image),
         body = if(image, do: %{text: text, image: image}, else: %{text: text}),
         {:ok, %{"reply" => reply}} <-
           request(:post, "/api/chat", json: body, receive_timeout: @chat_timeout) do
      {:ok, reply}
    end
  end

  def approvals do
    with {:ok, %{"approvals" => items}} <- request(:get, "/api/approvals"), do: {:ok, items}
  end

  def decide(id, action) when action in ["approve", "deny"] do
    if Regex.match?(~r/\A[0-9a-f]{1,32}\z/, id) do
      with {:ok, %{"result" => result}} <-
             request(:post, "/api/approvals/#{id}/#{action}", json: %{}),
           do: {:ok, result}
    else
      {:error, "The request ID is not valid."}
    end
  end

  def decide(_id, _action), do: {:error, "Use approve or deny."}

  def money do
    with {:ok, %{"text" => text}} <- request(:get, "/api/money"), do: {:ok, text}
  end

  def system, do: request(:get, "/api/system")

  @doc "Checks an image from the page. nil is no image."
  def check_image(nil), do: {:ok, nil}

  def check_image(%{"media_type" => type, "data" => data})
      when type in @image_types and is_binary(data) do
    case Base.decode64(data) do
      {:ok, bytes} when byte_size(bytes) <= @max_image_bytes ->
        {:ok, %{"media_type" => type, "data" => data}}

      {:ok, _} ->
        {:error, "The image is more than 5 MB."}

      :error ->
        {:error, "The image data is not valid base64."}
    end
  end

  def check_image(_), do: {:error, "LUNA accepts JPEG, PNG or WebP images."}

  defp check_message("", nil), do: {:error, "Write a message."}
  defp check_message(_text, _image), do: :ok

  defp request(method, path, opts \\ []) do
    socket = Application.fetch_env!(:luna_web, :core_socket)

    opts =
      Keyword.merge(
        [method: method, url: "http://core" <> path, unix_socket: socket, retry: false],
        opts
      )

    case Req.request(opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{body: %{"error" => message}}} when is_binary(message) ->
        {:error, message}

      {:ok, %{status: status}} ->
        {:error, "The core replied with the status #{status}."}

      {:error, _} ->
        {:error, "The LUNA core is not available. Try again in some minutes."}
    end
  end
end
