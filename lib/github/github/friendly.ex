defmodule BorsNG.GitHub.FriendlyMock do
  @moduledoc """
  Helper functions for ServerMock for common operations without having to
  modify state by hand.

  Tries to lookup values instead of requiring full %{} associative arrays.

  Does everything through webhook notifications. Do not use Repo.insert
  directly!
  """

  alias BorsNG.GitHub.ServerMock
  alias BorsNG.GitHub.FriendlyMock
  alias BorsNG.GitHub.Pr
  #alias BorsNG.Database.Installation
  #alias BorsNG.Database.Project
  alias BorsNG.WebhookController

  # Defaults
  @def_user %{"id" => 7,
	      "login" => "tester",
	      "avatar_url" => "" }
  @def_inst 91
  @def_repo 14
  @def_files %{".github/bors.toml" => ~s"""
    status = [ "ci" ]
    pr_status = [ "ci" ]
    delete_merged_branches = true
    """}
  
  def init_state() do
    # Creates a single installation with a single repo where
    # nothing has happened yet.
    # Will do everything through webhook notifications. 
    #inst = %Installation{installation_xref: @def_inst}
    #|> Repo.insert!()
    #proj = %Project{
    #  installation_id: inst.id,
    #  repo_xref: @def_repo,
    #  staging_branch: "staging",
    #  trying_branch: "trying"}
    #|> Repo.insert!()
    # Would need more if we wanted to also be able to _list_ repos!
    ServerMock.put_state(%{
      {:installation, 91} => %{ repos: [
          %BorsNG.GitHub.Repo{
	    id: @def_repo,
	    name: "test/repo",
	    owner: %{type: :user,
		     id: @def_user["id"],
		     login: @def_user["login"],
		     avatar_url: @def_user["avatar_url"]}}
      ] },
      {{:installation, @def_inst}, @def_repo} => %{
        branches: %{"master" => "ini"},
        commits: %{},
        comments: %{},
        statuses: %{},
        files: %{"master" => @def_files,
		 "staging.tmp" => @def_files},
	collaborators: %{},
	pulls: %{},
	pr_commits: %{}
      }})
    WebhookController.do_webhook(%{
	  body_params: %{
	    "installation" => %{ "id" => @def_inst },
	    "sender" => @def_user,
	    "action" => "created" }}, "github", "installation")
    BorsNG.Worker.SyncerInstallation.wait_hot_spin_xref(@def_inst)
  end

  def prs(repo \\ @def_repo, inst \\ @def_inst) do
    # How can I get both open and unopen PRs?
    BorsNG.GitHub.get_open_prs!({{:installation, inst}, repo})
  end

  def comments(repo \\ @def_repo, inst \\ @def_inst) do
    conn = {{:installation, inst}, repo}
    state = ServerMock.get_state
    with({:ok, repo} <- Map.fetch(state, conn),
         {:ok, comments} <- Map.fetch(repo, :comments),
      do: comments)
  end

  def add_pr(title, body \\ nil) do
    # branch name == title for now
    number = 1 + Enum.max([0 | Enum.map(prs(), fn x -> x.number end)])
    sha = "SHA-#{number}"
    ref = title
    pr = %Pr{number: number,
	     title: title,
	     state: :open,
	     base_ref: "master",
	     head_sha: sha,
	     head_ref: ref,
	     body: body,
	     user: @def_user}
    update_mock([:pulls], &(Map.put(&1, number, pr)))
    update_mock([:pr_commits], &(Map.put(&1, number, [])))
    update_mock([:comments], &(Map.put(&1, number, [])))
    update_mock([:branches], &(Map.put(&1, ref, sha)))
    update_mock([:files], &(Map.put(&1, sha, @def_files)))
    update_mock([:statuses], &(Map.put(&1, sha, %{})))
    WebhookController.do_webhook(%{
    	  body_params: %{
    	    "installation" => %{ "id" => @def_inst },
    	    "sender" => @def_user,
    	    "repository" => %{ "id" => @def_repo},
    	    "pull_request" => pr_to_json(pr),
    	    "action" => "created" }},
          "github", "pull_request")
    number
    #%{body_params: %{
    #	    "installation" => %{ "id" => @def_inst },
    #	    "sender" => @def_user,
    #	    "repository" => %{ "id" => @def_repo},
    #	    "pull_request" => pr_to_json(pr),
    #	    "action" => "created" }}
  end

  def update_mock(path, fun, repo \\ @def_repo, inst \\ @def_inst) do
    path = [{{:installation, inst}, repo} | path]
    ServerMock.put_state(update_in(ServerMock.get_state, path, fun))
  end

  def commits(pr_num, repo \\ @def_repo, inst \\ @def_inst) do
    BorsNG.GitHub.get_pr_commits!({{:installation, inst}, repo}, pr_num)
  end

  def add_commit(pr_num, sha, author) do
    commit = %{sha: sha,
	       author_name: author,
	       author_email: author <> "'s email"}
    # Could maybe prepend to make things faster
    update_mock([:pr_commits, pr_num], &(&1 ++ [commit]))
  end

  def add_comment(pr_num, body, author \\ @def_user) do
    pr = Enum.find(prs(), &(match?(%{number: ^pr_num}, &1)))
    # number = 1 + Enum.max([0 | Enum.map(comments(), fn x -> x.number end)])
    #comment = [body]
    #update_mock([:comments], &(Map.put(&1, pr_num, comment)))
    update_mock([:comments, pr_num], &([body | &1]))
    WebhookController.do_webhook(
      %{
	  body_params: %{
	    "sender" => author,
    	    "repository" => %{ "id" => @def_repo},
	    "comment" => %{ "user" => author,
			    "body" => body },
	    "pull_request" => pr_to_json(pr),
	    "action" => "created" }} , "github", "pull_request_review_comment")
  end

  def make_admin(username \\ @def_user["login"]) do
    alias BorsNG.Database
    user = Database.Repo.get_by! Database.User, login: username
    Database.Repo.update! Database.User.changeset(user, %{is_admin: true})
  end


  def add_reviewer(repo \\ @def_repo, user \\ @def_user) do
    alias BorsNG.Database
    alias BorsNG.Database.Repo
    #use Phoenix.ConnTest

    #import Ecto
    #import Ecto.Changeset
    #import Ecto.Query

    #import BorsNG.Router.Helpers
    # Could instead post html instead of calling add_reviewer directly.
    # See test/controllers/project_controller_test.exs
    #phx_conn = Phoenix.ConnTest.build_conn()
    project = Repo.get_by!(Database.Project, %{repo_xref: repo})
    BorsNG.ProjectController.add_reviewer(nil, :rw, project, %{"reviewer" => user})
    #conn = conn
    #|> login()
    #|> post(
    #  project_path(conn, :add_reviewer, project),
    #%{"reviewer" => %{"login" => "case"}})
    #resp = conn
    #|> get(redirected_to(conn, 302))
    #|> html_response(200)
  end

  def ci_status(hash, ci_name, status) do
    update_mock([:statuses, hash], &(Map.put(&1, ci_name, status)))
  end

  def full_example() do
    alias BorsNG.GitHub.FriendlyMock
    alias BorsNG.Database
    # ServerMock.put_state(old_state)
    FriendlyMock.init_state
    FriendlyMock.make_admin
    FriendlyMock.add_pr "first"
    #FriendlyMock.add_pr "First pull request"
    FriendlyMock.add_pr "Second pull request"
    FriendlyMock.add_commit(2, "000002", "Tester")
    FriendlyMock.add_commit(2, "000003", "Tester")
    FriendlyMock.add_comment(2, "Hello world")
    Database.Repo.all Database.User
    Database.Repo.all Database.Project
    Database.Repo.all Database.Patch
    FriendlyMock.add_reviewer
    FriendlyMock.add_comment(2, "bors r+")
    ServerMock.get_state
  end

  def run_once() do
    alias BorsNG.GitHub.FriendlyMock
    alias BorsNG.Database
    FriendlyMock.init_state
    FriendlyMock.make_admin
    FriendlyMock.add_pr "first"
    FriendlyMock.add_reviewer
    FriendlyMock.ci_status("SHA-1", "ci", :running)
    FriendlyMock.add_comment(1, "bors ping")
    FriendlyMock.add_comment(1, "bors r+")
    #FriendlyMock.ci_status("SHA-1", "ci", :ok)
  end

  def pr_to_json(%Pr{number: number,
		     title: title,
		     state: state,
		     base_ref: base_ref,
		     head_sha: head_sha,
		     body: body,
		     user: user}) do
    %{
    "number" => number,
    "title" => title,
    "body" => body,
    "state" => Atom.to_string(state),
    "base" => %{
      "ref" => base_ref,
      "repo" => %{
        "id" => 0 #base_repo_id
      }
    },
    "head" => %{
      "sha" => head_sha,
      "ref" => "0000",
      "repo" => %{
        "id" => "0"
      }
    },
    "user" => user,
    "merged_at" => "some non-nul time :)",
    }
  end
end
