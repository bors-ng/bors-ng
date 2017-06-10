defmodule BorsNG.PermissionDeniedError do
  @moduledoc """
  When a controller detects that the user is doing something they shouldn't,
  it raises this error.
  """
  defexception plug_status: 403, message: "Permission denied"
end
