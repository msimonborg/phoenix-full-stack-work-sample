defmodule FlyWeb.AppLive.Index do
  use FlyWeb, :live_view

  import FlyWeb.AppLive.Helpers

  require Logger

  alias Fly.Client
  alias FlyWeb.Components.HeaderBreadcrumbs

  @impl true
  def mount(_params, session, socket) do
    socket =
      assign(socket,
        config: config(session),
        state: :loading,
        apps: [],
        authenticated: true
      )

    # Only make the API call if the websocket is setup. Not on initial render.
    if connected?(socket) do
      {:ok, fetch_apps(socket)}
    else
      {:ok, socket}
    end
  end

  defp fetch_apps(socket) do
    case Client.fetch_apps(socket.assigns.config) do
      {:ok, apps} ->
        assign(socket, :apps, apps)

      {:error, :unauthorized} ->
        put_flash(socket, :error, "Not authenticated")

      {:error, reason} ->
        Logger.error("Failed to load apps. Reason: #{inspect(reason)}")

        put_flash(socket, :error, reason)
    end
  end
end
