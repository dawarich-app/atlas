FactoryBot.define do
  factory :beacon_event do
    project
    sequence(:origin) { |n| "https://instance-#{n}.example.com" }
    version { "1.0.0" }
    created_at { Time.current }
  end
end
