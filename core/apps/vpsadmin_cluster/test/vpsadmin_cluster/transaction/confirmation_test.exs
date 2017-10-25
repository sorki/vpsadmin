defmodule VpsAdmin.Cluster.Transaction.ConfirmationTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Command, Transaction}
  alias VpsAdmin.Cluster.Transaction.Chain
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  defmodule TestTransaction do
    use Transaction

    def label(), do: "Test transaction"

    def create(ctx, fun), do: fun.(ctx)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Persistence.Repo)
  end

  test "insert accepts a new changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
          assert is_integer(location.id)
          assert location.row_state == :new

          {ctx, location} = insert(
            ctx,
            %Schema.Location{} |> Ecto.Changeset.change(%{label: "Test", domain: "test"})
          )
          assert is_integer(location.id)
          assert location.row_state == :new

          ctx
        end)
    end)
  end

  test "insert accepts precreated changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      new_location = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = insert(ctx, new_location)
          assert is_integer(location.id)
          assert new_location.id == location.id
          assert location.row_state == :new

          {ctx, location} = insert(
            ctx,
            new_location |> Ecto.Changeset.change()
          )
          assert is_integer(location.id)
          assert new_location.id == location.id
          assert location.row_state == :new

          ctx
        end)
    end)
  end

  test "delete accepts changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      orig_location = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = delete(ctx, orig_location)
          assert is_integer(location.id)
          assert location.row_state == :deleted

          {ctx, location} = delete(
            ctx,
            orig_location |> Ecto.Changeset.change()
          )
          assert is_integer(location.id)
          assert location.row_state == :deleted

          ctx
        end)
    end)
  end

  test "change accepts changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      orig_location = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = change(ctx, orig_location, %{label: "Better Test"})
          assert is_integer(location.id)
          assert orig_location.id == location.id
          assert location.label == "Better Test"
          assert location.row_state == :updated
          assert location.row_changes == %{label: {ctx.chain.id, "Better Test"}}

          {ctx, location} = change(
            ctx,
            orig_location |> Ecto.Changeset.change(),
            %{label: "Best Test"}
          )
          assert is_integer(location.id)
          assert orig_location.id == location.id
          assert location.label == "Best Test"
          assert location.row_state == :updated
          assert location.row_changes == %{label: {ctx.chain.id, "Best Test"}}

          persistent = Persistence.Repo.get(Schema.Location, location.id)
          assert persistent.row_state == :updated
          assert persistent.label == "Test"
          assert persistent.row_changes == %{label: {ctx.chain.id, "Best Test"}}

          ctx
        end)
    end)
  end

  test "changing inserted rows" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
          assert is_integer(location.id)
          assert location.row_state == :new

          {ctx, location} = change(ctx, location, %{label: "Just Test"})
          assert is_integer(location.id)
          assert location.row_state == :new
          assert location.row_changes == %{label: {ctx.chain.id, "Just Test"}}
          assert location.label == "Just Test"

          ctx
        end)
    end)
  end

  test "multiple chains can update different columns in the same row" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    location = Persistence.Repo.insert!(%Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    })

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = change(ctx, location, %{label: "Change 1"})

          assert location.row_changes == %{label: {ctx.chain.id, "Change 1"}}
          assert location.label == "Change 1"

          ctx
        end)
    end)

    location = Persistence.Repo.get(Schema.Location, location.id)

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, location} = change(ctx, location, %{domain: "change2"})

           assert location.row_changes[:label]
           assert location.row_changes[:domain] == {ctx.chain.id, "change2"}
           assert location.label == "Test"
           assert location.domain == "change2"

           ctx
         end)
    end)
  end

  test "only one chain can change a particular column in one row" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    location = Persistence.Repo.insert!(%Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    })

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, location} = change(ctx, location, %{label: "Change 1"})

           assert location.row_changes == %{label: {ctx.chain.id, "Change 1"}}
           assert location.label == "Change 1"

           ctx
         end)
    end)

    location = Persistence.Repo.get(Schema.Location, location.id)

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           assert_raise(Ecto.InvalidChangesetError, fn ->
             {_ctx, _location} = change(ctx, location, %{label: "change2"})
           end)

           ctx
         end)
    end)
  end

  test "only one chain can insert/delete one row" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    loc1 = Persistence.Repo.insert!(%Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :new,
    })

    loc2 = Persistence.Repo.insert!(%Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    })

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, _location} = insert(ctx, loc1)
           {ctx, _location} = delete(ctx, loc2)
           ctx
         end)
    end)

    loc1 = Persistence.Repo.get(Schema.Location, loc1.id)
    loc2 = Persistence.Repo.get(Schema.Location, loc2.id)

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           assert_raise(Ecto.InvalidChangesetError, fn ->
             {_ctx, _location} = insert(ctx, loc1)
           end)

           assert_raise(Ecto.InvalidChangesetError, fn ->
             {_ctx, _location} = delete(ctx, loc2)
           end)

           ctx
         end)
    end)
  end

  test "deleting inserted rows" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
          assert is_integer(location.id)
          assert location.row_state == :new

          {ctx, location} = delete(ctx, location)
          assert is_integer(location.id)
          assert location.row_state == :deleted

          ctx
        end)
    end)
  end

  test "can confirm changes" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, pid} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      loc1 = Persistence.Repo.insert!(%Schema.Location{label: "Test1", domain: "test1"})
      loc2 = Persistence.Repo.insert!(%Schema.Location{label: "Test2", domain: "test2"})
      loc3 = Persistence.Repo.insert!(%Schema.Location{label: "Test3", domain: "test3"})

      Agent.update(pid, fn _ -> %{loc1: loc1.id, loc2: loc2.id, loc3: loc3.id} end)

      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, _loc1} = insert(ctx, loc1)
          {ctx, _loc2} = change(ctx, loc2, %{label: "Better Test 2", domain: "better.test2"})
          {ctx, _loc3} = delete(ctx, loc3)

          ctx
        end)
    end)

    {:ok, _chain} = Chain.close(chain, :ok)
    state = Agent.get(pid, fn state -> state end)

    loc1 = Persistence.Repo.get(Schema.Location, state.loc1)
    loc2 = Persistence.Repo.get(Schema.Location, state.loc2)
    loc3 = Persistence.Repo.get(Schema.Location, state.loc3)

    assert loc1
    assert loc1.row_state == :confirmed

    assert loc2
    assert loc2.row_state == :confirmed
    assert is_nil(loc2.row_changes)
    assert loc2.label == "Better Test 2"
    assert loc2.domain == "better.test2"

    refute loc3

    Agent.stop(pid)

    confirmations = Persistence.Transaction.Confirmation.for_chain(chain)
    assert length(confirmations) > 0

    for cnf <- confirmations do
      assert cnf.state == :confirmed
    end
  end

  test "can discard changes" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, pid} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      loc1 = Persistence.Repo.insert!(%Schema.Location{label: "Test1", domain: "test1"})
      loc2 = Persistence.Repo.insert!(%Schema.Location{label: "Test2", domain: "test2"})
      loc3 = Persistence.Repo.insert!(%Schema.Location{label: "Test3", domain: "test3"})

      Agent.update(pid, fn _ -> %{loc1: loc1.id, loc2: loc2.id, loc3: loc3.id} end)

      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
          {ctx, _loc1} = insert(ctx, loc1)
          {ctx, _loc2} = change(ctx, loc2, %{label: "Better Test 2", domain: "better.test2"})
          {ctx, _loc3} = delete(ctx, loc3)

          ctx
        end)
    end)

    {:ok, _chain} = Chain.close(chain, :error)
    state = Agent.get(pid, fn state -> state end)

    loc1 = Persistence.Repo.get(Schema.Location, state.loc1)
    loc2 = Persistence.Repo.get(Schema.Location, state.loc2)
    loc3 = Persistence.Repo.get(Schema.Location, state.loc3)

    refute loc1

    assert loc2
    assert loc2.row_state == :confirmed
    assert is_nil(loc2.row_changes)
    assert loc2.label == "Test2"
    assert loc2.domain == "test2"

    assert loc3
    assert loc3.row_state == :confirmed

    Agent.stop(pid)

    confirmations = Persistence.Transaction.Confirmation.for_chain(chain)
    assert length(confirmations) > 0

    for cnf <- confirmations do
      assert cnf.state == :discarded
    end
  end

  test "can confirm changes by multiple chains" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    loc = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

    {:ok, chain1} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, _loc} = change(ctx, loc, %{label: "Better Test"})
           ctx
         end)
    end)

    loc = Persistence.Repo.get(Schema.Location, loc.id)

    {:ok, chain2} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, _loc} = change(ctx, loc, %{domain: "better.test"})
           ctx
         end)
    end)

    {:ok, _chain} = Chain.close(chain1, :ok)
    loc = Persistence.Repo.get(Schema.Location, loc.id)

    assert loc
    assert loc.row_state == :updated
    assert loc.label == "Better Test"
    assert loc.domain == "test"
    refute loc.row_changes[:label]
    assert loc.row_changes[:domain]

    {:ok, _chain} = Chain.close(chain2, :ok)
    loc = Persistence.Repo.get(Schema.Location, loc.id)

    assert loc
    assert loc.row_state == :confirmed
    refute loc.row_changes
    assert loc.label == "Better Test"
    assert loc.domain == "better.test"
  end

  test "can discard changes by one of multiple chains" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    loc = Persistence.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

    {:ok, chain1} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, _loc} = change(ctx, loc, %{label: "Better Test"})
           ctx
         end)
    end)

    loc = Persistence.Repo.get(Schema.Location, loc.id)

    {:ok, chain2} = Chain.stage_single(Transaction.Custom, fn ctx ->
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, _loc} = change(ctx, loc, %{domain: "better.test"})
           ctx
         end)
    end)

    {:ok, _chain} = Chain.close(chain1, :error)
    loc = Persistence.Repo.get(Schema.Location, loc.id)

    assert loc
    assert loc.row_state == :updated
    assert loc.label == "Test"
    assert loc.domain == "test"
    refute loc.row_changes[:label]
    assert loc.row_changes[:domain]

    {:ok, _chain} = Chain.close(chain2, :ok)
    loc = Persistence.Repo.get(Schema.Location, loc.id)

    assert loc
    assert loc.row_state == :confirmed
    refute loc.row_changes
    assert loc.label == "Test"
    assert loc.domain == "better.test"
  end
end
