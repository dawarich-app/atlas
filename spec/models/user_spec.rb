require "rails_helper"

RSpec.describe User, type: :model do
  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "github",
        uid: "12345",
        info: {
          email: "octocat@example.com",
          name: "The Octocat",
          nickname: "octocat"
        }
      )
    end

    it "creates a new user when none exists" do
      expect { User.from_omniauth(auth) }.to change(User, :count).by(1)
    end

    it "returns the existing user when (provider, uid) match" do
      existing = User.from_omniauth(auth)
      expect { User.from_omniauth(auth) }.not_to change(User, :count)
      expect(User.from_omniauth(auth)).to eq existing
    end

    it "stores name, nickname, and email" do
      user = User.from_omniauth(auth)
      expect(user).to have_attributes(
        provider: "github",
        uid: "12345",
        email: "octocat@example.com",
        name: "The Octocat",
        nickname: "octocat"
      )
    end

    it "falls back to a noreply email when GitHub returns no email" do
      auth_no_email = OmniAuth::AuthHash.new(
        provider: "github",
        uid: "99999",
        info: { email: nil, name: "No Email", nickname: "noemail" }
      )
      user = User.from_omniauth(auth_no_email)
      expect(user.email).to eq "99999@users.noreply.github.com"
    end

    it "backfills a real email on a later OAuth callback when the user previously had a noreply fallback" do
      auth_no_email = OmniAuth::AuthHash.new(
        provider: "github",
        uid: "77777",
        info: { email: nil, name: "Pending", nickname: "pending" }
      )
      user = User.from_omniauth(auth_no_email)
      expect(user.email).to eq "77777@users.noreply.github.com"

      auth_with_email = OmniAuth::AuthHash.new(
        provider: "github",
        uid: "77777",
        info: { email: "real@example.com", name: "Pending", nickname: "pending" }
      )
      User.from_omniauth(auth_with_email)
      expect(user.reload.email).to eq "real@example.com"
    end

    it "does not overwrite a non-noreply email on a later OAuth callback" do
      user = User.from_omniauth(auth) # email = octocat@example.com
      auth_with_other_email = OmniAuth::AuthHash.new(
        provider: "github",
        uid: "12345",
        info: { email: "different@example.com", name: "The Octocat", nickname: "octocat" }
      )
      User.from_omniauth(auth_with_other_email)
      expect(user.reload.email).to eq "octocat@example.com"
    end
  end
end
