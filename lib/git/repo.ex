defmodule BorsNG.Git.Repo do
  # What do we need in this module?
  # * a function to take in a batch and merge in all the changes
  #   locally... which presumably also would handle resetting the current
  #   state
  # * a function to then push up those changes to github, since we
  #   can't rely on doing that using the API... at least, not the way
  #   it's done right now
  # 
  # i think if we had those two, it would be enough to correctly have
  # bors handle the rest, since it would just pass us each waiting
  # batch that it wanted...
  #
  # however. there's a problem here, which is that bors can have 
  # multiple waiting batches at a time, and it relies on GH as
  # its storage. we would probably have to do the same thing.
  # in fact, we may actually have to use that API that allows you
  # to directly specify the SHA... god, that sounds like a pain.
  # please tell me there's a way to push just a commit.
  #
  # yes... so it definitely seems like github is not particularly
  # happy with that, and if i wanted to do what i'm trying to do,
  # i'd have to directly make use of the commit creation api.
  # which clearly is not the intended way to use github! but at
  # least it seems like it works. so we'd need some way of getting
  # those contents into the tree format we're looking for as well...
  # which probably means some sort of recursive file lookup -> 
  # enumerate it into the thing we're looking for.
  #
  # and this would be *really* ugly for our repository, since it
  # would mean potentially reading the contents of a lot of stuff...
  # we should make sure to test that we can do that.

  # so first we'll want this function to attempt to create the commit
  # information and check if it's even remotely fast enough for
  # what we're trying to do here. it probably won't be... in which
  # case we'll have to get creative.

  # actually, we do have a branch we can push to... the staging.tmp branch.
  # if we just use that, then things could work, I think!
  # bors is already using it anyways, so why not!

  # or rather, it uses it for squash merges. but regardless, it stakes a
  # claim on that branch name, so let's just use that.

  # it's... probably better to have a separate worker for this, since we want
  # there to be only a single interface to the filesystem and we don't want
  # multiple workers potentially screwing up the filesystem by overwriting
  # each other.

  alias BorsNG.Database.Repo
  alias BorsNG.Database.Batch
  alias BorsNG.Database.LinkPatchBatch
  alias BorsNG.Database.Project
  alias BorsNG.GitHub

  # We probably should put this under the GitHub folder, since we are
  # hitting GitHub directly, and mentioning it etc.

  @spec merge_batch(Batch.t()) :: :ok
  def merge_batch(batch) do
    # repo_conn = Project.installation_connection(batch.project.repo_xref, Repo)
    # {commit: base} = GitHub.get_branch!(repo_conn, batch.into_branch)
    batch = batch |> Repo.preload([:project, :patches])
    patch_links =
      Repo.all(LinkPatchBatch.from_batch(batch.id))
      |> Enum.sort_by(& &1.patch.pr_xref)    

    git = fn args -> System.cmd("git", args, cd: batch.project.name) end

    git.(["fetch", "origin", batch.into_branch])
    git.(["checkout", "origin/#{batch.into_branch}"])

    # So now we have to 'fetch' all the branches inside the patches, and then
    # merge them into the actual stuff..

    patch_links
      |> Enum.reduce(nil, fn (link_patch_batch, _acc) ->
        link_patch_batch = link_patch_batch |> Repo.preload([:patch])
        patch = link_patch_batch.patch

        git.(["fetch", "origin", patch.commit])
        git.(["merge", patch.commit])
      end)
    :ok
  end

  @spec persist_merged_batch(Batch.t()) :: :ok
  def persist_merged_batch(batch) do
    batch = batch |> Repo.preload([:project])
    stmp = "#{batch.project.staging_branch}.tmp"
    System.cmd("git", ["push", "origin", "HEAD:refs/heads/#{stmp}"], cd: batch.project.name)
    :ok
  end

  # We're going to need to change this to use credentials later.
  @spec init_batch_repo(Batch.t()) :: :ok
  def init_batch_repo(batch) do
    batch = batch |> Repo.preload([:project])    
    System.cmd("git", ["clone", "git@github.com:#{batch.project.name}.git", "--recursive", batch.project.name])
    :ok
  end
end