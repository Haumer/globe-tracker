namespace :scheduler do
  desc "Enqueue due polling jobs for Heroku Scheduler"
  task polling_tick: :environment do
    result = GlobalPollerService.tick!
    puts result.inspect
  end
end
