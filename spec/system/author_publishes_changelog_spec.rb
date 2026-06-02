require "rails_helper"

RSpec.describe "Author publishes a changelog", type: :system do
  before { driven_by(:rack_test) }

  it "lets a signed-in author go from zero to a public page" do
    user = create(:user)
    sign_in user, scope: :user

    visit authors_projects_path
    click_link "New project"

    fill_in "Slug", with: "dawarich"
    fill_in "Name", with: "Dawarich"
    click_button "Create Project"

    expect(page).to have_content "Project created"
    expect(page).to have_content "Dawarich"

    # Add an entry to Unreleased
    select "Added", from: "entry[kind]"
    fill_in "entry[body_markdown]", with: "Initial **release**"
    click_button "Add"

    expect(page).to have_content "Entry added"
    expect(page).to have_content "Initial **release**"

    # Release the version
    fill_in "number", with: "1.0.0"
    fill_in "released_at", with: "2026-04-30"
    click_button "Release"

    expect(page).to have_content "Released 1.0.0"

    # Public page renders
    visit public_changelog_path(slug: "dawarich")
    expect(page).to have_content "Dawarich"
    expect(page).to have_content "1.0.0"
    expect(page).to have_content "2026-04-30"
    expect(page).to have_selector("strong", text: "release")
  end
end
