

defmodule BorsNG.CodeOwners do

  @type tjson :: map
  @type t :: %BorsNG.CodeOwners{
               patterns: [BorsNG.FilePattern],
             }
  defstruct(
    patterns: [],
  )
end

defmodule BorsNG.FilePattern do


  @type tjson :: map
  @type t :: %BorsNG.FilePattern{
               file_pattern: bitstring,
               approvers: [bitstring],
             }
  defstruct(
    file_pattern: "",
    approvers: {},
  )
end


defmodule BorsNG.CodeOwnerParser do

  # Returns a list of lists
  # Items in the inner lists are joined by an OR statement
  # Items in the the outer list are joined by an AND statement
  # [ [A], [A, B], [A, C] -> A and (A or B) and (A or C)
  @spec list_required_reviews(BorsNG.CodeOwners, [GitHub.File] ) :: [[bitstring]]
  def list_required_reviews(code_owners, files) do

    IO.inspect(code_owners)
    IO.inspect(files)

    pats = Enum.map(files, fn x ->

      pats = Enum.map(code_owners.patterns, fn owner ->

         if :glob.matches(x.filename, owner.file_pattern) do
           owner.approvers
         end


      end)

      IO.inspect(pats)

      pats = Enum.reduce(pats, fn x, acc ->
        if x != nil do
          x
        else
          acc
        end

      end)

      IO.inspect(pats)


    end)

    IO.inspect(pats)
    pats

  end

  @spec parse_file(bitstring) :: BorsNG.CodeOwners
  def parse_file(file_contents) do
    lines = String.split(file_contents, "\n")

    # Remove empty lines
    lines = Enum.filter(lines, fn x -> String.length(String.trim(x)) > 0 end)
    # Remove comment lines
    lines = Enum.filter(lines, fn x -> String.at(String.trim(x), 0) != "#" end)

    IO.inspect(lines)

    patterns = Enum.map(lines, fn x ->
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