class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable, :omniauthable,
         omniauth_providers: [:github]

  has_many :projects, dependent: :destroy

  GITHUB_NOREPLY_SUFFIX = "@users.noreply.github.com".freeze

  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    if user.email.blank? || user.email.end_with?(GITHUB_NOREPLY_SUFFIX)
      user.email = auth.info.email || "#{auth.uid}#{GITHUB_NOREPLY_SUFFIX}"
    end
    user.name      = auth.info.name
    user.nickname  = auth.info.nickname
    user.password  = Devise.friendly_token[0, 20] if user.new_record?
    user.save!
    user
  end
end
