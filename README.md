A merge bot for GitHub pull requests
====================================

[Bors-NG] implements a continuous-testing workflow where the master branch never breaks.
It integrates GitHub pull requests with a tool like [Travis CI] that runs your tests.

* [Home page](https://bors-ng.github.io/)
* [Getting started](https://bors-ng.github.io/getting-started/)
* [Developer documentation](https://bors-ng.github.io/devdocs/bors-ng/Aelita2.html)

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

Bors is a [GitHub integration], so (assuming you already have Travis CI set up), getting bors set up requires two steps:

 1. Add the integration to your repo in GitHub.
 2. Commit a bors.toml with these contents:

        status = ["continuous-integration/travis-ci/push"]

To use it, you need to stop clicking the big green merge button, and instead leave a comment with this in it on any pull request that looks good to you:

    bors r+

As commits are reviewed, bors lumps them into a queue of batches. If everything passes, there will just be two batches; the one that's running, and the one that's waiting to be run (and is accumulating more and more pull requests until it gets a chance to run).

To run a batch, bors creates a merge commit, merging master with all the pull requests that make up the batch. They'll look like this:

    Merge #5 #7 #8

    5: Rename `bifurcate()` to `bifurcateCrab()`
    7: Call `bifurcate()` in the `onland` event handler
    8: Fix crash in `drive()`

If the build passes, the master branch gets fast-forwarded to meed the staging branch. Since the master branch contains the exact contents that were just tested, bit-for-bit, it's not broken. (at least, not in any way that the automated tests are able to detect)

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

[Bors-NG]: https://github.com/integration/bors-ng
[GitHub integration]: https://github.com/settings/installations
[Travis CI]: https://travis-ci.org/
[dashboard page]: https://bors-ng.herokuapp.com/

The original bors used a more simple system (it just tested one PR at a time all the time).
The one-at-a-time strategy is O(N), where N is the total number of pull requests.
The batching strategy is O(E log N), where N is again the total number of pull requests and E is the number of pull requests that fail.

# How to set up your own instance

Please read this whole guide before you start doing anything.

## Step 1: set up a GitHub integration

The first step is to [create a GitHub integration] on the GitHub web site.

[create a GitHub integration]: https://github.com/settings/integrations

### Integration settings

The *name*, *description*, and *homepage URL* are irrelevant, though I suggest pointing the homepage at the dashboard page.

Leave the *callback URL* blank.

The *webhook URL* should be at `<dashboard page>/webhook/github`.

The *webhook secret* should be a randomly generated string. The `mix phoenix.gen.secret` command will work awesomely for this.

### Required GitHub integration permissions

*Repository metadata*: Will be read-only. Must be set to receive *Repository* (Repository created, deleted, publicized, or privatized) events. This is needed to automatically remove entries from our database when a repo is deleted.

*Repository administration*: No access.

*Commit statuses*: Must be set to *Read & write*, to report a testing status. Also must get *Status* (Commit status updated from the API) events, to integrate with CI systems that report their status via GitHub.

*Deployments*: No access.

*Issues*: Must be set to *Read-only*, because pull requests are issues. *Issue comment* (Issue comment created, edited, or deleted) events must be enabled, to get the "bors r+" comments.

*Pages*: No access.

*Pull requests*: Must be set to *Read & write*, to be able to post pull request comments. Also, must receive *Pull request* (Pull request opened, closed, reopened, edited, assigned, unassigned, labeled, unlabeled, or synchronized) events to be able to keep the dashboard working, and must get *Pull request review* (pull request review submitted) and *Pull request review comment* (pull request diff comment created, edited, or deleted) events to get those kinds of comments.

*Repository contents*: Must be set to *Read-write*, to be able to create merge commits.

*Single file*: No.

*Repository projects*: No.

*Organization members*: No.

*Organization projects*: No.

### After you click the "Create" button

GitHub will send a "ping" notification to your webhook endpoint. Since bors is not actually running yet, that will fail. This is expected.

You'll need to jot down the Integration ID (it's between the "Install" button and the "Transfer ownership" button).

You'll also need to generate the private key. Save the file, because you'll need it later.

## Step 2: Set up the oAuth app

To authenticate access to the dashboard page, you'll also need to [set up oAuth].

The only important setting is *Authorization callback URL*, which is `<dashboard url>/auth/github/callback`.

## Step 3: Set up the server

bors-ng is written in the [Elixir] programming language,
and it uses [PostgreSQL] as the backend database.
Whatever machine you plan to run it on needs to have both of those installed.

[Elixir]: https://elixir-lang.org/
[PostgreSQL]: https://postgresql.org/
[docs on how to deploy phoenix apps]: http://www.phoenixframework.org/docs/deployment

bors-ng is built on the Phoenix web framework, and they have [docs on how to deploy phoenix apps] already. Where you deploy will determine the what the dashboard URL will be, which is needed in the previous steps, so this decision needs to be made before you can set up the Integration or the oAuth app.

You'll need to edit the configuration with a few bors-specific variables.

### Deploying on Heroku (and other 12-factor-style systems)

The config file in the repository is already set up to pull the needed information from the environment, so just set the right env variables and deploy the app:

You can do it the easy way:

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

Or you can do it manually:

    $ heroku create --buildpack "https://github.com/HashNuke/heroku-buildpack-elixir.git" bors-ng
    $ heroku buildpacks:add https://github.com/gjaldon/heroku-buildpack-phoenix-static.git
    $ heroku addons:create heroku-postgresql:hobby-dev
    $ heroku config:set \
        MIX_ENV=prod \
        POOL_SIZE=18 \
        PUBLIC_HOST=bors-ng.herokuapp.com \
        SECRET_KEY_BASE=<SECRET1> \
        GITHUB_CLIENT_ID=<OAUTH_CLIENT_ID> \
        GITHUB_CLIENT_SECRET=<OAUTH_CLIENT_SECRET> \
        GITHUB_INTEGRATION_ID=<ISS> \
        GITHUB_INTEGRATION_PEM=`base64 -w0 priv.pem` \
        GITHUB_WEBHOOK_SECRET=<SECRET2>
    $ git push heroku master

*WARNING*: bors-ng stores some short-term state inside the `web` dyno (it uses a sleeping process to implement delays, specifically).
It can recover the information after restarting, but it will not work correctly with Heroku's replication system.
If you need more throughput than one dyno can provide, you should deploy using a system that allows Erlang clustering to work.

### Deploying on your own cluster

Your configuration can be done by modifying `config/prod.secret.exs`.

## Optional step 4: make yourself an admin

bors-ng offers a number of special functions for "administrator" users, including diagnostics and the ability to open a repo dashboard without being a reviewer.

However, there's no UI for adding admins; you'll have to go into Postgres yourself to do it. There's two ways to do that:

### From an iex prompt

You can do it from the iex prompt, like this:

    shell$ iex -S mix # or `heroku run iex -S mix`
    iex> me = Aelita2.Repo.get_by! Aelita2.User, login: "<your login>"
    iex> Aelita2.Repo.update! Aelita2.User.changeset(me, %{is_admin: true})

You can do it from a PostgreSQL prompt like this:

    postgres=# \c aelita2_dev -- or aelita2_prod
    aelita2_dev=# update users set is_admin = true where login = '<your login>';

# Copyright license

bors-ng is licensed under the Apache license, version 2.0.
It should be included with the source distribution in [LICENSE-APACHE].
If it is missing, it is at <http://www.apache.org/licenses/LICENSE-2.0>.

[LICENSE-APACHE]: LICENSE-APACHE

