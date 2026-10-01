lock "~> 3.18"

set :application, "loyalty"

# Máy chủ không có khoá GitHub riêng. Khi deploy tay, nó mượn SSH agent của
# máy đang deploy (forward_agent trong config/deploy/production.rb). GitHub
# Actions không mượn được như vậy — tổ chức TiumPower tắt Deploy keys — nên CI
# truyền vào REPO_URL dạng HTTPS kèm token ngắn hạn của chính lần chạy đó.
set :repo_url, ENV.fetch("REPO_URL", "git@github.com:TiumPower/loyalty.git")

# Token sai thì git phải hỏng ngay. Không có ai ngồi trước máy chủ để gõ mật
# khẩu, nên một lời nhắc đăng nhập là một deploy treo cho tới khi hết giờ.
set :default_env, { "GIT_TERMINAL_PROMPT" => "0" } if ENV["REPO_URL"].to_s.start_with?("https://")

set :deploy_to,   "/var/www/loyalty"
set :branch,      ENV.fetch("BRANCH", "main")

# rbenv
set :rbenv_type,   :user
set :rbenv_ruby,   File.read(".ruby-version").strip.sub(/^ruby-/, "")
set :rbenv_prefix, "RBENV_ROOT=$HOME/.rbenv RBENV_VERSION=#{fetch(:rbenv_ruby)} $HOME/.rbenv/bin/rbenv exec"
set :rbenv_path,   "$HOME/.rbenv"

# Shared files/dirs persisted across deploys
set :linked_files, %w[.env]
set :linked_dirs, %w[
  log
  tmp/pids
  tmp/cache
  tmp/sockets
  storage
  public/assets
]

set :keep_releases, 5
set :assets_roles, [:web]

# Puma
set :puma_threads,        [2, 4]
set :puma_workers,        2
set :puma_bind,           "unix://#{shared_path}/tmp/sockets/puma.sock"
set :puma_state,          "#{shared_path}/tmp/pids/puma.state"
set :puma_pid,            "#{shared_path}/tmp/pids/puma.pid"
set :puma_access_log,     "#{release_path}/log/puma.access.log"
set :puma_error_log,      "#{release_path}/log/puma.error.log"
set :puma_preload_app,    true
set :puma_init_active_record, true

# Sidekiq (systemd)
set :sidekiq_config, "#{current_path}/config/sidekiq.yml"

namespace :deploy do
  desc "Seed database (run manually: cap production deploy:seed)"
  task :seed do
    on roles(:db) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "db:seed"
        end
      end
    end
  end

  desc "XOÁ toàn bộ workspace rồi dựng lại bộ dữ liệu test (cap production deploy:test_data PASSWORD=... [ONLY=cozycafe])"
  task :test_data do
    pw = ENV["PASSWORD"].to_s
    raise "Cần PASSWORD='<mật khẩu ≥12 ký tự>'" if pw.length < 12
    only = ENV["ONLY"].to_s
    on roles(:db) do
      within release_path do
        with rails_env: fetch(:rails_env), password: pw, confirm: "yes", only: only do
          execute :rake, "loyalty:test_data"
        end
      end
    end
  end

  desc "Tra toạ độ cho chi nhánh từ địa chỉ (cap production deploy:geocode [FORCE=1])"
  task :geocode do
    on roles(:app) do
      within current_path do
        with rails_env: fetch(:rails_env), force: ENV["FORCE"].to_s do
          execute :rake, "loyalty:geocode"
        end
      end
    end
  end

  desc "Chép tệp Active Storage từ đĩa lên DigitalOcean Spaces (cap production deploy:to_spaces)"
  task :to_spaces do
    on roles(:app) do
      within current_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "storage:to_spaces"
        end
      end
    end
  end

  desc "Kiểm tra mọi tệp đính kèm đọc được (cap production deploy:verify_storage)"
  task :verify_storage do
    on roles(:app) do
      within current_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "storage:verify"
        end
      end
    end
  end

  # Capistrano ghi :repo_url vào config của git mirror trên máy chủ. Token của
  # CI hết hạn ngay khi lần chạy kết thúc, nhưng một chuỗi bí mật đã chết vẫn
  # không nên nằm lại trên đĩa — CI gọi task này sau mỗi lần deploy, kể cả khi
  # deploy hỏng.
  desc "Trả git mirror trên máy chủ về URL SSH (xoá token HTTPS của CI)"
  task :scrub_repo_url do
    on roles(:app) do
      next unless test("[ -d #{repo_path} ]")
      execute :git, "-C", repo_path, "remote", "set-url", "origin",
              "git@github.com:TiumPower/loyalty.git"
    end
  end

  after :publishing, :restart

  after :finishing, :restart_sidekiq do
    on roles(:app) do
      execute :sudo, "systemctl restart sidekiq-loyalty"
    end
  end

  # Keep the nightly backup script in shared/ rather than in the release: a bad
  # deploy (or a rolled-back release) must never be able to stop backups. The
  # source of truth stays in the repo, copied out on every deploy.
  desc "Install the nightly backup script and its cron entry"
  task :install_backup do
    on roles(:db) do
      dest = "#{shared_path}/bin/loyalty_backup.sh"
      execute :mkdir, "-p", "#{shared_path}/bin"
      upload! "bin/loyalty_backup.sh", dest
      execute :chmod, "+x", dest
      line = "45 3 * * * #{dest} >> #{shared_path}/log/backup.log 2>&1"
      # Idempotent: drop any previous loyalty_backup line, then append ours.
      execute %(crontab -l 2>/dev/null | grep -v 'loyalty_backup.sh' > /tmp/loyalty_cron || true)
      execute %(echo "#{line}" >> /tmp/loyalty_cron && crontab /tmp/loyalty_cron && rm -f /tmp/loyalty_cron)
    end
  end
  after :finishing, :install_backup
end
