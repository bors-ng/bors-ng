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
  alias BorsNG.Database.Context.Logging
  alias BorsNG.Database.Context.Permission
  alias BorsNG.Database.Installation
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
    comment: ""
  )

  @type t :: %BorsNG.Command{
          project: Project.t(),
          commenter: User.t(),
          pr: map | nil,
          pr_xref: integer,
          patch: Patch.t() | nil,
          comment: binary
        }

  defp command_trigger(),
    do: Confex.fetch_env!(:bors, BorsNG)[:command_trigger]

  @doc """
  If the GitHub PR is not already in this struct, fetch it.
  """
  @spec fetch_pr(t) :: t
  def fetch_pr(c) do
    case {c.pr, c.pr_xref} do
      {nil, pr_xref} ->
        pr =
          c.project.repo_xref
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
          {:try, binary}
          | :try_cancel
          | {:activate_by, binary}
          | {:set_is_single, integer()}
          | {:set_priority, integer()}
          | :activate
          | :deactivate
          | :delegate
          | {:delegate_to, binary}
          | {:autocorrect, binary}
          | :ping
          | :retry

  @doc """
  Parse a comment for bors commands.
  """
  @spec parse(nil) :: []
  def parse(nil) do
    []
  end

  @spec parse(binary) :: [cmd]
  def parse(comment) do
    comment
    |> String.splitter("\n")
    |> Enum.flat_map(fn string ->
      trim_and_parse_cmd(Regex.named_captures(regex(), string))
    end)
  end

  def regex, do: ~r/^(?<command_trigger>#{command_trigger()}|bros):?\s(?<command>.+)/i

  def trim_and_parse_cmd(%{"command_trigger" => "bros", "command" => cmd}) do
    with [_] <- parse_cmd(cmd), do: [:bros]
  end

  def trim_and_parse_cmd(%{"command" => cmd}) do
    cmd
    |> String.trim()
    |> parse_cmd()
  end

  def trim_and_parse_cmd(_), do: []

  def parse_cmd("try-"), do: [:try_cancel]
  def parse_cmd("try" <> arguments), do: [{:try, arguments}]
  def parse_cmd("single" <> rest), do: parse_single_patch(rest)
  def parse_cmd("r+ single" <> rest), do: parse_single_patch(rest) ++ [:activate]
  def parse_cmd("r+ p=" <> rest), do: parse_priority(rest) ++ [:activate]
  def parse_cmd("r+" <> _), do: [:activate]
  def parse_cmd("r-" <> _), do: [:deactivate]
  def parse_cmd("r=" <> arguments), do: parse_activation_args(arguments)
  def parse_cmd("merge-" <> _), do: [:deactivate]
  def parse_cmd("merge p=" <> rest), do: parse_priority(rest) ++ [:activate]
  def parse_cmd("merge=" <> arguments), do: parse_activation_args(arguments)
  def parse_cmd("merge" <> _), do: [:activate]
  def parse_cmd("delegate+" <> _), do: [:delegate]
  def parse_cmd("delegate=" <> arguments), do: parse_delegation_args(arguments)
  def parse_cmd("d+" <> _), do: [:delegate]
  def parse_cmd("d=" <> arguments), do: parse_delegation_args(arguments)
  def parse_cmd("+r" <> _), do: [{:autocorrect, "r+"}]
  def parse_cmd("-r" <> _), do: [{:autocorrect, "r-"}]
  def parse_cmd("ping" <> _), do: [:ping]
  def parse_cmd("p=" <> rest), do: parse_priority(rest)
  def parse_cmd("retry" <> _), do: [:retry]
  def parse_cmd(_), do: []

  @doc ~S"""
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
      iex> Command.parse_activation_args("", "")
      ""
      iex> Command.parse_activation_args("somebody")
      [{:activate_by, "somebody"}]
      iex> Command.parse_activation_args("")
      []
      iex> Command.parse_activation_args("  ")
      []
      iex> Command.parse_activation_args("somebody p=10")
      [{:set_priority, 10}, {:activate_by, "somebody"}]
  """
  def parse_activation_args("", string) do
    {rest, mentions} =
      string
      |> String.trim()
      |> String.replace(~r/, */, ",")
      |> String.split("\n", parts: 2)
      |> List.first()
      |> String.trim()
      |> String.split(~r/, */)
      |> Enum.map(fn s -> String.replace(s, "@", "") end)
      |> List.pop_at(-1)

    [last_mention | rest_list] =
      rest
      |> String.trim()
      |> String.split(~r/\s+/, parts: 2)

    mentions = mentions ++ [last_mention]
    mentions = Enum.join(mentions, ",")

    params =
      case rest_list do
        [] ->
          nil

        [rest] ->
          rest
          |> String.trim()
          |> String.split("=", parts: 2)
          |> Enum.map(&String.trim(&1))
      end

    case params do
      ["p", priority_s] ->
        {priority_i, _} = Integer.parse(priority_s)
        {mentions, %{p: priority_i}}

      _ ->
        mentions
    end
  end

  def parse_activation_args(arguments) do
    arguments = parse_activation_args("", arguments)

    case arguments do
      "" -> []
      {mentions, %{p: p}} -> [{:set_priority, p}, {:activate_by, mentions}]
      arguments -> [{:activate_by, arguments}]
    end
  end

  @doc ~S"""
  The username part of a delegate-to command is defined like this:

    * It may start with whitespace
    * @-signs are stripped
    * ", " is converted to ","
    * Otherwise, whitespace ends it.
    * It's split on comma.

      iex> alias BorsNG.Command
      iex> Command.parse_delegation_args(" this, is, whitespace heavy")
      [
        {:delegate_to, "this"},
        {:delegate_to, "is"},
        {:delegate_to, "whitespace"}]
      iex> Command.parse_delegation_args(" @this, @has, @ats")
      [{:delegate_to, "this"}, {:delegate_to, "has"}, {:delegate_to, "ats"}]
      iex> Command.parse_delegation_args(" trimmed ")
      [{:delegate_to, "trimmed"}]
      iex> Command.parse_delegation_args("what\never")
      [{:delegate_to, "what"}]
      iex> Command.parse_delegation_args("somebody")
      [{:delegate_to, "somebody"}]
      iex> Command.parse_delegation_args("")
      []
      iex> Command.parse_delegation_args("  ")
      []
  """
  def parse_delegation_args([], "", " " <> rest) do
    parse_delegation_args([], "", rest)
  end

  def parse_delegation_args(l, nick, "@" <> rest) do
    parse_delegation_args(l, nick, rest)
  end

  def parse_delegation_args(l, nick, ", " <> rest) do
    parse_delegation_args([nick | l], "", rest)
  end

  def parse_delegation_args(l, nick, "," <> rest) do
    parse_delegation_args([nick | l], "", rest)
  end

  def parse_delegation_args(l, nick, "\n" <> _) do
    [nick | l]
  end

  def parse_delegation_args(l, nick, "") do
    [nick | l]
  end

  def parse_delegation_args(l, nick, " " <> _) do
    [nick | l]
  end

  def parse_delegation_args(l, nick, <<c::8, rest::binary>>) do
    parse_delegation_args(l, <<nick::binary, c::8>>, rest)
  end

  def parse_delegation_args(arguments) do
    []
    |> parse_delegation_args("", arguments)
    |> :lists.reverse()
    |> Enum.flat_map(fn
      "" -> []
      nick -> [{:delegate_to, nick}]
    end)
  end

  def parse_priority(binary) do
    {p, _} = Integer.parse(binary)

    [{:set_priority, p}]
  end

  def parse_single_patch(binary) do
    case String.trim(binary) do
      "on" <> _ ->
        [{:set_is_single, true}]

      "off" <> _ ->
        [{:set_is_single, false}]
    end
  end

  @doc """
  Given a populated struct, run everything.
  """
  @spec run(t) :: :ok
  def run(c) do
    c =
      c
      |> fetch_pr()
      |> fetch_patch()

    cmd_list = parse(c.comment)

    cmd_list
    |> required_permission_level()
    |> Permission.permission?(c.commenter, c.patch)
    |> if do
      Enum.each(cmd_list, &run(c, &1))
      Enum.each(cmd_list, &log(c, &1))
    else
      permission_denied(c)
    end
  end

  def required_permission_level_cmd(:ping) do
    :none
  end

  def required_permission_level_cmd({:autocorrect, _}) do
    :none
  end

  def required_permission_level_cmd({:try, _}) do
    :member
  end

  def required_permission_level_cmd(:try_cancel) do
    :member
  end

  def required_permission_level_cmd(:deactivate) do
    :member
  end

  def required_permission_level_cmd(:retry) do
    :member
  end

  def required_permission_level_cmd(_) do
    :reviewer
  end

  def required_permission_level(cmd_list) do
    cmd_list
    |> Enum.reduce(:none, fn cmd, perm ->
      new_perm = cmd |> required_permission_level_cmd()

      case {perm, new_perm} do
        {:none, new_perm} -> new_perm
        {perm, :none} -> perm
        {_, :reviewer} -> :reviewer
        {:reviewer, _} -> :reviewer
        {p, p} -> p
      end
    end)
  end

  def permission_denied(c) do
    login = c.commenter.login

    url =
      project_url(
        BorsNG.Endpoint,
        :confirm_add_reviewer,
        c.project,
        login
      )

    c.project.repo_xref
    |> Project.installation_connection(Repo)
    |> GitHub.post_comment!(
      c.pr_xref,
      """
      :lock: Permission denied

      Existing reviewers: [click here to make #{login} a reviewer](#{url})
      """
    )
  end

  @spec log(t, cmd) :: :ok
  def log(c, cmd) do
    Logging.log_cmd(c.patch, c.commenter, cmd)
  end

  @spec run(t, cmd) :: :ok
  def run(c, :activate) do
    run(c, {:activate_by, c.commenter.login})
  end

  def run(c, {:activate_by, username}) do
    batcher = Batcher.Registry.get(c.project.id)
    Batcher.reviewed(batcher, c.patch.id, username)
  end

  def run(c, {:set_is_single, is_single}) do
    batcher = Batcher.Registry.get(c.project.id)
    Batcher.set_is_single(batcher, c.patch.id, is_single)
  end

  def run(c, {:set_priority, priority}) do
    batcher = Batcher.Registry.get(c.project.id)
    Batcher.set_priority(batcher, c.patch.id, priority)
  end

  def run(c, :deactivate) do
    c = fetch_patch(c)
    batcher = Batcher.Registry.get(c.project.id)
    Batcher.cancel(batcher, c.patch.id)
  end

  def run(c, {:try, arguments}) do
    c = fetch_patch(c)
    attemptor = Attemptor.Registry.get(c.project.id)
    Attemptor.tried(attemptor, c.patch.id, arguments)
  end

  def run(c, :try_cancel) do
    c = fetch_patch(c)
    attemptor = Attemptor.Registry.get(c.project.id)
    Attemptor.cancel(attemptor, c.patch.id)
  end

  def run(c, {:autocorrect, command}) do
    c.project.repo_xref
    |> Project.installation_connection(Repo)
    |> GitHub.post_comment!(
      c.pr_xref,
      ~s/Did you mean "#{command}"?/
    )
  end

  def run(c, :ping) do
    c.project.repo_xref
    |> Project.installation_connection(Repo)
    |> GitHub.post_comment!(
      c.pr_xref,
      "pong"
    )
  end

  def run(c, :delegate) do
    patch = Repo.preload(c.patch, :author)
    delegate_to(c, patch.author)
  end

  def run(c, {:delegate_to, login}) do
    delegatee =
      case Repo.get_by(User, login: login) do
        nil ->
          installation = Repo.get!(Installation, c.project.installation_id)

          gh_user =
            GitHub.get_user_by_login!(
              {:installation, installation.installation_xref},
              login
            )

          Repo.insert!(%User{
            login: gh_user.login,
            user_xref: gh_user.id
          })

        user ->
          user
      end

    delegate_to(c, delegatee)
  end

  def run(c, :retry) do
    {commenter, cmd} = Logging.most_recent_cmd(c.patch)
    run(%{c | commenter: commenter}, cmd)
  end

  def run(c, :bros) do
    c.project.repo_xref
    |> Project.installation_connection(Repo)
    |> GitHub.post_comment!(
      c.pr_xref,
      ~s/👊/
    )
  end

  def delegate_to(c, delegatee) do
    Permission.delegate(delegatee, c.patch)

    c.project.repo_xref
    |> Project.installation_connection(Repo)
    |> GitHub.post_comment!(
      c.pr_xref,
      ~s{:v: #{delegatee.login} can now approve this pull request. To approve and merge a pull request, simply reply with `bors r+`. More detailed instructions are available [here](https://bors.tech/documentation/getting-started/#reviewing-pull-requests).}
    )
  end
end
