external_url ENV['GITLAB_EXTERNAL_URL'] || 'https://gitlab.example.com'

postgresql['enable'] = false
redis['enable']      = false

gitlab_rails['db_host']     = ENV['GITLAB_DB_HOST'] || 'pg-main'
gitlab_rails['db_port']     = (ENV['GITLAB_DB_PORT'] || '5432').to_i
gitlab_rails['db_username'] = ENV['GITLAB_DB_USER'] || 'gitlab'
gitlab_rails['db_password'] = ENV['GITLAB_DB_PASSWORD'] || ''
gitlab_rails['db_database'] = ENV['GITLAB_DB_NAME'] || 'gitlabhq_production'

gitlab_rails['redis_host']     = ENV['GITLAB_REDIS_HOST'] || 'redis-main'
gitlab_rails['redis_port']     = (ENV['GITLAB_REDIS_PORT'] || '6379').to_i

prometheus['enable']      = false
alertmanager['enable']    = false
node_exporter['enable']   = false
redis_exporter['enable']  = false

registry['enable']                      = true
gitlab_rails['registry_enabled']        = true
gitlab_pages['enable']                  = false
gitlab_kas['enable']                    = false

puma['worker_processes'] = 0
puma['min_threads'] = 1
puma['max_threads'] = 4
sidekiq['concurrency'] = 5

nginx['listen_port']  = 80
nginx['listen_https'] = false

gitlab_rails['gitlab_shell_ssh_port'] = (ENV['GITLAB_SSH_BIND'] || '22').to_i