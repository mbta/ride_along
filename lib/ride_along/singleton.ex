defmodule RideAlong.Singleton do
  @moduledoc """
  Some functionality we only want to run on a single server.

  Each time a node joins/exits the cluster, we randomly sort the nodes and pick
  the smallest one.
  """
  use GenServer

  require Logger

  @default_name __MODULE__

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, @default_name)
    set_singleton(opts[:name])
    GenServer.start_link(__MODULE__, opts)
  end

  def singleton?(name \\ @default_name) do
    :persistent_term.get(name, true)
  end

  @impl GenServer
  def init(opts) do
    name = opts[:name]

    :net_kernel.monitor_nodes(true)

    {:ok, name, :hibernate}
  end

  @impl GenServer
  def handle_info({:nodeup, _node}, name) do
    set_singleton(name)

    {:noreply, name, :hibernate}
  end

  def handle_info({:nodedown, _node}, name) do
    set_singleton(name)

    {:noreply, name, :hibernate}
  end

  def set_singleton(name) do
    singleton_node = Enum.min_by([node() | Node.list()], &:erlang.phash2({name, &1}))
    singleton? = singleton_node == node()

    :persistent_term.put(name, singleton?)
    log_singleton(singleton?)
  end

  defp log_singleton(value) do
    Logger.info("#{__MODULE__} node=#{inspect(node())} others=#{inspect(Node.list())} singleton=#{inspect(value)}")
  end
end
