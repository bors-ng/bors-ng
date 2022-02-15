defmodule DynamicEctoRepoWrapper do
  @moduledoc """
  Exposes a macro to define Ecto.Repo functions dynamically.
  """
  defmacro create_ecto_repo_callback(args, name) do
    quote bind_quoted: [args: args, name: name] do
      def unquote(name)(unquote_splicing(args)) do
        repo = :persistent_term.get(:db_repo)
        apply(repo, unquote(name), unquote(args))
      end
    end
  end

  def create_ecto_repo_callback_args(_, 0) do
    []
  end

  def create_ecto_repo_callback_args(module, arity) do
    Enum.map(1..arity, &Macro.var(:"arg#{&1}", module))
  end
end

defmodule BorsNG.Database.Repo do
  @moduledoc """
  This is an Ecto.Repo wrapper that defines all callback functions.
  """
  import DynamicEctoRepoWrapper

  @ecto_repo_callbacks Path.join([__DIR__, "repo_callbacks.txt"])
                       |> File.read!()
                       |> String.trim()
                       |> String.split("\n")
                       |> Enum.map(fn line ->
                         [line, arity] = line |> String.split("/") |> Enum.map(&String.trim(&1))
                         {String.to_atom(line), String.to_integer(arity)}
                       end)

  @ecto_repo_callbacks
  |> Enum.flat_map(fn
    {callback, arity} when arity >= 1 ->
      is_defined = Enum.any?(@ecto_repo_callbacks, fn fun -> fun == {callback, arity - 1} end)

      if is_defined,
        do: [{callback, arity}],
        else: [{callback, arity}, {callback, arity - 1}]

    {callback, arity} ->
      [{callback, arity}]
  end)
  |> Enum.map(fn {callback, arity} ->
    __MODULE__
    |> create_ecto_repo_callback_args(arity)
    |> create_ecto_repo_callback(callback)
  end)
end
