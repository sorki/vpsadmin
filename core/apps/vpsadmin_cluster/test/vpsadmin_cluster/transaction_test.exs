defmodule VpsAdmin.Cluster.TransactionTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Command, Transaction}
  alias VpsAdmin.Cluster.Transaction.Chain
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  defmodule OptionCommand do
    use Command

    def create(ctx, [id: id]) do
      ctx
      |> Cluster.Command.Test.Noop.create(nil)
      |> params(%{id: id})
    end
  end

  defmodule SimpleCommands do
    use Transaction

    def label(), do: "Simple commands"

    def create(ctx, _opts) do
      ctx
      |> append(Cluster.Command.Test.Noop)
      |> append(Cluster.Command.Test.Noop)
      |> append(Cluster.Command.Test.Noop)
    end
  end

  defmodule CommandOptions do
    use Transaction

    def label(), do: "Command options"

    def create(ctx, initial) do
      ctx
      |> append(OptionCommand, id: initial+100)
      |> append(OptionCommand, id: initial+200)
      |> append(OptionCommand, id: initial+300)
    end
  end

  defmodule ShallowInclude do
    use Transaction

    def label(), do: "Shallow include"

    def create(ctx, initial) do
      ctx
      |> include(CommandOptions, initial)
      |> append(OptionCommand, id: initial+400)
      |> append(OptionCommand, id: initial+500)
      |> include(CommandOptions, initial+500)
    end
  end

  defmodule NestedInclude do
    use Transaction

    def label(), do: "Nested include"

    def create(ctx, _opts) do
      ctx
      |> include(ShallowInclude, 0)
      |> append(OptionCommand, id: 900)
      |> append(OptionCommand, id: 1000)
      |> include(ShallowInclude, 1000)
    end
  end

  defmodule ResourceLocking do
    use Transaction

    def label(), do: "Resource locking"

    def create(ctx, _opts) do
      location = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> lock(location)
      |> run(fn ctx -> Context.put(ctx, :location, location) end)
    end
  end

  defmodule DoubleResourceLocking do
    use Transaction

    def label(), do: "Double resource locking"

    def create(ctx, _opts) do
      location = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> lock(location)
      |> lock(location)
      |> lock(location)
    end
  end

  defmodule NestedResourceLocking do
    use Transaction

    def label(), do: "Nested resource locking"

    def create(ctx, _opts) do
      ctx
      |> include(ResourceLocking)
      |> lock(fn ctx -> ctx.data.location end)
    end
  end

  defmodule LockObject do
    use Transaction

    def label(), do: "Lock object"

    def create(ctx, obj) do
      ctx
      |> lock(obj)
    end
  end

  defmodule RunPipeline do
    use Transaction

    def label(), do: "Run pipeline"

    def create(ctx, pid) do
      ctx
      |> run(fn ctx ->
        ctx
        |> Context.put(
          :location,
          Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})
        )
      end)
      |> lock(fn ctx -> ctx.data.location end)
      |> run(fn ctx -> Agent.update(pid, fn _ -> ctx.data.location end) end)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Persistence.Repo)
  end

  test "can append commands" do
    {:ok, chain} = Chain.stage_single(SimpleCommands)
    chain = Chain.preload(chain)

    assert length(chain.transactions) == 1
    assert length(List.first(chain.transactions).commands) == 3
  end

  test "can append commands with options" do
    {:ok, chain} = Chain.stage_single(CommandOptions, 0)
    chain = Chain.preload(chain)
    cmds = List.first(chain.transactions).commands

    assert length(cmds) == 3

    [100, 200, 300]
    |> Enum.zip(for cmd <- cmds, do: cmd.params["id"])
    |> Enum.each(fn {v1, v2} -> assert v1 == v2 end)
  end

  test "can include other transactions" do
    {:ok, chain} = Chain.stage_single(ShallowInclude, 0)
    chain = Chain.preload(chain)
    cmds = List.first(chain.transactions).commands

    assert length(cmds) == 8

    (for n <- 1..8, do: n * 100)
    |> Enum.zip(for cmd <- cmds, do: cmd.params["id"])
    |> Enum.each(fn {v1, v2} -> assert v1 == v2 end)
  end

  test "included transactions can include other transactions" do
    {:ok, chain} = Chain.stage_single(NestedInclude)
    chain = Chain.preload(chain)
    cmds = List.first(chain.transactions).commands

    assert length(cmds) == 18

    (for n <- 1..18, do: n * 100)
    |> Enum.zip(for cmd <- cmds, do: cmd.params["id"])
    |> Enum.each(fn {v1, v2} -> assert v1 == v2 end)
  end

  test "resource locking" do
    {:ok, chain} = Chain.stage_single(ResourceLocking)
    chain = Chain.preload(chain)

    locks = Persistence.Transaction.Chain.locks(chain)
    cluster = Enum.find(
      locks,
      nil,
      &(&1.resource == "Elixir.VpsAdmin.Persistence.Schema.Cluster")
    )
    location = Enum.find(
      locks,
      nil,
      &(&1.resource == "Elixir.VpsAdmin.Persistence.Schema.Location")
    )

    assert cluster
    assert cluster.type == :inclusive
    refute cluster.transaction_chain_id
    assert location
    assert location.type == :exclusive
    assert location.transaction_chain_id == chain.id
  end

  test "locking already locked resources by this transactions" do
    {:ok, chain} = Chain.stage_single(DoubleResourceLocking)
    chain = Chain.preload(chain)

    assert length(Persistence.Transaction.Chain.locks(chain)) == 2
  end

  test "locking already locked resources by included transactions" do
    {:ok, chain} = Chain.stage_single(NestedResourceLocking)
    chain = Chain.preload(chain)

    assert length(Persistence.Transaction.Chain.locks(chain)) == 2
  end

  test "refuses to lock resource locked by another transaction" do
    location = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

    {:ok, chain} = Chain.stage_single(LockObject, location)
    chain = Chain.preload(chain)

    assert length(Persistence.Transaction.Chain.locks(chain)) == 2
    assert_raise(Ecto.InvalidChangesetError, fn -> Chain.stage_single(LockObject, location) end)
  end

  test "running arbitrary functions within pipeline" do
    {:ok, pid} = Agent.start_link(fn -> nil end)
    {:ok, _chain} = Chain.stage_single(RunPipeline, pid)

    assert Agent.get(pid, fn state -> state end).label == "Test"
  end
end
