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
    Enum.each(owner_file.patterns, fn x -> assert x.approvers == ["@my_org/my_team"] end)
  end

  test "Parse file with trailing comments " do

    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_2")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    assert Enum.count(owner_file.patterns) == 2
    Enum.each(owner_file.patterns, fn x -> assert x.approvers == ["@my_org/my_team"] end)
  end

  test "Parse file with multiple teams" do

    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_3")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    assert Enum.count(owner_file.patterns) == 1
    Enum.each(owner_file.patterns, fn x -> assert x.approvers == ["@my_org/my_team", "@my_org/my_other_team"] end)
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
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/my_team"
  end

end