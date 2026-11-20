defmodule LunaWeb.ErrorHTML do
  @moduledoc "Error pages as plain text. An error page shows no internal data."
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
