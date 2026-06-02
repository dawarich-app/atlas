FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "author#{n}@example.com" }
    sequence(:uid)   { |n| "uid-#{n}" }
    provider { "github" }
    name     { Faker::Name.name }
    nickname { Faker::Internet.username }
    password { "password123" }
  end
end
