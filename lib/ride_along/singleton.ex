defmodule RideAlong.Singleton do
  @moduledoc """
  Some functionality we only want to run on a single server.

  This server uses a globally registered name to decide whether it or another
  server is responsible for those singleton functionalities.
  """
  use GenServer
  require Logger

  @default_name __MODULE__

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts)
  end

  def singleton?(name \\ @default_name) do
    :persistent_term.get(name, true)
  end

  @impl GenServer
  def init(opts) do
    name = opts[:name]

    {:ok, name, check_registration(name)}
  end

  @impl GenServer
  def handle_continue(:register, name) do
    result =
      case :global.register_name(name, self(), &:global.random_notify_name/3) do
        :yes ->
          set_singleton(name, true)
          :hibernate

        :no ->
          check_registration(name)
      end

    {:noreply, name, result}
  end

  @impl GenServer
  def handle_info({:global_name_conflict, other}, name) do
    Process.monitor(other)
    set_singleton(name, false)
    {:noreply, name, :hibernate}
  end

  def handle_info({:DOWN, _, :process, _, _}, name) do
    {:noreply, name, check_registration(name)}
  end

  defp check_registration(name) do
    case :global.whereis_name(name) do
      :undefined ->
        {:continue, :register}

      pid ->
        Process.monitor(pid)
        set_singleton(name, false)
        :hibernate
    end
  end

  defp set_singleton(name, value) do
    if value != singleton?(name) do
      :persistent_term.put(name, value)
      Logger.info("#{__MODULE__} node=#{inspect(node())} singleton=#{value}")
    end
  end
end
