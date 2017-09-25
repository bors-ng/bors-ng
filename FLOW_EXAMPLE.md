Flow example of Bors-NG
=======================

This document goal is to explain what's the flow of events which occur when
someone merges a PR with bors.

PR creation
-----------
Nothing special in this step. A developer creates a PR, CI runs and other developers
do the code review. After everyone is in agreement, someone writes `bors r+`
as a comment in the PR.

Comments web hook
-----------------
Every time there is a comment, bors gets notified through a Github webhook.
See `webhoook_controller.ex` for the code.
Bors gets all the information it needs and creates a `Command`.
Since the comment contains `r+`, `Worker.Batcher` needs to be notified.

`Command` looks up in the registry for an existing Batcher thread.
If the batcher thread does not exist (either because there was no running work,
or because it crashed), it creates a new thread. If the batcher thread does
already exist, it just sends a message to it.

Batcher
-------
**NOTE:** We are assuming that the queue is empty.

First of all, the Batcher will wait `batch_delay_sec` seconds before starting any work.
By default, this is 10 seconds and it's a project property.

The batcher will use the github APIs to create a merge commit with all PR's commits
and apply it to the `staging` branch.
Previous `staging` changes are destroyed by force-pushing the merge commit over
the top of it. If bors were using the git CLI, what it would be doing is:

 - clone the repo
 - create a new local branch called staging
 - merge the PRs into the staging branch
 - git push -f it to the remote server

After merging the merge commit to the `staging` branch it will wait for the CI result.

 CI
 --
CI will detect the change in the staging branch and start building it.

**TIP:** Depending how you configure your CI, what you run on staging might be
different than what you run against PRs. A possible example is running unit
tests in PRs and running EOE tests in staging. That's up to you.

After the build is finished, CI will notify github through the
[Status API](https://github.com/blog/1227-commit-status-api).

The reason all communication is done through github is to make sure bors supports
as many CI clients as possible. Right now, Travis, AppVeyor, and Jenkins are used
without requiring to write custom rules on them.

Merge to master
---------------
`Worker.Batcher` will get notified of the CI result. There are two ways to find
out the `staging` branch build status:
 - Status API webhook
 - Polling the status API

The poll logic is needed because a webhook might fail and GitHub does not retry delivery.
If `staging` build is successful, `Worker.Batcher` would merge the merge commit,
closing the PR.

`Worker.Batcher`'s thread gets terminated after all of the items in the backlog are done.
