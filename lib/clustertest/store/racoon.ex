defmodule Clustertest.Store.Racoon do
  use GenServer

  defmodule Types.Racoon do
    defstruct [
      :id,
      :name,
      caretaker_id: nil
    ]

    def decode({__MODULE__, id, name, caretaker_id}) do
      %__MODULE__{
        id: id,
        name: name,
        caretaker_id: caretaker_id
      }
    end

    def encode(%__MODULE__{
      id: id,
      name: name,
      caretaker_id: caretaker_id
    }) do
      {__MODULE__, id, name, caretaker_id}
    end
  end

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

  def list() do
    {:atomic, list} = :mnesia.transaction(fn ->
      :mnesia.match_object({Types.Racoon, :_, :_, :_})
    end)

    list |> Enum.map(fn x -> Types.Racoon.decode(x) end)
  end

  def create(%Types.Racoon{ id: id } = state) when is_integer(id) do
    IO.puts("Inserting #{inspect state}")

    {:atomic, reason} = :mnesia.transaction(fn ->
      case :mnesia.read(Types.Racoon, id, :write) do
        [] ->
          Types.Racoon.encode(state) |> :mnesia.write()
        _ ->
          :record_exists
      end
    end)

    reason
  end

  def update(%Types.Racoon{ id: id } = new_state) when is_integer(id) do
    IO.puts("Updating #{inspect new_state}")

    {:atomic, reason} = :mnesia.transaction(fn ->
      [{Types.Racoon, ^id, _, _,}] = :mnesia.read(Types.Racoon, id, :write)

      Types.Racoon.encode(new_state) |> :mnesia.write()
    end)

    reason
  end

  def read(id) when is_integer(id) do
    IO.puts("Returning #{id}")

    {:atomic, result} = :mnesia.transaction(fn ->
      :mnesia.read(Types.Racoon, id, :read)
    end)

    case result do
      [] -> nil
      list -> list |> List.first() |> Types.Racoon.decode()
    end
  end

  def delete(id) when is_integer(id) do
    IO.puts("Deleting #{id}")

    {:atomic, :ok} = :mnesia.transaction(fn ->
      :ok = :mnesia.delete(Types.Racoon, id, :write)
    end)
    :ok
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
      Types.Racoon,
      [
        attributes: [
          :id,
          :name,
          :caretaker_id
        ],
        disc_copies: [Node.self()]
      ]
    )
    |> case do
      {:atomic, :ok} ->
        :ok
      {:aborted, {:already_exists, Types.Racoon}} ->
        :ok
    end

    :ok = :mnesia.wait_for_tables([Types.Racoon], 5000)
  end

  defp ensure_table_copy_exists() do
    case :mnesia.add_table_copy(Types.Racoon, node(), :disc_copies) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, Types.Racoon, _node}} -> :ok
    end
  end
end
