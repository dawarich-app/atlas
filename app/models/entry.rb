class Entry < ApplicationRecord
  KINDS = %w[added changed deprecated removed fixed security].freeze

  belongs_to :version

  enum :kind, KINDS.zip(KINDS).to_h, instance_methods: false

  validates :kind, presence: true
  validates :body_markdown, presence: true

  scope :ordered, -> { order(:position, :created_at) }

  def self.by_kind
    grouped = where(kind: KINDS).ordered.group_by(&:kind)
    KINDS.each_with_object({}) do |kind, h|
      h[kind] = grouped[kind] if grouped[kind]&.any?
    end
  end
end
