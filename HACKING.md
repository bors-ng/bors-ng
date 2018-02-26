The innards of Bors-NG
======================

Bors-NG uses Ecto for all permanent data storage
and Phoenix to implement the webserver portion
(which is responsible for both the dashboard frontend and GitHub webhooks).
Bors-NG also has a number of worker GenServers,
to help isolate different projects from each other and perform background processing.

You'll also want to do some terminology mapping between what we say to users and what we say in the code:

  * Project → Repo: A Bors "Project" corresponds to a GitHub "Repo."
                    We do this renaming because Ecto already has the concept of a Repo.
  * Attempt → Try: Try is a keyword in Elixir, and in a lot of other languages besides,
                   so the code calls a try an attempt.
  * Patch → PR: A Bors "Patch" corresponds to a GitHub "Pull Request."

<!---->

The frontend
------------

In the source tree, you'll find the frontend in the `lib/web` folder.
There is also a webhook controller in the `lib/web/controllers` folder.
This isn't really part of the frontend, because the user won't be interacting with it,
but rather GitHub will POST to it when comments are left, builds are completed,
and new GitHub repositories are associated with our integration.
The webhook controller is on a separate Plug pipeline for this reason.


The backend
-----------

In `lib/worker`, the worker GenServers are implemented.

### `Worker.Batcher` and `Worker.Attemptor`

Batcher handles "r+"-ed patches, which the user is attempting to land in master.
Attemptor handles "try"-ed patches.

Batcher and Attemptor both have about the same structure:
each project has zero or one instance of these workers at any time,
and a registry GenServer lazily creates an instance if it's needed and none exists.

The webhook controller sends a message to the appropriate worker when the user
posts the comment on a pull request.
The webhook controller also delivers status notifications for running builds,
and the server will poll GitHub every half-hour just in case.

These servers also keep all their state written to Ecto,
so bors can pick up where it left off if it's restarted.


The GitHub glue
---------------

Found in the folder `lib/github`.

### GitHub.Server

All requests made to GitHub's REST API
(except a couple things related to oAuth) go through the "GitHub API server."
This server keeps a cache of installation tokens
(so we don't constantly re-request them) and is responsible for rate limiting.
It can be replaced with `GitHub.ServerMock`, for local testing.
