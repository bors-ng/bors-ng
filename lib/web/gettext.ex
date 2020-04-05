defmodule BorsNG.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:

      import BorsNG.Gettext

      # Simple translation
      gettext "Here is the string to translate"

      # Plural translation
      ngettext "Here is the string to translate",
               "Here are the strings to translate",
               3

      # Domain-based translation
      dgettext "errors", "Here is the error message to translate"

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """

  @dialyzer [
    {:nowarn_function, "MACRO-dgettext": 3},
    {:nowarn_function, "MACRO-dgettext": 4},
    {:nowarn_function, "MACRO-dngettext": 5},
    {:nowarn_function, "MACRO-dngettext": 6},
    {:nowarn_function, "MACRO-ngettext_noop": 3}
  ]

  use Gettext, otp_app: :bors
end
