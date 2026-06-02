class Project < ApplicationRecord
  SLUG_REGEX = /\A[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?\z/

  belongs_to :user
  has_many :versions, -> { ordered }, dependent: :destroy
  has_many :entries, through: :versions
  has_many :beacon_events, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true,
                   format: { with: SLUG_REGEX, message: "must be lowercase alphanumeric with hyphens, 3–63 chars" },
                   length: { in: 3..63 },
                   uniqueness: { case_sensitive: false }
  validates :description,  length: { maximum: 2000 }, allow_nil: true
  validates :homepage_url, length: { maximum: 500 }, allow_nil: true

  def to_param
    slug
  end
end
