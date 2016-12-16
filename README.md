# Aelita2

To start your Phoenix app:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.create && mix ecto.migrate`
  * Install Node.js dependencies with `npm install`
  * Start Phoenix endpoint with `mix phoenix.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](http://www.phoenixframework.org/docs/deployment).

## Learn more

  * Official website: http://www.phoenixframework.org/
  * Guides: http://phoenixframework.org/docs/overview
  * Docs: https://hexdocs.pm/phoenix
  * Mailing list: http://groups.google.com/group/phoenix-talk
  * Source: https://github.com/phoenixframework/phoenix


# Required GitHub integration settings

Repository metadata: Will be read-only. Must be set to receive "Repository created, deleted, publicized, or privatized" events. This is needed to automatically remove entries from our database when a repo is deleted.

Repository administration: No access.

Commit statuses: Must be set to "Read & write", to report a testing status. Also must get Status events, to integrate with CI systems that report their status via GitHub.

Deployments: No access.

Issues: Must be set to "Read-only", because pull requests are issues. "Issue comment" events must be enabled, to get the "@bors r+" comments.

Pull requests: Must be set to "Read-only", to know when a pull request exists and what its current commit is. Also, must receive "Pull request" events to be able to keep the dashboard and cache, and must get "Pull request review" and "Pull request review comment" events to get those kinds of comments.

Repository contents: Must be set to "Read-write," to be able to create merge commits.

Single file: No.

Repository projects: No.

Organization members: No.

Organization projects: No.
