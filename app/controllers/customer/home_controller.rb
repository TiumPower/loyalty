module Customer
  class HomeController < BaseController
    MISSION_WINDOW = 12 # how many missions we consider before picking three

    def show
      if current_workspace.nil?
        # Apex host (no shop resolved) → marketing landing page.
        @plans = Plan.ordered.to_a
        @plans = Plan::DEFAULTS.map { |d| Plan.new(d) } if @plans.empty?
        render "customer/home/landing", layout: "marketing"
      elsif !member_signed_in? || current_member&.workspace_id != current_workspace.id
        redirect_to member_login_path
      else
        @member = current_member
        @tier   = @member.tier
        @unread = @member.notifications.unread.count
        # Highlight what's redeemable now + what's opening soon (open first).
        @offers = current_workspace.rewards.redeemable.ordered.to_a
                    .select { |r| %i[open upcoming].include?(r.redeem_state) }
                    .sort_by { |r| r.redeem_open? ? 0 : 1 }
                    .first(6)
        prog = current_workspace.program
        if prog.gamification_enabled
          # Daily tasks + one-time missions (e.g. social share) both surface here.
          # This used to take the first three by position and look each one's
          # progress row up separately: a customer who had finished those three
          # was shown three ticked boxes and none of the ones still worth doing,
          # and the page ran a query per mission. Load a window, resolve every
          # progress row in one go, then put what is still open first.
          candidates = current_workspace.missions.active.ordered
                                        .where(period: %w[daily once]).limit(MISSION_WINDOW).to_a
          rows = MissionProgress.where(member_id: @member.id, mission_id: candidates.map(&:id))
                                .index_by { |r| [r.mission_id, r.period_key] }
          all = candidates.index_with do |m|
            rows[[m.id, m.current_period_key]] ||
              MissionProgress.new(workspace: current_workspace, member: @member,
                                  mission: m, period_key: m.current_period_key)
          end
          @missions = candidates.sort_by.with_index { |m, i| [all[m].completed? ? 1 : 0, i] }.first(3)
          @progress = @missions.index_with { |m| all[m] }
          # "Play & collect" needs the live state of the two habit loops, not
          # just whether the feature is switched on — the cards show a spin
          # count and a stamp progress bar.
          @wheel = current_workspace.spin_wheel
          @wheel_free = @wheel && @wheel.free_spin_available?(@member)
          # "Win up to 100 pts" on the home card — the best point prize the
          # wheel actually carries, not a number typed into the design.
          @wheel_top_prize = @wheel&.resolved_segments.to_a.select { |s| s["kind"] == "points" }.map { |s| s["value"].to_i }.max.to_i
          load_badge_strip
        end
        if prog.stamps_enabled
          @stamp_card = current_workspace.stamp_cards.active.ordered.detect(&:running?)
          @stamp_membership = @stamp_card&.membership_for(@member)
          @stamp_card = nil if @stamp_membership.nil?
        end
        # Shown on the shop card; nil when the shop keeps feedback private.
        @shop_rating = current_workspace.feedback_public? ? Rating.average(:stars)&.round(1) : nil
        render :show
      end
    end

    private

    # Dải huy hiệu ở cuối màn hình chính.
    #
    # Huy hiệu trước đây chỉ đến được qua trang Hạng, nên hầu như không ai biết
    # quán có huy hiệu. Nó không phải một việc để làm như vòng quay hay thẻ tem
    # — nó là BỘ SƯU TẬP mà những việc kia cộng lại thành, và điều đáng nói của
    # một bộ sưu tập là chỗ còn trống. Nên đây là một dải ngang nhiều đĩa chứ
    # không phải thêm một thẻ vuông vào lưới "Chơi & tích": thẻ vuông chỉ khoe
    # được một cái.
    #
    # KHÔNG gọi `Gamification.evaluate_badges` ở đây như trang Huy hiệu: nó ghi
    # bản ghi, cộng điểm và bắn thông báo, quá nặng cho trang được mở nhiều
    # nhất. Thay vào đó, huy hiệu nào đã đủ tiến độ thì coi như đã đạt để hiển
    # thị — tránh cảnh "25/25 chưa đạt" khi quán vừa thêm huy hiệu mới mà khách
    # chưa mở trang Huy hiệu.
    STRIP_SIZE = 6
    EARNED_SHOWN = 4

    def load_badge_strip
      all = current_workspace.badges.ordered.to_a
      return if all.empty?

      progress = Badge.progress_map(all, @member)
      owned = @member.member_badges.pluck(:badge_id).to_set
      @badge_done = all.select do |b|
        done, target = progress[b]
        owned.include?(b.id) || (target.positive? && done >= target)
      end

      # Gần đạt nhất trước: tỉ lệ hoàn thành giảm dần. Huy hiệu chưa có mốc nào
      # (target 0) xuống cuối thay vì chia cho 0.
      near = (all - @badge_done).sort_by do |b|
        done, target = progress[b]
        target.positive? ? -(done.to_f / target) : 1.0
      end

      # Luôn chừa chỗ cho tối đa hai cái CHƯA đạt: mục này tồn tại để khách biết
      # quán có huy hiệu gì, không chỉ để khoe cái đã có. Nhưng chừa chỗ mà
      # không có gì để xếp vào thì dải bị ngắn lại một cách vô cớ, nên thiếu
      # bao nhiêu thì lấp nốt bằng huy hiệu đã đạt.
      locked = near.first(STRIP_SIZE - EARNED_SHOWN)
      @badge_strip = (@badge_done.first(STRIP_SIZE - locked.size) + near).first(STRIP_SIZE)
      @badge_progress = progress
      @badge_total = all.size
    end
  end
end
