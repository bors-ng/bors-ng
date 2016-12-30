defmodule Aelita2.BatchTest do
  use Aelita2.ModelCase

  alias Aelita2.Batch
  alias Aelita2.Installation
  alias Aelita2.Project

  setup do
    installation = Repo.insert!(%Installation{
      installation_xref: 31,
      })
    project = Repo.insert!(%Project{
      installation_id: installation.id,
      repo_xref: 13,
      name: "example/project",
      })
    {:ok, installation: installation, project: project}
  end

  test "grab batches that are incomplete", %{installation: _installation, project: project} do
    batch0 = Repo.insert!(%Batch{project: project, state: 0})
    batch1 = Repo.insert!(%Batch{project: project, state: 1})
    _batch2 = Repo.insert!(%Batch{project: project, state: 2})
    _batch3 = Repo.insert!(%Batch{project: project, state: 3})
    incomplete = Repo.all(Batch.all_for_project(project.id, :incomplete))
    assert Enum.any?(incomplete, fn batch -> batch.id == batch0.id end)
    assert Enum.any?(incomplete, fn batch -> batch.id == batch1.id end)
    assert Enum.count(incomplete) == 2
  end

  test "grab batches that are complete", %{installation: _installation, project: project} do
    _batch0 = Repo.insert!(%Batch{project: project, state: 0})
    _batch1 = Repo.insert!(%Batch{project: project, state: 1})
    batch2 = Repo.insert!(%Batch{project: project, state: 2})
    batch3 = Repo.insert!(%Batch{project: project, state: 3})
    incomplete = Repo.all(Batch.all_for_project(project.id, :complete))
    assert Enum.any?(incomplete, fn batch -> batch.id == batch2.id end)
    assert Enum.any?(incomplete, fn batch -> batch.id == batch3.id end)
    assert Enum.count(incomplete) == 2
  end
end
