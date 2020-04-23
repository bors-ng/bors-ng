require Logger

defmodule BorsNG.CodeOwners do
  @type tjson :: map
  @type t :: %BorsNG.CodeOwners{
          patterns: [BorsNG.FilePattern]
        }
  defstruct(patterns: [])
end

defmodule BorsNG.FilePattern do
  @type tjson :: map
  @type t :: %BorsNG.FilePattern{
          file_pattern: String.t(),
          approvers: [String.t()]
        }
  defstruct(
    file_pattern: "",
    approvers: {}
  )
end

defmodule BorsNG.CodeOwnerParser do
  # Returns a list of lists
  # Items in the inner lists are joined by an OR statement
  # Items in the the outer list are joined by an AND statement
  # [[A], [A, B], [A, C]] -> A and (A or B) and (A or C)
  @spec list_required_reviews(%BorsNG.CodeOwners{}, [%BorsNG.GitHub.File{}]) :: [[String.t()]]
  def list_required_reviews(code_owners, files) do
    Logger.debug("Code Owners: #{inspect(code_owners)}")
    Logger.debug("Files modified: #{inspect(files)}")

    required_reviewers =
      Enum.map(files, fn x ->
        # Convert each file to an array of matching owners
        pats =
          Enum.map(code_owners.patterns, fn owner ->
            cond do
              String.equivalent?("*", owner.file_pattern) ->
                owner.approvers

              String.contains?(owner.file_pattern, "**") &&
                  process_double_asterisk(x.filename, owner.file_pattern) ->
                owner.approvers

              # If the patterh starts with a slask, only match the root dir
              String.starts_with?(owner.file_pattern, "/") &&
                :glob.matches("/" <> x.filename, owner.file_pattern) &&
                  !:glob.matches(x.filename, owner.file_pattern <> "/*") ->
                owner.approvers

              # For patterns that doesn't start with a leading /, the pattern is
              # the equivalent of "**/{pattern}"
              !String.starts_with?(owner.file_pattern, "/") &&
                :glob.matches(x.filename, "**" <> owner.file_pattern) &&
                  !:glob.matches(x.filename, owner.file_pattern <> "/*") ->
                owner.approvers

              # For non glob patterns, if the patterh starts with a slash, only match the root dir
              String.starts_with?(owner.file_pattern, "/") &&
                  String.starts_with?("/" <> x.filename, owner.file_pattern) ->
                owner.approvers

              !String.starts_with?(owner.file_pattern, "/") &&
                  String.contains?(x.filename, owner.file_pattern) ->
                owner.approvers

              true ->
                # if unknown fall through
                nil
            end
          end)

        # Remove any nil entries (indicating review not required)
        # Pick the last matching entry (entries further down in the file have higher priority
        pats
        |> Enum.reduce([], fn x, acc ->
          if x != nil do
            x
          else
            acc
          end
        end)
        # If the last matching entry is @ghost, ignore it (it's a null owner on GH)
        |> Enum.filter(fn x ->
          !String.equivalent?("@ghost", x)
        end)
      end)

    required_reviewers = Enum.filter(required_reviewers, fn x -> Enum.count(x) > 0 end)

    Logger.debug("Required reviewers: #{inspect(required_reviewers)}")

    required_reviewers
  end

  @spec process_double_asterisk(String.t(), String.t()) :: boolean
  def process_double_asterisk(file_name, file_pattern) do
    double_asterisk = "**"

    cond do
      String.starts_with?(file_pattern, double_asterisk) ->
        pattern = String.trim_leading(file_pattern, double_asterisk)
        String.contains?(file_name, pattern)

      String.ends_with?(file_pattern, double_asterisk) ->
        pattern = String.trim_trailing(file_pattern, double_asterisk)
        String.starts_with?(file_name, pattern)

      String.contains?(file_pattern, double_asterisk) ->
        patterns = String.split(file_pattern, double_asterisk, parts: 2)

        String.starts_with?(file_name, List.first(patterns)) &&
          String.contains?(file_name, List.last(patterns))
    end
  end

  @spec parse_file(String.t()) :: {:ok, %BorsNG.CodeOwners{}}
  def parse_file(file_contents) do
    # Empty codeowners file
    if file_contents == nil do
      owners = %BorsNG.CodeOwners{
        patterns: []
      }

      {:ok, owners}
    else
      lines = String.split(file_contents, "\n")

      # Remove any comments from the file
      lines =
        Enum.map(lines, fn x ->
          String.replace(x, ~r/#.*/, "")
        end)

      # Remove empty lines
      lines = Enum.filter(lines, fn x -> String.length(String.trim(x)) > 0 end)

      patterns =
        Enum.map(lines, fn x ->
          segments = String.split(x)
          approvers = Enum.slice(segments, 1, Enum.count(segments) - 1)

          %BorsNG.FilePattern{
            file_pattern: Enum.at(segments, 0),
            approvers: approvers
          }
        end)

      owners = %BorsNG.CodeOwners{
        patterns: patterns
      }

      {:ok, owners}
    end
  end
end
