defmodule BorsNG.Worker.Batcher.BorsToml do
  @moduledoc """
  The format for `bors.toml`. It looks like this:

      status = [
        "continuous-integration/travis-ci/push",
        "continuous-integration/appveyor/branch"]

      block_labels = [ "S-do-not-merge-yet" ]

      pr_status = [ "continuous-integration/travis-ci/pull" ]
  """

  defstruct status: [], block_labels: [], pr_status: [],
    timeout_sec: (60 * 60),
    required_approvals: 0,
    cut_body_after: nil,
    delete_merged_branches: false

  @type t :: %BorsNG.Worker.Batcher.BorsToml{
    status: [binary],
    block_labels: [binary],
    pr_status: [binary],
    timeout_sec: integer,
    required_approvals: integer,
    cut_body_after: binary | nil,
    delete_merged_branches: boolean}

  @type err :: :status |
    :block_labels |
    :pr_status |
    :timeout_sec |
    :required_approvals |
    :cut_body_after |
    :empty_config |
    :parse_failed

  @spec new(binary) :: {:ok, t} | {:error, err}
  def new(str) when is_binary(str) do
    case :etoml.parse(str) do
      {:ok, toml} ->
        toml = toml
        |> Enum.map(fn {key, val} -> {String.replace(key, "-", "_"), val} end)
        |> Map.new()
        toml = %BorsNG.Worker.Batcher.BorsToml{
          status: Map.get(toml, "status", []),
          block_labels: Map.get(toml, "block_labels", []),
          pr_status: Map.get(toml, "pr_status", []),
          timeout_sec: Map.get(toml, "timeout_sec", 60 * 60),
          required_approvals: Map.get(toml, "required_approvals", 0),
          cut_body_after: Map.get(toml, "cut_body_after", nil),
          delete_merged_branches: Map.get(toml,
                                          "delete_merged_branches",
                                          false)
        }
        case toml do
          %{status: status} when not is_list status ->
            {:error, :status}
          %{block_labels: block_labels} when not is_list block_labels ->
            {:error, :block_labels}
          %{pr_status: pr_status} when not is_list pr_status ->
            {:error, :pr_status}
          %{timeout_sec: timeout_sec} when not is_integer timeout_sec ->
            {:error, :timeout_sec}
          %{required_approvals: req_approve} when not is_integer req_approve ->
            {:error, :required_approvals}
          %{cut_body_after: c} when (not is_binary c) and (not is_nil c) ->
            {:error, :cut_body_after}
          %{status: [], block_labels: [], pr_status: []} ->
            {:error, :empty_config}
          toml -> {:ok, toml}
        end
      {:error, _error} -> {:error, :parse_failed}
    end
  end

end
