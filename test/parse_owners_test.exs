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

    Enum.each(owner_file.patterns, fn x ->
      assert x.approvers == ["@my_org/my_team", "@my_org/my_other_team"]
    end)
  end

  test "Test direct file matching" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_1")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "secrets.json"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/my_team"
  end

  test "Test glob matching file matching" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_4")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "src/github.com/go/double/double.go"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/go_reviewers"
  end

  test "Test infinite depth glob matching" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_4")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "build/logs/github.com/go/double/double.go"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/my_team"
  end

  test "Test single depth glob matching - no match" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_5")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "docs/github.com/go/double/double.go"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 0
  end

  test "Test single depth glob matching - match" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_4")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "docs/double.go"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/my_other_team"
  end

  test "Test Asterisk" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_6")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "some_folder/some_file"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 2
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/my_team"
    assert Enum.at(Enum.at(reviewers, 0), 1) == "@my_org/my_other_team"
  end

  test "Test Double Asterisk in the middle" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_7")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "src/file1/test"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/test_team_2"
  end

  test "Test Double Asterisk in the beggining" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_7")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "file0/file1/test"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/test_team"
  end

  test "Test Double Asterisk in the end" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_7")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "other/file1/file2"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/other_team"
  end

  test "Test double asterix matches rule with leading slash (specific rule matches)" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "foo/a/b/c.yaml"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 2
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-b"
    assert Enum.at(Enum.at(reviewers, 0), 1) == "@my_org/team-c"
  end

  test "Test double asterix matches rule with leading slash (catch all rule matches)" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{
        filename: "something/else.exs"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/catch-all"
  end

  test "Test double asterix matches rule with leading slash (require catch all and specific)" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "foo/a/b/c.yaml"},
      %BorsNG.GitHub.File{filename: "something/else.exs"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 2
    assert Enum.count(Enum.at(reviewers, 0)) == 2
    assert Enum.count(Enum.at(reviewers, 1)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-b"
    assert Enum.at(Enum.at(reviewers, 0), 1) == "@my_org/team-c"
    assert Enum.at(Enum.at(reviewers, 1), 0) == "@my_org/catch-all"
  end

  test "Test double asterix matches rule without leading slash (catch all rule matches)" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "bar/hello/world.css"},
      %BorsNG.GitHub.File{filename: "something/else.exs"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 2
    assert Enum.count(Enum.at(reviewers, 0)) == 2
    assert Enum.count(Enum.at(reviewers, 1)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-d"
    assert Enum.at(Enum.at(reviewers, 0), 1) == "@my_org/team-e"
    assert Enum.at(Enum.at(reviewers, 1), 0) == "@my_org/catch-all"
  end

  test "Test double asterix matches rule without leading slash anywhere in tree" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "somewhere/deep/below/bar/hello/world.css"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 2
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-d"
    assert Enum.at(Enum.at(reviewers, 0), 1) == "@my_org/team-e"
  end

  test "Test no leading slash matches any dir (matches subdir)" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "another/path/no_leading/foo.txt"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-no-leading"
  end

  test "Test no leading slash matches any dir (matches root)" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "/no_leading/foo.txt"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-no-leading"
  end

  test "Test with leading slash matches only root" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "with_leading/foo.txt"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/team-with-leading"
  end

  test "Test with leading slash does not match non root dir" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_8")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "something_else/with_leading/foo.txt"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@my_org/catch-all"
  end

  test "Test @ghost user means no ownership" do
    IO.inspect(File.cwd())
    {:ok, codeowner} = File.read("test/testdata/code_owners_9")

    {:ok, owner_file} = BorsNG.CodeOwnerParser.parse_file(codeowner)

    files = [
      %BorsNG.GitHub.File{filename: "docs/dog"}
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 1
    assert Enum.count(Enum.at(reviewers, 0)) == 1
    assert Enum.at(Enum.at(reviewers, 0), 0) == "@owners/cat"

    files = [
      %BorsNG.GitHub.File{
        filename: "docs/cat"
      }
    ]

    reviewers = BorsNG.CodeOwnerParser.list_required_reviews(owner_file, files)

    assert Enum.count(reviewers) == 0
  end
end
