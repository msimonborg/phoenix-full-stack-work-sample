defmodule FlyWeb.AppLive.Helpers do
  @moduledoc """
  Convenience functions for AppLive live views.
  """

  use Phoenix.Component
  use Timex

  def config(session) do
    Fly.Client.config(access_token: session["auth_token"] || System.get_env("FLYIO_ACCESS_TOKEN"))
  end

  def format_uptime(deploy_time) when is_struct(deploy_time, NaiveDateTime) do
    {h, m, s, _} =
      NaiveDateTime.utc_now()
      |> Timex.diff(deploy_time, :duration)
      |> Timex.Duration.to_clock()

    "#{h}h #{m}m #{s}s"
  end

  def format_uptime(deploy_time) do
    deploy_time
    |> NaiveDateTime.from_iso8601!()
    |> format_uptime()
  end

  def status_bg_color(app) do
    case app["status"] do
      "running" -> "bg-green-100"
      "successful" -> "bg-green-100"
      "dead" -> "bg-red-100"
      _ -> "bg-yellow-100"
    end
  end

  def status_text_color(app) do
    case app["status"] do
      "running" -> "text-green-800"
      "successful" -> "text-green-800"
      "dead" -> "text-red-800"
      _ -> "text-yellow-800"
    end
  end

  def preview_url(app) do
    "https://#{app["name"]}.fly.dev"
  end

  def regions(app) do
    Enum.map(app["regions"], fn region ->
      region["code"]
    end)
    |> Enum.join(", ")
  end

  def health_checks(%{deployment_status: status} = assigns) do
    assigns =
      assign(assigns,
        desired: status["desiredCount"],
        placed: status["placedCount"],
        healthy: status["healthyCount"],
        unhealthy: status["unhealthyCount"]
      )

    ~H"""
    <%= @desired %> desired, <%= @placed %> placed,
    <span class="text-green-800"><%= @healthy %> healthy</span>,
    <span class="text-red-800"><%= @unhealthy %> unhealthy</span>
    """
  end

  def health_checks(%{allocation: alloc} = assigns) do
    assigns =
      assign(assigns,
        total: alloc["totalCheckCount"],
        passing: alloc["passingCheckCount"],
        warning: alloc["warningCheckCount"],
        critical: alloc["criticalCheckCount"]
      )

    ~H"""
    <%= @total %> total, <%= @passing %> passing
    <%= if @warning > 0 do %>
      , <span class="text-yellow-800"><%= @warning %> warning</span>
    <% end %>
    <%= if @critical > 0 do %>
      , <span class="text-red-800"><%= @critical %> critical</span>
    <% end %>
    """
  end
end
