ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include FactoryBot::Syntax::Methods

    # Run a block with a tenant set (acts_as_tenant).
    def with_tenant(ws, &blk) = ActsAsTenant.with_tenant(ws, &blk)
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Pretend we are production for the duration of a block, so the
  # subdomain-only branches (merchant_url_for, the canonical-host redirects)
  # can be exercised at all.
  #
  # Puts the original method back rather than removing the override. Both live
  # on ApplicationController, so `remove_method` deletes the real one and
  # leaves the class without it — which has now taken unrelated tests down
  # twice. Define it once, here, so nobody has to remember.
  def across_hosts
    original = ApplicationController.instance_method(:force_subdomain_links?)
    ApplicationController.class_eval { define_method(:force_subdomain_links?) { true } }
    yield
  ensure
    ApplicationController.class_eval do
      define_method(:force_subdomain_links?, original)
      private :force_subdomain_links?
    end
  end
end
