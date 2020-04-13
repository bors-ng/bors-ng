A merge bot for GitHub pull requests
====================================

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/bors-ng/bors-ng)

[![Bors enabled](https://bors.tech/images/badge_small.svg)](https://app.bors.tech/repositories/3)

[Bors-NG] implements a continuous-testing workflow where the master branch never breaks.
It integrates GitHub pull requests with a tool like [Travis CI] that runs your tests.

Other resources:

* [Home page](https://bors.tech/)
* [Documentation](https://bors.tech/documentation/)
* [Support forum](https://forum.bors.tech/)
* [Publicly hosted instance (public repositories only)](https://app.bors.tech/)


# But don't GitHub's Protected Branches already do this?

Travis and Jenkins both run the test suite on every branch after it's pushed to
and every pull request when it's opened, and GitHub can block the pull requests
if the tests fail on them. To understand why this is insufficient to get an
evergreen master, imagine this:

  * #### Pull Request \#1: Rename `bifurcate()` to `bifurcateCrab()`

    Change the name of this function, as well as every call site that currently
    exists in master. I've thought of making it a method on Crab instead of on
    Sword, but then it would be `bifurcateWithSword()`, which hardly seems like
    an improvement.

  * #### Pull Request \#2: `bifurcate()` after landing, in addition to before

    Adds another call to `bifurcate()`, to make sure it gets done even if we
    skip the pre-landing procedure.

When both of these pull requests are sitting open in the backlog, they will
both be tested against master. Assuming they both pass, GitHub will happily
present the Big Green Merge Button. Once they both get merged master will
go red (Method `bifurcate()` not found).

In addition to the testing requirements, GitHub can also be set to block pull
requests that are not "up to date" with master, meaning that problems like this
can show up. This fixes the problem, by requiring that master only contain a
snapshot of the code that has passed the tests, but it requires maintainers to
manually:

 1. "Update the pull requests," merging them onto master without changing
    master itself
 2. Wait for the test suite to finish
 3. Merge the pull request when it's done, which is a trivial operation that
    can't break the test suite thanks to step 1

And it has to be done for every pull request one at a time.

This is similar to, but less efficient than, the process that bors automates.
Instead of merging, you add reviewed pull requests to a "merge queue" of pull
requests that are tested against master by copying master to a staging branch
and merging into that. When the status of staging is determined (either pass or fail),
bors reports the result back as a comment and merges staging into master if it was a pass.
Then it goes on to the next one.
Based on the assumption that the tests usually pass once they're r+-ed,
bors actually tests them in batches (and bisects if a batch fails).

Note that bors is not a replacement for Jenkins or Travis. It just implements
this workflow.


# How it works

Bors is a [GitHub Application], so (assuming you already have Travis CI set up), getting bors set up requires two steps:

 1. Add the app to your repo in GitHub. [Click here to use the publicly hosted instance.](https://github.com/apps/bors/installations/new)
 2. Commit a bors.toml with these contents:

        status = ["continuous-integration/travis-ci/push"]

To use it, you need to stop clicking the big green merge button, and instead leave a comment with this in it on any pull request that looks good to you:

    bors r+

As commits are reviewed, bors lumps them into a queue of batches. If everything passes, there will just be two batches; the one that's running, and the one that's waiting to be run (and is accumulating more and more pull requests until it gets a chance to run).

To run a batch, bors creates a merge commit, merging master with all the pull requests that make up the batch. Instead of pushing the merge commit to `master` immediately, however, it will instead push it to the `staging` branch. They'll look like this:

    Merge #5 #7 #8

    5: Rename `bifurcate()` to `bifurcateCrab()`
    7: Call `bifurcate()` in the `onland` event handler
    8: Fix crash in `drive()`

If the build passes, the master branch gets fast-forwarded to meet the staging branch. Since the master branch contains the exact contents that were just tested, bit-for-bit, it's not broken. (at least, not in any way that the automated tests are able to detect)

If the build fails, bors will follow a strategy called "bisecting". Namely, it splits the batch into two batches, and pushes those to the queue. In this example, the first batch will look like this:

    Merge #5 #7

    5: Rename `bifurcate()` to `bifurcateCrab()`
    7: Call `bifurcate()` in the `onland` event handler

This batch will still fail, because the second patch inserts a call to a function that the first patch removes. It will get bisected again, as a result.

The second will still pass, though.

    Merge #8

    8: Fix crash in `drive()`

This one will work, causing it to land in master, leaving the first two still in the backlog.

    Merge #5

    5: Rename `bifurcate()` to `bifurcateCrab()`

This one will pass, since the PR it conflicts with (#7) is sitting behind it in the queue.

    Merge #7

    7: Call `bifurcate()` in the `onland` event handler

When a batch cannot be bisected (because it only contains one PR), it gets kicked back to the creator so they can fix it.

Note that you can watch this process running on the [dashboard page] if you want.

As a convenience, you can also run `bors try`, which will kick off a build the same way `r+` would, but without actually pushing it to master even if it does succeed. To help keep them separate, `r+` merge commits go in `staging` and `try` builds go in `trying`.

[Bors-NG]: https://bors.tech/
[GitHub Application]: https://github.com/settings/installations
[Travis CI]: https://travis-ci.org/
[dashboard page]: https://app.bors.tech/

The [original bors] used a more simple system (it just tested one PR at a time all the time).
The one-at-a-time strategy is O(N), where N is the total number of pull requests.
The batching strategy is O(E log N), where N is again the total number of pull requests and E is the number of pull requests that fail.

[original bors]: https://bors-ng.github.io/guide/2017/04/26/whirlwind/

# How to run it on your local machine

If you're using a macOS or Linux command line with Docker on it,
`./script/setup && ./script/server` will set up a local instance,
with a mocked-out GitHub instance, using Docker to pull in all the underlying dependencies.
The web server ends up running on <http://localhost:8000/>.
You can get an Elixir REPL running in the same context as the webserver by running
`repl` instead of `server`. To run the tests, run `test` instead of `server`.

If you log in, it will log you in with the user "space."
There won't be any repositories, and space will not have admin perms.
You can use the [User model] to give space admin rights,
and the [WebhookController] and [GitHub ServerMock] to create the repo.

[User model]: https://bors-ng.github.io/devdocs/bors-ng/BorsNG.Database.User.html
[WebhookController]: https://bors-ng.github.io/devdocs/bors-ng/BorsNG.WebhookController.html
[GitHub ServerMock]: https://bors-ng.github.io/devdocs/bors-ng/BorsNG.GitHub.ServerMock.html

## Setting it up without Docker, like on Windows home edition

The main things you'll need to run Bors on your laptop are:

  * Familiarity with the command line
  * Elixir, with a full installation of OTP (the `esl-erlang` package is sufficient)
  * PostgreSQL; the configuration for it is in config/dev.exs
  * Stock C compilation tools, because some of bors's dependencies use NIFs
  * A git client, which you probably already have for downloading this repository
  * NodeJS, to perform asset compilation

I use [Portable PostgreSQL],
the [Chocolatey] packages for Elixir, Git, and NodeJS,
and the Visual C++ build tools from Microsoft.

[Portable PostgreSQL]: https://sourceforge.net/projects/postgresqlportable/
[Chocolatey]: https://chocolatey.org/packages/Elixir

You can then run it using `mix`:

    $ mix ecto.create
    $ mix ecto.migrate
    $ mix phx.server

And it'll run with the GitHub API mocked-out.

To run tests, run:

    $ mix test
    $ mix dogma
    $ mix dialyzer --halt-exit-status

# How to set up your own real instance

## Step 1: Register a new GitHub App

The first step is to [register a new Github App] on the GitHub web site.

[Register a new GitHub App]: https://github.com/settings/apps

### App settings

The *Github App name*, *description*, and *homepage URL* are irrelevant, though I suggest pointing the homepage at the dashboard page.

The *user authorization callback URL* should be at `<DASHBOARD URL>/auth/github/callback`.

Leave the *setup URL* blank.

The *webhook URL* should be at `<DASHBOARD URL>/webhook/github`.

The *webhook secret* should be a randomly generated string. The `mix phoenix.gen.secret` command will work awesomely for this. Keep this handy to specify the same value in the bors configuration (you can also edit this value later if you need to).

### Required GitHub App permissions

####  Permission summary

For each of these sections, set the following overall section permissions and check the following webhook event checkboxes. Explanations for why bors-ng needs each of these permissions are below.

- *Repository metadata*: Read-only (no choice)
  - *Repository* (Repository created, deleted, publicized, or privatized)
- *Repository administration*: No access
- *Commit statuses*: Read & write
  - *Status* (Commit status updated from the API)
- *Deployments*: No access
- *Issues*: Read & write
  - *Issue comment* (Issue comment created, edited, or deleted)
- *Pages*: No access
- *Pull requests*: Read & write
  - *Pull request* (Pull request opened, closed, reopened, edited, assigned, unassigned, review requested, review request removed, labeled, unlabeled, or synchronized)
  - *Pull request review* (Pull request review submitted, edited, or dismissed)
  - *Pull request review comment* (Pull request diff comment created, edited, or deleted)
- *Repository contents*: Read & write
  - (no checkboxes)
- *Single file*: No access
- *Repository projects*: No access
- *Organization members*: Read-only
  - *Team* (Team is created, deleted, edited, added to/removed from a repository)
  - *Member* (Collaborator added to, removed from, or has changed permissions for a repository)
  - *Membership* (Team membership added or removed)
  - *Organization* ( User invited to, added to, or removed from an organization)
- *Organization projects*: No access
- *Checks*: Read & Write
  - *Check run* (Check run created from the API)
  - *Check suite* (Check suite created from the API)

#### Permission explanations

*Repository metadata* will be read-only. Must be set to receive *Repository* events to automatically remove entries from our database when a repo is deleted.

*Commit statuses* must be set to *Read & write* to report a testing status (this is the older version). Also must get *Status* events to integrate with CI systems that report their status via GitHub.

*Issues* must be set to *Read & write* because pull requests are issues. *Issue comment* events must be enabled to get the "bors r+" comments. If *Issues* is set to Read-only, repos will end up with pull requests that are marked as simultaneously merged and opened.

*Pull requests* must be set to *Read & write* to be able to post pull request comments. Also, must receive *Pull request* events to be able to keep the dashboard working, and must get *Pull request review* and *Pull request review comment* events to get those kinds of comments.

*Repository contents* must be set to *Read & write* to be able to create merge commits.

*Checks* must be set to *Read & write* to report a testing status (this is the newer version). Also must get *Check run* events to integrate with CI systems that report their status via GitHub.

*Organization members* must be set to *Read only* to synchronize repository contributors and bors reviewers.

### After you click the "Create" button

GitHub will send a "ping" notification to your webhook endpoint. Since bors is not actually running yet, that will fail. This is expected.

You'll need the following values from your GitHub App for configuring bors-ng:

- Private key (generate one and download the file)
- OAuth credentials
- ID (appears beneath the app logo and "Owned by" in the right hand column)

### Internal app?

GitHub Apps can be set as "Internal" or "External".
When the App is set to be internal,
then whichever organization/user it belongs to will be the only one allowed to install it.

This setting can be chosen while first creating the app, or it can be changed afterward at one of these URLs (the switch is on the bottom of the page):

* If the app is owned by an organization: `https://github.com/organizations/<ORGANIZATION>/settings/apps/<APP NAME>/advanced`
* If the app is owned by a user: `https://github.com/settings/apps/<APP NAME>/advanced`

If an "External" app is installed on any external repositories,
then the "Make Internal" button will be grayed out.

## Step 2: Set up the server

bors-ng is written in the [Elixir] programming language,
and it uses [PostgreSQL] as the backend database.
Whatever machine you plan to run it on needs to have both of those installed.

[Elixir]: https://elixir-lang.org/
[PostgreSQL]: https://postgresql.org/
[docs on how to deploy phoenix apps]: http://www.phoenixframework.org/docs/deployment

bors-ng is built on the Phoenix web framework, and they have [docs on how to deploy phoenix apps] already. Where you deploy will determine what the dashboard URL will be, which is needed in the previous steps, so this decision needs to be made before you can set up the Github App.

You'll need to edit the configuration with a few bors-specific variables.

### Deploying on [Heroku] (and other 12-factor-style systems)

[Heroku]: https://heroku.com/

The config file in the repository is already set up to pull the needed information from the environment, so you can configure bors by setting the right env variables and deploy the app from this repository into Heroku:

You can do using Heroku's one-button-deploy system:

[![Deploy on Heroku](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

Or you can do it manually:

**Note**: The `GITHUB_INTEGRATION_ID` is now called the App ID on GitHub.

    $ heroku create --buildpack "https://github.com/HashNuke/heroku-buildpack-elixir.git" bors-app
    $ heroku buildpacks:add https://github.com/gjaldon/heroku-buildpack-phoenix-static.git
    $ heroku addons:create heroku-postgresql:hobby-dev
    $ heroku config:set \
        MIX_ENV=prod \
        POOL_SIZE=18 \
        PUBLIC_HOST=bors-app.herokuapp.com \
        ALLOW_PRIVATE_REPOS=true \
        COMMAND_TRIGGER=bors \
        SECRET_KEY_BASE=<SECRET1> \
        GITHUB_CLIENT_ID=<OAUTH_CLIENT_ID> \
        GITHUB_CLIENT_SECRET=<OAUTH_CLIENT_SECRET> \
        GITHUB_INTEGRATION_ID=<ISS> \
        GITHUB_INTEGRATION_PEM=`base64 -w0 priv.pem` \
        GITHUB_WEBHOOK_SECRET=<SECRET2>
    $ git push heroku master
    $ heroku run 'POOL_SIZE=1 mix ecto.migrate'

*WARNING*: bors-ng stores some short-term state inside the `web` dyno (it uses a sleeping process to implement delays, specifically).
It can recover the information after restarting, but it will not work correctly with Heroku's replication system.
If you need more throughput than one dyno can provide, you should deploy using a system that allows Erlang clustering to work.


### Deploying using [Docker] (and compatible container orchestration systems)

[Docker]: https://docker.com/

Pre-built Docker images are available at [Docker Hub](https://hub.docker.com/r/borsng/bors-ng/) for tags and the current `master` (as `bors-ng:latest`).

The Dockerfile in the project root can be used to build the image yourself.
It relies on [multi-stage builds](https://docs.docker.com/engine/userguide/eng-image/multistage-build/) as introduced in Docker 17.05,
to generate a slim image without the Erlang, Elixir and NodeJS development tools.

Most of the important configuration options should be set at runtime using environment variables, not unlike the Heroku instructions.
All the same recommendations apply, with some extra notes:

- `ELIXIR_VERSION` can be set as a build-time argument. Its default value is defined in the [Dockerfile](Dockerfile).
- `ALLOW_PRIVATE_REPOS` must be set at both build and run times to take effect. It is set to ` true` by default.
- `DATABASE_URL` *must* contain the database port, as it will be used at container startup to wait until the database is reachable. [The format is documented here](https://hexdocs.pm/ecto/Ecto.Repo.html#module-urls).
- The database schema will be automatically created and migrated at container startup, unless the ` DATABASE_AUTO_MIGRATE`  env. var.
  is set to `false`. Make that change if the database state is managed externally, or if you are using a database that cannot safely handle
  concurrent schema changes (such as older MariaDB/MySQL versions).
- Database migrations can be manually applied from a container using the `migrate` release command. Example:
  `docker run borsng/bors-ng:latest /app/bors/bin/bors migrate`.
  Unfortunately other `mix` tasks are not available, as they cannot be run from compiled releases.
- The `PORT` environment variable is set to `4000` by default.
- `GITHUB_URL_ROOT_API` and `GITHUB_URL_ROOT_HTML` should allow you to connect bors-ng to an instance of GitHub Enterprise.
  Note: I've never actually used GitHub Enterprise, so I'm kinda guessing about what you'd need here.

      docker create --name bors --restart=unless-stopped \
          -e PUBLIC_HOST=app.bors.tech \
          -e SECRET_KEY_BASE=<secret> \
          -e GITHUB_CLIENT_ID=<secret> \
          -e GITHUB_CLIENT_SECRET=<secret> \
          -e GITHUB_INTEGRATION_ID=<secret> \
          -e GITHUB_INTEGRATION_PEM=<secret> \
          -e GITHUB_WEBHOOK_SECRET=<secret> \
          -e DATABASE_URL="postgresql://postgres:<secret>@db:5432/bors_ng" \
          -e DATABASE_USE_SSL=false \
          -e DATABASE_AUTO_MIGRATE=true \
          -e COMMAND_TRIGGER=bors \
          borsng/bors-ng
      docker start bors

### Deploying on your own cluster

Your configuration can be done by modifying `config/prod.secret.exs`.

## Optional step 3: make yourself an admin

bors-ng offers a number of special functions for "administrator" users, including diagnostics and the ability to open a repo dashboard without being a reviewer.

However, there's no UI for adding admins; you'll have to go into Postgres yourself to do it. There's two ways to do that:

You can do it from the iex prompt, like this:

    shell$ iex -S mix # or `heroku run bash -c "POOL_SIZE=1 iex -S mix"`
    iex> me = BorsNG.Database.Repo.get_by! BorsNG.Database.User, login: "<your login>"
    iex> BorsNG.Database.Repo.update! BorsNG.Database.User.changeset(me, %{is_admin: true})

You can do it from a PostgreSQL prompt like this:

    postgres=# \c bors_dev -- or bors_prod
    bors_dev=# update users set is_admin = true where login = '<your login>';

# Copyright license

bors-ng is licensed under the Apache license, version 2.0.
It should be included with the source distribution in LICENSE-APACHE.
If it is missing, it is at <http://www.apache.org/licenses/LICENSE-2.0>.
