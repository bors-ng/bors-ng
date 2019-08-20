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
          file_pattern: String.t,
          approvers: [String.t]
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
  @spec list_required_reviews(%BorsNG.CodeOwners{}, [%BorsNG.GitHub.File{}]) :: [[String.t]]
  def list_required_reviews(code_owners, files) do
    Logger.debug("Code Owners: #{inspect(code_owners)}")
    Logger.debug("Files modified: #{inspect(files)}")

    required_reviewers =
      Enum.map(files, fn x ->
         # Convert each file to an array of matching owners
         pats = Enum.map(code_owners.patterns, fn owner ->
            cond do
              # glob matches has an extra '/' in it, don't match on it
             :glob.matches(x.filename, owner.file_pattern) && !:glob.matches(x.filename, owner.file_pattern <> "/*")  ->
                owner.approvers
             String.starts_with?(x.filename, owner.file_pattern) ->
              owner.approvers
             true ->
              nil # if unknown fall through
            end
          end)

        # Remove any nil entries (indicating review not required)
        # Pick the last matching entry (entries further down in the file have higher priority
        pats =
          Enum.reduce(pats, nil, fn x, acc ->
            if x != nil do
              x
            else
              acc
            end
          end)
      end)

    required_reviewers = Enum.filter(required_reviewers, fn x -> x != nil end)

    Logger.debug("Required reviewers: #{inspect(required_reviewers)}")

    required_reviewers
  end

  @spec parse_file(String.t) :: {:ok, %BorsNG.CodeOwners{}}
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
      lines = Enum.map(lines, fn x ->
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
