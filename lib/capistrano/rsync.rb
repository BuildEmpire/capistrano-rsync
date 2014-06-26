require File.expand_path("../rsync/version", __FILE__)

# NOTE: Please don't depend on tasks without a description (`desc`) as they
# might change between minor or patch version releases. They make up the
# private API and internals of Capistrano::Rsync. If you think something should
# be public for extending and hooking, please let me know!

rsync_cache = lambda do
  cache = fetch(:rsync_cache)
  cache = deploy_to + "/" + cache if cache && cache !~ /^\//
  cache
end

namespace :load do
  task :defaults do
    set :rsync_options, []
    set :rsync_copy, "rsync --archive --acls --xattrs"

    # Stage is used on your local machine for rsyncing from.
    set :rsync_stage, "tmp/deploy"

    # Cache is used on the server to copy files to from to the release directory.
    # Saves you rsyncing your whole app folder each time.  If you nil rsync_cache,
    # Capistrano::Rsync will sync straight to the release path.
    set :rsync_cache, "shared/deploy"
  end
end

desc "Stage and rsync to the server (or its cache)."
task :rsync => %w[rsync:stage] do
  roles(:all).each do |role|
    user = role.user + "@" if !role.user.nil?

    rsync = %w[rsync]
    rsync.concat fetch(:rsync_options)
    rsync << fetch(:rsync_stage) + "/"
    rsync << "#{user}#{role.hostname}:#{rsync_cache.call || release_path}"
    run_locally do
      execute *rsync
    end
  end
end

namespace :rsync do
  task :set_current_revision do
    run_locally do
      within fetch(:rsync_stage) do
        rev = capture(:git, 'rev-parse', 'HEAD')
        set :current_revision, rev
      end
    end
  end

  task :check do
    # Everything's a-okay inherently!
  end

  task :create_stage do
    next if File.directory?(fetch(:rsync_stage))

    run_locally do
      execute :git, 'clone', fetch(:repo_url, "."), fetch(:rsync_stage)
    end
  end

  desc "Stage the repository in a local directory."
  task :stage => %w[create_stage] do
    run_locally do
      within fetch(:rsync_stage) do
        rev = capture(:git, 'ls-remote', fetch(:repo_url), fetch(:branch)).split[0]
        execute(:git, 'fetch', '--quiet', '--all', '--prune')
        execute(:git, 'reset', '--hard', rev)
        execute(:git, 'clean', '-q', '-d', '-f')
      end
    end
  end

  desc "Copy the code to the releases directory."
  task :create_release => %w[rsync] do
    # Skip copying if we've already synced straight to the release directory.
    next if !fetch(:rsync_cache)

    copy = %(#{fetch(:rsync_copy)} "#{rsync_cache.call}/" "#{release_path}/")
    on roles(:all).each do execute copy end
  end
end
