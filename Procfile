web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
ws: bin/anycable-go
release: bundle exec rails assets:precompile && bundle exec rails db:migrate
