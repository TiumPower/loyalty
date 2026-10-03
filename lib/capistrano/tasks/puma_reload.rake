# Nạp lại Puma bằng hot restart (USR2) thay vì systemctl restart.
#
# `systemctl restart` tắt hẳn Puma rồi bật lại — unix socket biến mất vài giây
# và nginx trả 502 cho mọi người trong lúc đó. USR2 khiến Puma tự re-exec mà
# GIỮ NGUYÊN socket đang lắng nghe và GIỮ NGUYÊN PID, nên systemd không coi là
# tiến trình chết.
#
# Ghi đè thẳng `puma:restart` (chứ không thêm task mới): plugin systemd của
# capistrano3-puma có hook RIÊNG gọi `puma:restart` sau khi deploy xong, nên
# thêm task mới thì vẫn bị nó restart cứng ngay sau đó.
namespace :puma do
  desc "Hot restart Puma (USR2) — không làm rớt kết nối"
  task :hot_restart do
    on roles(:app) do
      unit = "#{fetch(:application)}_puma_#{fetch(:rails_env)}"
      runtime = "XDG_RUNTIME_DIR=/run/user/1000"
      if test("#{runtime} systemctl --user is-active --quiet #{unit}")
        execute "#{runtime} systemctl --user reload #{unit}"
      else
        execute "#{runtime} systemctl --user start #{unit}"
      end
    end
  end
end

Rake::Task["puma:restart"].clear_actions if Rake::Task.task_defined?("puma:restart")
namespace :puma do
  task restart: "puma:hot_restart"
end
