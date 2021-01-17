defmodule BorsNG.Worker.Batcher.BorsToml do
  @moduledoc """
  The format for `bors.toml`. It looks like this:

      status = [
        "continuous-integration/travis-ci/push",
        "continuous-integration/appveyor/branch"]

      block_labels = [ "S-do-not-merge-yet" ]

      pr_status = [ "continuous-integration/travis-ci/pull" ]
  """

  alias BorsNG.GitHub

  defstruct status: [],
            block_labels: [],
            pr_status: [],
            timeout_sec: 60 * 60,
            # prerun_timeout_sec controls how long bors will wait for all GitHub status checks to be completed before taking action.
            # If this value is set to 0, bors will not wait for status checks to be completed. Otherwise, Bors will poll status checks
            # every 5 minutes. If prerun_timeout_sec or more elapsed in the latest poll, Bors will return an error message.
            # Half an hour by default.
            prerun_timeout_sec: 30 * 60,
            use_squash_merge: false,
            required_approvals: nil,
            up_to_date_approvals: false,
            cut_body_after: nil,
            delete_merged_branches: false,
            use_codeowners: false,
            committer: nil,
            commit_title: "Merge ${PR_REFS}",
            update_base_for_deletes: false

  @type tcommitter :: %{
          name: binary,
          email: binary
        }

  @type t :: %BorsNG.Worker.Batcher.BorsToml{
          status: [binary],
          use_squash_merge: boolean,
          block_labels: [binary],
          pr_status: [binary],
          timeout_sec: integer,
          prerun_timeout_sec: integer,
          required_approvals: integer | nil,
          up_to_date_approvals: boolean,
          cut_body_after: binary | nil,
          delete_merged_branches: boolean,
          use_codeowners: boolean,
          committer: tcommitter,
          commit_title: binary,
          update_base_for_deletes: boolean
        }

  @type err ::
          :status
          | :block_labels
          | :pr_status
          | :timeout_sec
          | :prerun_timeout_sec
          | :required_approvals
          | :cut_body_after
          | :committer_details
          | :commit_title
          | :empty_config
          | :parse_failed

  defp to_map(toml) do
    toml
    |> Enum.map(fn {key, val} -> {String.replace(key, "-", "_"), val} end)
    |> Map.new()
  end

  @spec new(binary) :: {:ok, t} | {:error, err}
  def new(str) when is_binary(str) do
    case Toml.decode(str) do
      {:ok, toml} ->
        toml = to_map(toml)

        committer = Map.get(toml, "committer", nil)

        committer =
          case committer do
            nil ->
              nil

            _ ->
              c = to_map(committer)

              %{
                name: Map.get(c, "name", nil),
                email: Map.get(c, "email", nil)
              }
          end

        toml = %BorsNG.Worker.Batcher.BorsToml{
          status: Map.get(toml, "status", []),
          use_squash_merge:
            Map.get(
              toml,
              "use_squash_merge",
              false
            ),
          block_labels: Map.get(toml, "block_labels", []),
          pr_status: Map.get(toml, "pr_status", []),
          timeout_sec: Map.get(toml, "timeout_sec", 60 * 60),
          prerun_timeout_sec: Map.get(toml, "prerun_timeout_sec", 30 * 60),
          required_approvals: Map.get(toml, "required_approvals", nil),
          up_to_date_approvals: Map.get(toml, "up_to_date_approvals", false),
          cut_body_after: Map.get(toml, "cut_body_after", nil),
          delete_merged_branches:
            Map.get(
              toml,
              "delete_merged_branches",
              false
            ),
          use_codeowners:
            Map.get(
              toml,
              "use_codeowners",
              false
            ),
          committer: committer,
          commit_title: Map.get(toml, "commit_title", "Merge ${PR_REFS}"),
          update_base_for_deletes: Map.get(toml, "update_base_for_deletes", false)
        }

        case toml do
          %{status: status} when not is_list(status) ->
            {:error, :status}

          %{block_labels: block_labels} when not is_list(block_labels) ->
            {:error, :block_labels}

          %{pr_status: pr_status} when not is_list(pr_status) ->
            {:error, :pr_status}

          %{timeout_sec: timeout_sec} when not is_integer(timeout_sec) ->
            {:error, :timeout_sec}

          %{prerun_timeout_sec: prerun_timeout_sec} when not is_integer(prerun_timeout_sec) ->
            {:error, :prerun_timeout_sec}

          %{required_approvals: req_approve}
          when not is_integer(req_approve) and not is_nil(req_approve) ->
            {:error, :required_approvals}

          %{cut_body_after: c} when not is_binary(c) and not is_nil(c) ->
            {:error, :cut_body_after}

          %{status: [], block_labels: [], pr_status: []} ->
            {:error, :empty_config}

          %{committer: %{name: n, email: e}} when is_nil(n) or is_nil(e) ->
            {:error, :committer_details}

          %{commit_title: msg} when not is_binary(msg) and not is_nil(msg) ->
            {:error, :commit_title}

          toml ->
            status =
              toml.status
              |> Enum.map(&GitHub.map_changed_status/1)
              |> Enum.uniq()

            pr_status =
              toml.pr_status
              |> Enum.map(&GitHub.map_changed_status/1)
              |> Enum.uniq()

            cond do
              Enum.count(status) != Enum.count(toml.status) ->
                {:error, :status}

              Enum.count(pr_status) != Enum.count(toml.pr_status) ->
                {:error, :pr_status}

              true ->
                {:ok, %{toml | status: status, pr_status: pr_status}}
            end
        end

      {:error, _error} ->
        {:error, :parse_failed}
    end
  end
end
