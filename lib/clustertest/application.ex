defmodule Clustertest.Application do
  use Application

  def start(_type, _args) do
    topologies = [
      epmd_example: [
        strategy: Cluster.Strategy.Epmd,
        config: [
          hosts: [:"a@127.0.0.1", :"b@127.0.0.1"]
        ]
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Clustertest.ClusterSupervisor]]}
    ]
    |> Supervisor.start_link(strategy: :one_for_one)
  end
end
