FactoryBot.define do
  factory :entry do
    version
    kind { "added" }
    body_markdown { "Added something useful" }
    body_tokens   { [{ "t" => "p", "c" => [{ "t" => "text", "v" => "Added something useful" }] }] }
    sequence(:position) { |n| n }
  end
end
