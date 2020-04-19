defmodule BorsNG.Database.UserTest do
  use BorsNG.Database.ModelCase

  alias BorsNG.Database.User

  setup do
    user =
      Repo.insert!(%User{
        user_xref: 1,
        login: "fooBAR"
      })

    {:ok, user: user}
  end

  test "case insensitive search", %{user: u} do
    user = Repo.get_by(User, login: "foobar")
    assert user.id == u.id
  end
end
