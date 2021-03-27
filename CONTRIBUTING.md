Getting started for contributors
================================

Thanks for wanting to help out with Bors-NG!


Answering support questions
---------------------------

If you've been using bors a lot,
you can help other people use it by answering questions on the [support forum].
It's running on Discourse, the same app used by Elixir Forum and Rust Users.

[support forum]: https://forum.bors.tech/


Submitting bug reports
----------------------

Go ahead and submit an issue report;
we can't fix a problem if we don't know about it.
Even if you're not sure if it's a bug,
go ahead and submit it.
If a lot of users think it's a problem,
even if we don't think it's "really a bug,"
we'll probably try to figure out a way to fix it anyway.
Bors needs to be useful, not just correct.
Besides, that's why we call them "issue reports" instead of "bug reports."

If you get the chance,
please use the search bar at the top of the issues list to see if somebody else already reported it.
You don't have to do that,
if you don't have time,
or just can't think of what to search for.
Think of it as extra credit.
If we find a duplicate,
we'll just leave a comment saying "Duplicate of #some-other-issue-number"
(so that you know where the existing conversation is happening)
and close it.

Filing an issue is as easy as going to the [new issue page] and filling out the fields.

[new issue page]: https://github.com/bors-ng/bors-ng/issues/new


Sending your change to us
-------------------------

The best way to send changes to Bors-NG is to fork our repo, then open a pull request.
GitHub has a [howto for the fork-pull system] on their own website.

[howto for the fork-pull system]: https://help.github.com/articles/fork-a-repo/

BTW, the [hub] CLI is really cool.
With it,
you can make a pull request that modifies this file by running these commands:

    $ hub clone bors-ng/bors-ng
    $ cd bors-ng
    $ hub fork
    $ git checkout -b fix_readme
    $ vim CONTRIBUTING.md
    $ git commit CONTRIBUTING.md
    $ git push -u <YOUR GITHUB USERNAME> HEAD
    $ hub pull-request

You don't have to use anything like that if you don't want to,
though.

[hub]: https://hub.github.com/


Finding something to work on
----------------------------

If you're not sure what to work on,
there's a list of easy-to-fix problems to get you started at <https://bors.tech/starters>.
After you pick an issue,
you should mention that you're working on it in a GitHub comment
(so that we can mark it as assigned and avoid duplicate work).
If you're having trouble fixing the problem,
go ahead and ask questions right in the issue's comments section,
even if your question seems unrelated to the issue itself.


Proposing and adding new features
---------------------------------

If you'd like to add a new feature, or make big changes to the way bors works,
head over to the [RFC](https://forum.bors.tech/t/about-the-draft-rfcs-category/291) area in the forum and follow the instructions.

Developing locally
------------------

To work on bors-ng you will need:

1. Erlang and Elixir installed and in PATH
2. a local database instance, bors uses Postgres by default

You can install Erlang and Elixir as you prefer, one way to do it without
affecting other development environments is with [asdf](https://asdf-vm.com/#/). The following shows you how to use asdf. If you already have Erlang and Elixir installed
or prefer to install them in another way just skip to the next section.

**NOTE**: please check the Erlang and Elixir versions against `.travis.yml` to make sure you are using a supported version.

### Installing Erlang and Elixir with asdf

To get started developing on bors with asdf install it as per the docs, then
install Erlang and Elixir with the following commands (we assume you're on linux,
YMMV on other OSs):

```sh
asdf plugin-add erlang
asdf install erlang 21.0.9
asdf plugin-add elixir
asdf install elixir 1.8.1
# in the parent directory
cat<<EOF > ../.tool-versions
elixir 1.8.1
erlang 21.0.9
EOF
```

**NOTE**: please double check the Erlang and Elixir versions against `.travis.yml` to make sure you are using a supported version.

### Running tests locally

You are now set for developing locally. For example to run the tests you will just have to start a postgres instance on localhost, using docker is the simplest way:

```sh
docker run -it --rm --net=host -e POSTGRES_PASSWORD=Postgres1234 postgres:11.2
```

then in another shell you can run the tests as simply as:

```sh
mix test
```

to run a single test suite/case just pass the relative path to the test name and optionally the line number:

```sh
mix test test/batcher/batcher_test.exs:3878
```
