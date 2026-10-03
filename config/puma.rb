threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

if ENV["RAILS_ENV"] == "production"
  # `__FILE__` nằm trong thư mục RELEASE đã được giải symlink, nên KHÔNG dùng nó
  # để suy ra đường dẫn. Deploy dùng hot restart (USR2): Puma tự re-exec, và nếu
  # nó gắn với đường dẫn release cũ thì sau deploy nó nạp lại CHÍNH CODE CŨ —
  # deploy "thành công" nhưng không có gì thay đổi. `directory` trỏ vào symlink
  # `current` để mỗi lần re-exec là chdir sang release mới.
  app_root = ENV.fetch("APP_ROOT", "/var/www/loyalty")
  shared   = "#{app_root}/shared"

  directory "#{app_root}/current"
  bind       "unix://#{shared}/tmp/sockets/puma.sock"
  pidfile    "#{shared}/tmp/pids/puma.pid"
  state_path "#{shared}/tmp/pids/puma.state"
  stdout_redirect "#{shared}/log/puma.log", "#{shared}/log/puma.log", true

  workers ENV.fetch("WEB_CONCURRENCY", 2).to_i
  # `preload_app!` và `prune_bundler` loại trừ nhau. Máy chủ đang chạy single
  # mode (WEB_CONCURRENCY=0) nên preload chẳng được gì, còn prune_bundler thì
  # BẮT BUỘC cho USR2: thiếu nó, re-exec vẫn dùng bundle của release cũ.
  preload_app! if ENV.fetch("WEB_CONCURRENCY", 2).to_i > 1
  prune_bundler
else
  port ENV.fetch("PORT", 3008)
  plugin :tmp_restart
end

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
