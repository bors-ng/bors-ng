use Mix.Config
alias Dogma.Rule

config :dogma,
  # Select a set of rules as a base
  rule_set: Dogma.RuleSet.All,
  exclude: [
    ~r(\Aconfig/)
  ],

  # Override an existing rule configuration
  override: [
    %Rule.PipelineStart{enabled: false}
  ]
