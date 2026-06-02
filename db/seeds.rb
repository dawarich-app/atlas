# Seeds are idempotent: re-running them resets the seeded account's password
# back to the configured value but never disturbs other data. The production
# guard prevents accidentally creating a backdoor user if the seeds file is
# run against the wrong environment.
return if Rails.env.production?

email    = ENV.fetch("SEED_EMAIL",    "demo@chibichange.com")
password = ENV.fetch("SEED_PASSWORD", "password")

user = User.find_or_initialize_by(email: email)
user.password = password
user.password_confirmation = password
user.save!

puts "[seed] user ready: #{email} / #{password}"
