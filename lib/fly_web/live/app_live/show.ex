defmodule FlyWeb.AppLive.Show do
  use FlyWeb, :live_view

  import FlyWeb.AppLive.Helpers

  require Logger

  alias Fly.Client
  alias FlyWeb.{Components, Components.HeaderBreadcrumbs}

  @impl true
  def mount(%{"name" => name}, session, socket) do
    config = config(session)

    socket =
      assign(socket,
        config: config,
        loading: true,
        app: nil,
        app_name: name,
        authenticated: true,
        refreshing: false,
        restarting: []
      )

    # Only make the API call if the websocket is setup. Not on initial render.
    if connected?(socket) do
      schedule_refresh()

      vm_options =
        Task.async(fn ->
          {:ok, options} = Client.fetch_template_options(%{}, config)
          Client.TemplateOptions.vm_options(options)
        end)

      app = Task.async(fn -> Client.fetch_app(name, config) end)

      {:ok,
       socket
       |> assign_app(Task.await(app))
       |> paused?()
       |> assign(:loading, false)
       |> assign_vm_sizes()
       |> assign_vm_counts()
       |> assign(:vm_options, Task.await(vm_options))}
    else
      {:ok, socket}
    end
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, 5_000)

  defp assign_app(socket, app_response) do
    case app_response do
      {:ok, app} ->
        assign(socket, app: app, uptimes: calculate_uptimes(app))

      {:error, :unauthorized} ->
        put_flash(socket, :error, "Not authenticated")

      {:error, reason} ->
        Logger.error(
          "Failed to load app '#{inspect(socket.assigns.app_name)}'. Reason: #{inspect(reason)}"
        )

        put_flash(socket, :error, reason)
    end
  end

  defp calculate_uptimes(app) do
    uptimes =
      Enum.reduce(app["allocations"], %{}, fn alloc, acc ->
        Map.put(acc, alloc["id"], format_uptime(alloc["createdAt"]))
      end)

    Enum.reduce(app["releases"]["nodes"], uptimes, fn release, acc ->
      Map.put(acc, release["id"], format_uptime(release["createdAt"]))
    end)
  end

  defp paused?(%{assigns: assigns} = socket) do
    paused = if assigns.app["status"] == "running", do: false, else: true
    assign(socket, :paused, paused)
  end

  defp assign_vm_sizes(socket) do
    vm_sizes =
      Enum.reduce(socket.assigns.app["processGroups"], %{}, fn pg, acc ->
        vm_size_name = pg["vmSize"]["name"]
        mem = pg["vmSize"]["memoryMb"]
        size = "#{vm_size_name}@#{mem}"
        Map.put(acc, pg["name"], size)
      end)

    assign(socket, :vm_sizes, vm_sizes)
  end

  defp assign_vm_counts(socket) do
    vm_counts =
      Enum.reduce(socket.assigns.app["taskGroupCounts"], %{}, fn group_count, acc ->
        Map.put(acc, group_count["name"], to_string(group_count["count"]))
      end)

    assign(socket, :vm_counts, vm_counts)
  end

  @impl true
  def handle_event("pause_app", %{"pause_app" => params}, %{assigns: assigns} = socket) do
    %{config: config, app: app} = assigns
    app_id = app["id"]

    socket =
      case params["pause"] do
        "true" ->
          Task.start(fn -> Client.pause_app(app_id, config) end)
          put_flash(socket, :warn, "Pausing application #{app_id}.")

        "false" ->
          Task.start(fn -> Client.resume_app(app_id, config) end)
          put_flash(socket, :info, "Resuming application #{app_id}.")
      end

    {:noreply, update(socket, :paused, &(!&1))}
  end

  def handle_event("set_vm_count", %{"vm_count" => params}, socket) do
    %{"group" => group, "count" => count} = params
    {:noreply, update(socket, :vm_counts, &Map.replace(&1, group, count))}
  end

  def handle_event("set_vm_size", %{"vm_size" => params}, socket) do
    %{"group" => group, "size" => size} = params
    {:noreply, update(socket, :vm_sizes, &Map.replace(&1, group, size))}
  end

  def handle_event("scale_vms", %{"vms" => params}, %{assigns: assigns} = socket) do
    %{app: app, vm_counts: vm_counts, vm_sizes: vm_sizes, config: config} = assigns
    group = params["group"]
    app_id = app["id"]
    vm_size = vm_sizes[group]
    count = normalize_count(vm_counts[group])

    Task.start(fn ->
      Client.set_vm_count(app_id, group, count, config)
      Client.set_vm_size(app_id, vm_size, config)
    end)

    {:noreply, put_flash(socket, :info, "Successfully scaled VMs")}
  end

  def handle_event("restart_allocation", %{"restart" => params}, %{assigns: assigns} = socket) do
    %{app: app, restarting: restarting, config: config} = assigns
    alloc_id = params["alloc_id"]

    if alloc_id not in restarting do
      Task.async(fn -> restart_allocation(app["id"], alloc_id, config) end)
      {:noreply, update(socket, :restarting, &[alloc_id | &1])}
    else
      {:noreply, socket}
    end
  end

  defp normalize_count(nil), do: 0
  defp normalize_count(""), do: 0
  defp normalize_count(count) when is_integer(count) and count >= 0, do: count

  defp normalize_count(count) when is_integer(count) and count < 0 do
    Logger.warn("VM count cannot be below 0. Received input: #{inspect(count)}")
    0
  end

  defp normalize_count(count) when is_binary(count) do
    count |> String.to_integer() |> normalize_count()
  end

  defp restart_allocation(app_id, alloc_id, config) do
    Client.restart_allocation(app_id, alloc_id, config)
    {:restarted, alloc_id}
  end

  @impl true

  def handle_info({ref, {:restarted, alloc_id}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> put_flash(:info, "Instance with ID #{alloc_id} restarting.")
     |> update(:restarting, &List.delete(&1, alloc_id))}
  end

  def handle_info(:refresh, %{assigns: assigns} = socket) do
    Task.async(fn -> {:app, Client.fetch_app(assigns.app_name, assigns.config)} end)
    {:noreply, assign(socket, :refreshing, true)}
  end

  def handle_info({ref, {:app, app}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    schedule_refresh()

    {:noreply,
     socket
     |> assign_app(app)
     |> assign(:refreshing, false)}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
