defmodule BorsNG.Database.CodeOwners do
  
    use BorsNG.Database.Model
  
    @type t :: %__MODULE__{}
    @type id :: pos_integer
  
    schema "code_owners" do
      field :name, :string
    end
  
    @spec changeset(t | Ecto.Changeset.t, map) :: Ecto.Changeset.t
    @doc """
    Builds a changeset based on the `struct` and `params`.
    """
    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, [
        :name])
      |> unique_constraint(:name, name: :code_owners_name_index)
    end

    @spec all_for_patch(Patch.id) :: Ecto.Queryable.t
    def all_for_patch(patch_id) do
      from c in CodeOwners,
        join: l in LinkPatchCodeOwners, on: l.code_owners_id == c.id,
        where: l.patch_id == ^patch_id
    end
end