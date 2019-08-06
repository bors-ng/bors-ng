defmodule BorsNG.ParseTest do
  use ExUnit.Case

  test "BorsNG.FilePattern can exist" do
    %BorsNG.FilePattern{}
  end

  test "BorsNG.CodeOwners can exist" do
    %BorsNG.CodeOwners{}
  end

  test "Parse simple file" do

    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_1")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    assert Enum.count(owner_file.patterns) == 3
  end

  test "File match test" do

    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_1")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [%BorsNG.GitHub.File{
      filename: "secrets.json"
    }]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@plaid/platform-team"
  end

end