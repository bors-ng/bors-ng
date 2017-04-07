Getting started for contributors
================================

Thanks for wanting to help out with Bors-NG!


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
there's a list of easy-to-fix problems to get you started at <https://bors-ng.github.io/starters>.
After you pick an issue,
you should mention that you're working on it in a GitHub comment
(so that we can mark it as assigned and avoid duplicate work).
If you're having trouble fixing the problem,
go ahead and ask questions right in the issue's comments section,
even if your question seems unrelated to the issue itself.
