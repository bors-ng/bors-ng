defmodule BorsNG.AdminController do
  @moduledoc """
  Functionality that is specific to administrators.

  Administrators are users with the `is_admin` flag set.
  Ensuring non-administrators can't get here is done in `BorsNG.Router`.

  Administrators have the ability to step outside the permissions
  and edit any repo, or delete it if they wish.
  """

  use BorsNG.Web, :controller

  alias BorsNG.Database.Crash
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.Repo

  # The actual handlers
  # Two-item ones have a project ID inputed
  # One-item ones don't

  def index(conn, _params) do
    orphans = Project.orphans()
    orphan_count = from(p in orphans, select: count(p.id))
    [orphan_count] = Repo.all(orphan_count)
    dup_patches = Repo.all(Patch.dups_in_batches())
    dup_patches_count = length(dup_patches)
    crashes_day = Crash.days(1)
    [crashes_day] = from(c in crashes_day, select: count(c.id)) |> Repo.all()
    crashes_week = Crash.days(7)
    [crashes_week] = from(c in crashes_week, select: count(c.id)) |> Repo.all()
    crashes_month = Crash.days(30)
    [crashes_month] = from(c in crashes_month, select: count(c.id)) |> Repo.all()

    render(conn, "index.html",
      orphan_count: orphan_count,
      dup_patches_count: dup_patches_count,
      crashes_day: crashes_day,
      crashes_week: crashes_week,
      crashes_month: crashes_month
    )
  end

  def orphans(conn, _params) do
    orphans = Repo.all(Project.orphans())
    render(conn, "orphans.html", orphans: orphans)
  end

  def dup_patches(conn, _params) do
    patch_proj =
      Patch.dups_in_batches()
      |> Repo.all()
      |> Enum.map(fn patch ->
        project = Repo.one(from(Project, where: [id: ^patch.project_id]))
        {patch, project}
      end)

    render(conn, "dup-patches.html", patch_proj: patch_proj)
  end

  def project_by_name(conn, %{"project" => %{"name" => name}}) do
    project = Repo.get_by!(Project, name: name)
    redirect(conn, to: project_path(conn, :show, project.id))
  end

  def synchronize_all_installations(conn, _params) do
    BorsNG.Worker.SyncerInstallation.start_synchronize_all_installations()
    redirect(conn, to: admin_path(conn, :index))
  end

  def crashes(conn, %{"days" => days}) do
    crashes =
      days
      |> String.to_integer(10)
      |> Crash.days()
      |> preload([c], [:project])
      |> order_by([c], desc: c.inserted_at)
      |> Repo.all()

    render(conn, "crashes.html", crashes: crashes, days: days)
  end
end
