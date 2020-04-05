defmodule BorsNG.Database.Installation do
  @moduledoc """
  A GitHub installation.

  See: https://developer.github.com/early-access/integrations/
  """

  use BorsNG.Database.Model

  @type xref :: integer

  schema "installations" do
    field(:installation_xref, :integer)

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:installation_xref])
    |> validate_required([:installation_xref])
  end
end
