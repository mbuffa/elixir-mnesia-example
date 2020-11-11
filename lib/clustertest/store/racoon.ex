defmodule Clustertest.Store.Racoon do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def init(state) do
    # Get notified when new nodes are connected.
    :ok = :net_kernel.monitor_nodes(true)

    {:ok, state}
  end

  def handle_info({:nodeup, node}, state) do
    IO.puts("Node connected: #{inspect node}")

    :ok = connect_mnesia_to_cluster()

    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    IO.puts("Node disconnected: #{inspect node}")

    update_mnesia_nodes()

    {:noreply, state}
  end

  defp connect_mnesia_to_cluster() do
    :ok = :mnesia.start()

    {:ok, [_|_] = nodes} = :mnesia.change_config(:extra_db_nodes, Node.list())

    IO.puts("Extra db nodes: #{ inspect nodes }")

    :ok = ensure_table_exists()
    :mnesia.change_table_copy_type(:schema, node(), :disc_copies)
    :ok = ensure_table_copy_exists()

    IO.puts("Successfully connected Mnesia to the cluster!")

    :ok
  end

  defp update_mnesia_nodes do
    nodes = Node.list()
    IO.puts("Updating Mnesia nodes with #{inspect nodes}")
    :mnesia.change_config(:extra_db_nodes, nodes)
  end

  defp ensure_table_exists() do
    :mnesia.create_table(
      Racoon,
      [
        attributes: [
          :id,
          :name,
          :caretaker_id
        ]
      ]
    )
    |> case do
      {:atomic, :ok} ->
        :ok
      {:aborted, {:already_exists, Racoon}} ->
        :ok
    end

    :ok = :mnesia.wait_for_tables([Racoon], 5000)
  end

  defp ensure_table_copy_exists() do
    case :mnesia.add_table_copy(Racoon, node(), :disc_copies) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, Racoon, _node}} -> :ok
    end
  end


end
