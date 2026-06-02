FactoryBot.define do
  factory :version do
    project
    sequence(:number) { |n| "1.0.#{n}" }
    released_at { Date.today }
    yanked { false }

    trait :unreleased do
      number { "Unreleased" }
      released_at { nil }
    end

    trait :yanked do
      yanked { true }
    end
  end
end
