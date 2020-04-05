defmodule BorsNG.FriendlyMockTest do
  use BorsNG.Worker.TestCase

  alias BorsNG.GitHub.FriendlyMock

  setup do
    FriendlyMock.init_state()
    # Can't figure out why syncing doesn't add the user.
    # Probably because we're missing all the Supervisors?
    BorsNG.Database.Repo.insert!(%BorsNG.Database.User{
      user_xref: 7,
      login: "tester"
    })

    FriendlyMock.make_admin()
    {:ok, inst: 91, proj: 14}
  end

  test "pr creation" do
    assert 1 = FriendlyMock.add_pr("first")
    assert 2 = FriendlyMock.add_pr("second")
  end

  test "add reviewer" do
    FriendlyMock.add_pr("first")
    assert {:ok, "Successfully added tester as a reviewer"} = FriendlyMock.add_reviewer()
    assert {:error, "This user is already a reviewer"} = FriendlyMock.add_reviewer()
  end

  test "add comment", %{inst: inst, proj: proj} do
    pr_num = FriendlyMock.add_pr("first")
    FriendlyMock.add_reviewer()
    FriendlyMock.add_comment(pr_num, "bors ping")

    assert %{1 => ["pong", "bors ping"]} =
             FriendlyMock.get_state()[{{:installation, inst}, proj}][:comments]
  end

  test "set ci status", %{inst: inst, proj: proj} do
    FriendlyMock.add_pr("first")
    assert :ok = FriendlyMock.ci_status("SHA-1", "ci", :running)

    assert %{"SHA-1" => %{"ci" => :running}} =
             FriendlyMock.get_state()[{{:installation, inst}, proj}][:statuses]
  end

  # Doesn't work without batchers running
  #   test "full test to bors r+" do
  #     pr_num = FriendlyMock.add_pr "first"
  #     FriendlyMock.add_reviewer
  #     FriendlyMock.ci_status("SHA-1", "ci", :ok)
  #     FriendlyMock.add_comment(pr_num, "bors ping")
  #     FriendlyMock.add_comment(pr_num, "bors r+")
  #     BorsNG.Worker.Batcher.handle_info({:poll, :once}, 91)
  #     assert %{"SHA-1" => %{"bors" => :running, "ci" => :ok}} = FriendlyMock.get_state()[{{:installation, 91}, 14}][:statuses]
  #   end
end
