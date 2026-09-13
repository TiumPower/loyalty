FactoryBot.define do
  factory :admin_user do
    sequence(:email) { |n| "ops#{n}@example.com" }
    sequence(:name)  { |n| "Ops #{n}" }
    password { "secret123" }
  end
end
