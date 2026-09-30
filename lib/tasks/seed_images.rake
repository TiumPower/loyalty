# Generates the photographs the demo dataset attaches (shop cover, reward
# product shots) and writes them to db/seed_images/.
#
#   bin/rails loyalty:seed_images            # only the ones missing
#   bin/rails loyalty:seed_images FORCE=1    # regenerate everything
#
# This is a one-off developer step, not part of seeding: the files are committed
# so `loyalty:test_data` works on a box with no OpenAI key and no outbound
# network. Generating them (rather than shipping stock photography) also means
# the images carry no third-party licence into a product that is sold on.
namespace :loyalty do
  desc "Generate the demo photographs into db/seed_images (ENV: FORCE=1)"
  task seed_images: :environment do
    unless AiImageService.configured?
      abort("✗ Cần OPENAI_API_KEY để tạo ảnh. Ảnh đã tạo nằm sẵn trong db/seed_images/.")
    end

    dir = Rails.root.join("db/seed_images")
    FileUtils.mkdir_p(dir)

    STYLE = "Ảnh chụp thật, ánh sáng tự nhiên ấm, độ sâu trường ảnh nông, tông màu be/nâu ấm " \
            "của một quán cà phê đặc sản Việt Nam. Không có chữ, không logo, không watermark, " \
            "không có người nhìn thẳng vào máy ảnh."

    IMAGES = {
      "shop_cover" => ["1536x1024",
        "Mặt tiền một quán cà phê đặc sản nhỏ ở Sài Gòn vào buổi chiều muộn: cửa kính lớn sáng đèn ấm, " \
        "cây xanh trong chậu, bàn gỗ và ghế mây trên vỉa hè, vài khách ngồi trò chuyện."],
      "reward_coffee" => ["1024x1024",
        "Cận cảnh một ly cà phê sữa đá Việt Nam trong ly thuỷ tinh cao, đá viên và lớp sữa đặc " \
        "loang trong cà phê, đặt trên mặt bàn gỗ sáng, phía sau mờ là quầy pha chế."],
      "reward_tea" => ["1024x1024",
        "Cận cảnh một ly trà sữa trân châu mát lạnh trong ly thuỷ tinh, ống hút giấy, " \
        "lá trà tươi bên cạnh, đặt trên bàn gỗ sáng."],
      "reward_bill" => ["1024x1024",
        "Góc quầy thanh toán của quán cà phê: một ly cà phê mang đi, một cuốn sổ nhỏ và " \
        "một chậu cây, ánh nắng chiều xiên qua."],
      "reward_cake" => ["1024x1024",
        "Cận cảnh một lát bánh ngọt trên đĩa sứ trắng, nĩa bạc bên cạnh, " \
        "một tách cà phê phía sau hơi mờ, bàn gỗ sáng."],
      "reward_combo" => ["1024x1024",
        "Hai ly cà phê và một chiếc bánh sừng bò trên khay gỗ, nhìn từ trên xuống một góc nhỏ, " \
        "khăn vải lanh, bàn gỗ sáng."],
    }.freeze

    made = 0
    IMAGES.each do |name, (size, subject)|
      path = dir.join("#{name}.jpg")
      if path.exist? && ENV["FORCE"] != "1"
        puts "   · #{name}.jpg đã có — bỏ qua (FORCE=1 để tạo lại)"
        next
      end
      print "   → đang tạo #{name} (#{size})… "
      result = AiImageService.new(size: size).generate("#{subject} #{STYLE}")
      # The API returns PNG; store JPEG so the seed stays small enough to commit
      # and to attach without tripping the 5MB reward-image limit.
      png = dir.join("#{name}.png")
      File.binwrite(png, result[:bytes])
      system("magick", png.to_s, "-quality", "82", "-strip", path.to_s, exception: true)
      File.delete(png)
      puts "#{(path.size / 1024.0).round}KB"
      made += 1
    end

    puts made.zero? ? "\n✅ Không có gì để tạo." : "\n✅ Đã tạo #{made} ảnh vào db/seed_images/"
  end
end
