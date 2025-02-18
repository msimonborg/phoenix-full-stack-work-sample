defmodule Fly.Client do
  @moduledoc """
  Client API for making GraphQL queries.
  """
  alias Fly.Client.TemplateOptions
  require Logger

  @doc """
  Return the configuration for making the call to the remote server.

  ## Examples

      config = Fly.Client.config(access_token: System.get_env("FLYIO_ACCESS_TOKEN"))
      Fly.Client.fetch_template_options(%{}, config)

  """
  def config(opts) do
    token = Keyword.fetch!(opts, :access_token)

    [
      url: Application.get_env(:fly, :graphql_endpoint),
      headers: [Authorization: "Bearer #{token}"]
    ]
  end

  def perform_query(query_string, args, config, fun_name) do
    client().perform_query(query_string, args, config, fun_name)
  end

  def perform_http_get(url, opts \\ []) do
    client().perform_http_get(url, opts)
  end

  defp client, do: Application.get_env(:fly, :client_api)

  # TESTING NOTES:
  # the tldr is:
  # 1. use the production graphql api, it’s fine!
  # 2. in local dev, use your `fly auth token` to auth, i set this as an env var
  # 3. when we need to get real auth in, i can probably write some code to do that (and it might be fun anyway)

  def fetch_template_options(args, config) do
    """
      query {
        organizations {
          nodes {
            id
            name
            slug
            type
          }
        }
        platform {
          vmSizes {
            name
            memoryIncrementsMb
          }
          requestRegion
          regions {
            code
            name
          }
        }
      }
    """
    |> perform_query(args, config, :fetch_template_options)
    |> handle_response()
    |> TemplateOptions.transform()
  end

  def create_template_deployment(args, config) do
    """
    mutation($input: CreateTemplateDeploymentInput!) {
      createTemplateDeployment(input: $input) {
        templateDeployment {
          id
        }
      }
    }
    """
    |> perform_query(%{input: args}, config, :create_template_deployment)
    |> handle_response()
    |> case do
      {:ok, %{"createTemplateDeployment" => %{"templateDeployment" => %{"id" => id}}}} ->
        Logger.info("App deployment created: #{inspect(id)}")
        {:ok, id}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error(
          "Expected result from create_template_deployment not found. Response: #{inspect(other)}"
        )

        {:error, "Failed to receive ID for created app"}
    end
  end

  def get_template_deployment_status(id, config) do
    """
    query($id: ID!) {
      node(id: $id) {
        id
        ... on TemplateDeployment {
          status
          apps {
            nodes {
              id
              name
              state
              allocations{
                id
                status
              }
            }
          }
        }
      }
    }
    """
    |> perform_query(%{id: id}, config, :get_template_deployment_status)
    |> handle_response()
    |> case do
      {:ok, %{"node" => %{"status" => status}}} ->
        Logger.info("Deployment status returned: #{inspect(status)}")
        {:ok, status}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error(
          "Unexpected result from get_template_deployment_status. Response: #{inspect(other)}"
        )

        {:error, "Failed status check for created app"}
    end
  end

  def fetch_apps(config) do
    """
      query {
        apps {
          nodes {
            id
            name
            organization {
              id
              slug
            }
            status
            currentRelease {
    		      createdAt
    	      }
          }
        }
      }
    """
    |> perform_query(%{}, config, :fetch_apps)
    |> handle_response()
    |> case do
      {:ok, %{"apps" => %{"nodes" => apps}}} ->
        Logger.info("app list returned: #{inspect(apps)}")
        {:ok, apps}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from fetch_apps. Response: #{inspect(other)}")

        {:error, "Failed list apps"}
    end
  end

  def fetch_app(name, config) do
    """
      query($name: String!) {
        app(name: $name) {
          id
          name
          deployed
          status
          hostname
          version
          appUrl
          organization {
            id
            slug
          }
          deployed
          status
          regions {
            code
            name
          }
          processGroups {
            name
            regions
            maxPerRegion
            vmSize {
              name
              cpuCores
              memoryMb
            }
          }
          taskGroupCounts {
            name
            count
          }
          releases(first: 5) {
            totalCount
            nodes {
              id
              version
              stable
              description
              reason
              createdAt
              user {
                name
                avatarUrl
              }
            }
          }
          deploymentStatus {
            id
            status
            version
            description
            placedCount
            promoted
            desiredCount
            healthyCount
            unhealthyCount
          }
          allocations(showCompleted: false) {
            id
            idShort
            version
            latestVersion
            status
            desiredStatus
            totalCheckCount
            passingCheckCount
            warningCheckCount
            criticalCheckCount
            createdAt
            updatedAt
            canary
            region
            restarts
            healthy
            privateIP
            taskName
            checks {
              status
              output
              name
            }
          }
        }
      }
    """
    |> perform_query(%{name: name}, config, :fetch_app)
    |> handle_response()
    |> case do
      {:ok, %{"app" => app}} ->
        Logger.info("app returned: #{inspect(app)}")
        {:ok, app}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from fetch_app. Response: #{inspect(other)}")

        {:error, "Failed to fetch app"}
    end
  end

  def restart_allocation(app_id, allocation_id, config) do
    config = Keyword.put(config, :connection_opts, recv_timeout: 20_000)

    """
      mutation RestartAllocation($allocId: ID!, $appId: ID!) {
        restartAllocation(input: {
          appId: $appId
          allocId: $allocId
        }) {
          allocation {
            id
            desiredStatus
            status
            restarts
          }
        }
      }
    """
    |> perform_query(%{allocId: allocation_id, appId: app_id}, config, :restart_allocation)
    |> handle_response()
    |> case do
      {:ok, %{"restartAllocation" => restart_allocation}} ->
        Logger.info("restart successful: #{inspect(restart_allocation)}")
        {:ok, restart_allocation}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from restart_allocation. Response: #{inspect(other)}")

        {:error, "Failed to restart instance"}
    end
  end

  def pause_app(app_id, config) do
    config = Keyword.put(config, :connection_opts, recv_timeout: 20_000)

    """
      mutation PauseApp($appId: ID!) {
        pauseApp(input: {
          appId: $appId
        }) {
          app {
            id
            status
          }
        }
      }
    """
    |> perform_query(%{appId: app_id}, config, :pause_app)
    |> handle_response()
    |> case do
      {:ok, %{"pauseApp" => pause_app}} ->
        Logger.info("paused app successfully: #{inspect(pause_app)}")
        {:ok, pause_app}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from pause_app. Response: #{inspect(other)}")

        {:error, "Failed to pause app"}
    end
  end

  def resume_app(app_id, config) do
    config = Keyword.put(config, :connection_opts, recv_timeout: 20_000)

    """
      mutation ResumeApp($appId: ID!) {
        resumeApp(input: {
          appId: $appId
      	}) {
          app {
            id
            status
          }
        }
      }
    """
    |> perform_query(%{appId: app_id}, config, :resume_app)
    |> handle_response()
    |> case do
      {:ok, %{"resumeApp" => resume_app}} ->
        Logger.info("resumed app successfully: #{inspect(resume_app)}")
        {:ok, resume_app}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from resume_app. Response: #{inspect(other)}")

        {:error, "Failed to resume app"}
    end
  end

  def set_vm_count(app_id, group, count, config) do
    config = Keyword.put(config, :connection_opts, recv_timeout: 20_000)

    """
      mutation SetVMCount($appId: ID!, $group: String, $count: Int) {
        setVmCount(input: {
          appId: $appId
          groupCounts: [
            {
              group: $group,
              count: $count
            }
          ]
        }) {
          app {
            id
          }
          taskGroupCounts {
            name
            count
          }
        }
      }
    """
    |> perform_query(%{appId: app_id, group: group, count: count}, config, :set_vm_count)
    |> handle_response()
    |> case do
      {:ok, %{"setVmCount" => set_vm_count}} ->
        Logger.info("set VM count successful: #{inspect(set_vm_count)}")
        {:ok, set_vm_count}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from set_vm_count. Response: #{inspect(other)}")

        {:error, "Failed to set VM count"}
    end
  end

  def set_vm_size(app_id, size, config) do
    config = Keyword.put(config, :connection_opts, recv_timeout: 20_000)

    """
      mutation SetVMSize($appId: ID!, $sizeName: String!) {
        setVmSize(input: {
          appId: $appId,
          sizeName: $sizeName
        }) {
          app {
            id
          }
          vmSize {
            name
            memoryMb
            cpuCores
          }
        }
      }
    """
    |> perform_query(%{appId: app_id, sizeName: size}, config, :set_vm_size)
    |> handle_response()
    |> case do
      {:ok, %{"setVmSize" => set_vm_size}} ->
        Logger.info("set VM size successful: #{inspect(set_vm_size)}")
        {:ok, set_vm_size}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from set_vm_size. Response: #{inspect(other)}")

        {:error, "Failed to set VM size"}
    end
  end

  def fetch_current_user(config) do
    """
      query {
        viewer {
          id
          name
          email
        }
      }
    """
    |> perform_query(%{}, config, :fetch_apps)
    |> handle_response()
    |> case do
      {:ok, %{"viewer" => viewer}} ->
        Logger.info("viewer returned: #{inspect(viewer)}")
        {:ok, viewer}

      {:error, _reason} = error ->
        error

      other ->
        Logger.error("Unexpected result from fetch_current_user. Response: #{inspect(other)}")

        {:error, "Failed to fetch user"}
    end
  end

  # Handle the GraphQL API responses. Handles success and error responses.
  # Transforms the data into a format we want.
  # Detect that there is an error message and return only the first error message.
  def handle_response(
        {:ok,
         %Neuron.Response{
           status_code: 200,
           body: %{"errors" => [%{"message" => message} | _rest]}
         }}
      ) do
    {:error, message}
  end

  # If no errors detected, then consider it successful
  def handle_response({:ok, %Neuron.Response{status_code: 200, body: %{"data" => body}}}) do
    {:ok, body}
  end

  def handle_response({:error, %Neuron.Response{status_code: 401}}) do
    Logger.warn("API call failed as unauthorized")
    {:error, :unauthorized}
  end

  def handle_response(
        {:error, %Neuron.Response{status_code: status, body: %{"errors" => errors}}}
      ) do
    reasons =
      errors
      |> Enum.map(fn
        %{"message" => message} ->
          message

        other_error ->
          "Unknown error: #{inspect(other_error)}"
      end)
      |> Enum.join(", ")

    Logger.warn(
      "GraphQL query failed with status #{inspect(status)}. Reasons: #{inspect(reasons)}"
    )

    {:error, reasons}
  end

  def handle_response(
        {:error, %Neuron.JSONParseError{response: %Neuron.Response{status_code: 404}}}
      ) do
    Logger.warn("Received 404 on API request")
    {:error, "Error making API request"}
  end

  def handle_response({:error, %Neuron.JSONParseError{error: error}}) do
    Logger.warn("Error parsing JSON response. Invalid JSON. Error: #{inspect(error)}")
    {:error, "Error making API request"}
  end

  def handle_response({:error, reason}) do
    Logger.warn("Error issuing HTTP request. Error: #{inspect(reason)}")
    {:error, "Error making API request"}
  end

  @spec check_http_response(url :: String.t()) :: :ready | :not_ready | {:error, String.t()}
  def check_http_response(url) do
    url
    |> perform_http_get()
    |> handle_http_response()
  end

  defp handle_http_response({:ok, %HTTPoison.Response{status_code: 200}}) do
    :ready
  end

  defp handle_http_response({:ok, %HTTPoison.Response{status_code: redirect}})
       when redirect in 300..399 do
    :ready
  end

  defp handle_http_response({:ok, %HTTPoison.Response{status_code: 404}}) do
    :not_ready
  end

  defp handle_http_response({:ok, %HTTPoison.Response{status_code: client_error}})
       when client_error in 400..499 do
    {:error, "Received unexpected status code #{client_error}"}
  end

  defp handle_http_response({:ok, %HTTPoison.Response{status_code: server_error}})
       when server_error in 500..599 do
    {:error, "Received unexpected status code #{server_error}"}
  end

  defp handle_http_response({:error, %HTTPoison.Error{reason: :nxdomain}}) do
    :not_ready
  end

  defp handle_http_response({:error, %HTTPoison.Error{reason: :timeout}}) do
    :not_ready
  end

  defp handle_http_response({:error, %HTTPoison.Error{reason: :closed}}) do
    # The server closed the connection (too early)
    :not_ready
  end

  defp handle_http_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, "Unexpected error: #{inspect(reason)}"}
  end
end
