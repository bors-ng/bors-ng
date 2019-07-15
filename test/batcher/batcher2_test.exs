defmodule Batcher2Test do
  use BorsNG.Worker.TestCase
  doctest BorsNG.GitHub

  alias BorsNG.Worker.Batcher
  alias BorsNG.Database.Batch
  alias BorsNG.Database.Status
  alias BorsNG.Database.Installation
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Status
  alias BorsNG.GitHub

  import Ecto.Query

  test "greets the world" do
    IO.puts("This is a test")



    batch = %Batch{
              project_id: 1,
              state: 0,
              commit: "5440f291bf92ef0d8555ae8b5ccf6a2a2d1c4386",
              into_branch: "master"}
      |> Repo.insert!()

#    IO.inspect(batch)

    status = %Status{
      identifier: "continuous-integration/jenkins/branch",
      url: "https://ci.plaid.com/job/bors-pdaas-3/job/staging/1/display/redirect",
      state: 2,
      batch: batch}
    |> Repo.insert!()

#    IO.inspect(status)

#    IO.inspect(Status.all_for_batch(batch.id))

    batches = Batch.all_for_project(1)

    IO.inspect(Repo.all(Status.all_for_batch(batch.id)))

    Batcher.maybe_complete_batch(batches)

    assert nil == Repo.get(LinkPatchBatch, 1)
  end
end