defmodule BorsNG.Worker.Batcher.Hooks do
  def invoke(hook, phase, repository, work_branch, target_branch, commit_id, project) do
    body = Jason.encode!(%{
      "phase" => phase,
      "repository" => repository,
      "work-branch" => work_branch,
      "target-branch" => target_branch,
      "commit-id" => commit_id,
      "timeout" => 60,
      "callback" => "#{BorsNG.Endpoint.url()}/webhook/callback/#{hook.identifier}"
    })
    signature = :crypto.mac(:hmac, :sha256, :erlang.binary_to_list(project.hook_secret), :erlang.binary_to_list(body))
                |> Base.encode16(case: :lower)
    tesla_client()
    |> Tesla.post!(hook.url, body, headers: [{"x-bors-ng-signature", "sha256-hmac=#{signature}"}])
  end

  defp tesla_client() do
    middleware = [
      {Tesla.Middleware.Headers,
        [
          {"user-agent", "bors-ng https://bors.tech"}
        ]},
      {Tesla.Middleware.Retry, delay: 100, max_retries: 5}
    ]

    middleware =
      if Confex.get_env(:bors, :log_outgoing, false) do
        middleware ++ [{Tesla.Middleware.Logger, filter_headers: ["authorization"], debug: true}]
      else
        middleware
      end

    params =
      [
        # TODO: should these be customized? (ie not just copy what we use for github)
        connect_timeout: Confex.get_env(:bors, :api_github_timeout, 8_000) - 1,
        recv_timeout: Confex.get_env(:bors, :api_github_timeout, 8_000) - 1
      ] ++
        case System.get_env("HTTPS_PROXY") do
          nil ->
            []

          proxy ->
            [proxy: proxy]
        end

    Tesla.client(
      middleware,
      {Tesla.Adapter.Hackney, params}
    )
  end
end
