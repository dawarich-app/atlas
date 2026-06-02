class Version < ApplicationRecord
  class AlreadyReleased       < StandardError; end
  class CannotYankUnreleased  < StandardError; end

  belongs_to :project
  has_many :entries, -> { ordered }, dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :project_id }

  scope :ordered, -> {
    order(Arel.sql("released_at DESC NULLS FIRST, created_at DESC"))
  }

  def self.unreleased_for(project)
    project.versions.where(released_at: nil).first
  end

  def unreleased?
    released_at.nil?
  end

  def release!(number:, released_at:)
    raise AlreadyReleased, "version #{self.number} is already released" unless unreleased?

    update!(number: number, released_at: released_at)
  end

  def yank!
    raise CannotYankUnreleased if unreleased?

    update!(yanked: true)
  end
end
