FactoryBot.define do
  factory :project do
    user
    sequence(:slug) { |n| "project-#{n}" }
    sequence(:name) { |n| "Project #{n}" }
    description { "A self-hostable thing." }
    homepage_url { "https://example.com" }
  end
end
