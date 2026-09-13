require "test_helper"

# The product's sales page: what a prospect reads before paying.
class LandingPageTest < ActionDispatch::IntegrationTest
  setup { get "/" }

  test "renders on the apex host" do
    assert_response :success
    assert_select "h1"
  end

  test "prices come from the plan records, not hardcoded copy" do
    Plan.seed_defaults! if Plan.count.zero?
    Plan.ordered.first.update!(price: 123_000)

    get "/"
    assert_match "123.000", response.body, "the pricing table is not reading the plans"
  end

  test "the trial length is stated rather than a vague promise of free" do
    days = Workspace::TRIAL_DAYS.to_s
    assert_match(/#{days} ngày/, response.body,
                 "the page says free but never says for how long")
    # "Bắt đầu miễn phí" with no duration read as a free tier; there is none.
    assert_no_match(/bắt đầu miễn phí/i, response.body)
  end

  test "the payment FAQ explains the trial, billing and grace period" do
    assert_match(/#{Workspace::TRIAL_DAYS} ngày/, response.body)
    assert_match(/#{Workspace::GRACE_DAYS} ngày ân hạn/, response.body)
  end

  test "carries a description and social tags for sharing" do
    desc = css_select("meta[name=description]").first
    assert desc.present?, "no meta description"
    assert_operator desc["content"].to_s.length, :>, 40
    assert_select "meta[property='og:title']"
    assert_select "meta[property='og:description']"
    assert_select "meta[property='og:image']"
    assert_select "link[rel=canonical]"
  end

  test "an existing shop owner can reach the login from the landing page" do
    assert_select "a[href=?]", "/merchant/login"
  end

  test "every section the nav points at exists" do
    %w[features how pricing faq].each do |id|
      assert_select "##{id}", 1, "the nav links to ##{id} but there is no such section"
    end
  end

  test "robots keeps the app and console out of search results" do
    get "/robots.txt"
    assert_response :success
    assert_match %r{Disallow: /merchant/}, response.body
    assert_match %r{Disallow: /admin/}, response.body
  end
end
