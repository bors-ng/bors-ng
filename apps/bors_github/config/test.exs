use Mix.Config

config :bors_github, :server, BorsNG.GitHub.ServerMock
config :bors_github, :oauth2, BorsNG.GitHub.OAuth2Mock
