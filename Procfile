web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
poller: bundle exec rails runner PollerRuntime.run
release: bundle exec rails assets:precompile && bundle exec rails db:migrate
