defmodule BorsNG.Command do
  @moduledoc """
  Resolve magic comments.

  # try

  The bors comment CLI allows parameters to be passed to try.
  Assuming the activation phrase is "bors try", you can do things like this:

      bors try --layout

  And the commit will come out like:

      Try #13: --layout

  Your build scripts should then inspect the commit message
  to pull out the commands.
  """

  alias BorsNG.Worker.Attemptor
  alias BorsNG.Worker.Batcher
  alias BorsNG.Command
  alias BorsNG.Database.LinkUserProject
  alias BorsNG.Database.Repo
  alias BorsNG.Database.Patch
  alias BorsNG.Database.Project
  alias BorsNG.Database.User
  alias BorsNG.GitHub
  alias BorsNG.Worker.Syncer

  import BorsNG.Router.Helpers

  defstruct(
    project: nil,
    commenter: nil,
    pr: nil,
    pr_xref: nil,
    patch: nil,
    comment: "")

  @activation_phrase(
    Application.get_env(:bors_frontend, BorsNG)[:activation_phrase])
  @activation_by_phrase(
    Application.get_env(:bors_frontend, BorsNG)[:activation_by_phrase])
  @deactivation_phrase(
    Application.get_env(:bors_frontend, BorsNG)[:deactivation_phrase])
  @try_phrase(
    Application.get_env(:bors_frontend, BorsNG)[:try_phrase])

  @type t :: %BorsNG.Command{
    project: Project.t,
    commenter: User.t,
    pr: map | nil,
    pr_xref: integer,
    patch: Patch.t | nil,
    comment: binary}

  @doc """
  If the GitHub PR is not already in this struct, fetch it.
  """
  @spec fetch_pr(t) :: t
  def fetch_pr(c) do
    case {c.pr, c.pr_xref} do
      {nil, pr_xref} ->
        pr = c.project.repo_xref
        |> Project.installation_connection(Repo)
        |> GitHub.get_pr!(pr_xref)
        %Command{c | pr: pr}
      {_, _} ->
        c
    end
  end

  @doc """
  If the Patch is not already in this struct, fetch it.
  This will not re-sync from GitHub unless it isn't even in the database.
  """
  @spec fetch_patch(t) :: t
  def fetch_patch(c) do
    case {c.patch, c.pr, c.pr_xref} do
      {nil, nil, pr_xref} ->
        case Repo.get_by(Patch, project_id: c.project.id, pr_xref: pr_xref) do
          nil -> c |> fetch_pr() |> fetch_patch()
          patch -> %Command{c | patch: patch}
        end
      {nil, pr, _} ->
        patch = Syncer.sync_patch(c.project.id, pr)
        %Command{c | patch: patch}
      {_, _, _} ->
        c
    end
  end

  @type cmd ::
    {:try, binary} |
    {:activate_by, binary} |
    :activate |
    :deactivate |
    :nomatch

  @doc """
  Parse a comment for bors commands.
  """
  @spec parse(binary | nil) :: cmd
  def parse(@try_phrase <> arguments) do
    {:try, arguments}
  end
  def parse(@activation_phrase <> _) do
    :activate
  end
  def parse(@activation_by_phrase <> arguments) do
    arguments = parse_activation_args("", arguments)
    case arguments do
      "" -> :nomatch
      arguments -> {:activate_by, arguments}
    end
  end
  def parse(@deactivation_phrase <> _) do
    :deactivate
  end
  def parse(<<_, rest :: binary>>) do
    parse(rest)
  end
  def parse(<<>>) do
    :nomatch
  end
  def parse(nil) do
    :nomatch
  end

  @doc ~S{
  The username part of an activation-by command is defined like this:

    * It may start with whitespace
    * @-signs are stripped
    * ", " is converted to ","
    * Otherwise, whitespace ends it.

      iex> alias BorsNG.Command
      iex> Command.parse_activation_args("", " this, is, whitespace heavy")
      "this,is,whitespace"
      iex> Command.parse_activation_args("", " @this, @has, @ats")
      "this,has,ats"
      iex> Command.parse_activation_args("", " trimmed ")
      "trimmed"
      iex> Command.parse_activation_args("", "what\never")
      "what"
  }
  def parse_activation_args("", " " <> rest) do
    parse_activation_args("", rest)
  end
  def parse_activation_args(args, "@" <> rest) do
    parse_activation_args(args, rest)
  end
  def parse_activation_args(args, ", " <> rest) do
    parse_activation_args(args <> ",", rest)
  end
  def parse_activation_args(args, "\n" <> _) do
    args
  end
  def parse_activation_args(args, "") do
    args
  end
  def parse_activation_args(args, " " <> _) do
    args
  end
  def parse_activation_args(args, <<c :: 8, rest :: binary>>) do
    parse_activation_args(<<args :: binary, c :: 8>>, rest)
  end

  @doc """
  Given a populated struct, run everything.
  """
  @spec run(t) :: :ok
  def run(c) do
    run(c, parse(c.comment))
  end
  @spec run(t, cmd) :: :ok
  def run(_, :nomatch) do
    :ok
  end
  def run(c, cmd) do
    link = Repo.get_by(LinkUserProject,
      project_id: c.project.id,
      user_id: c.commenter.id)
    run(c, cmd, link)
  end
  @spec run(t, cmd, term | nil) :: :ok
  def run(c, _, nil) do
    login = c.commenter.login
    url = project_url(
      BorsNG.Endpoint,
      :confirm_add_reviewer,
      c.project,
      login)
    c.project.repo_xref
    |> Project.installation_connection(Repo)
    |> GitHub.post_comment!(
      c.pr_xref,
      """
      :lock: Permission denied.

      Existing reviewers: [click here to make #{login} a reviewer](#{url}).
      """)
  end
  def run(c, :activate, link) do
    run(c, {:activate_by, c.commenter.login}, link)
  end
  def run(c, {:activate_by, username}, _) do
    c = c
    |> fetch_pr()
    |> fetch_patch()
    batcher = Batcher.Registry.get(c.project.id)
    Batcher.reviewed(batcher, c.patch.id, username)
  end
  def run(c, :deactivate, _) do
    c = fetch_patch(c)
    batcher = Batcher.Registry.get(c.project.id)
    Batcher.cancel(batcher, c.patch.id)
  end
  def run(c, {:try, arguments}, _) do
    c = fetch_patch(c)
    attemptor = Attemptor.Registry.get(c.project.id)
    Attemptor.tried(attemptor, c.patch.id, arguments)
  end
end
