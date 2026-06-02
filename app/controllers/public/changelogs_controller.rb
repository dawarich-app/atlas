class Public::ChangelogsController < ApplicationController
  layout "public"

  def show
    @project = Project.find_by!("lower(slug) = ?", params[:slug].downcase)

    # Cheap freshness probe before loading versions+entries. Covers both
    # version-level edits (release/yank) and entry edits on Unreleased.
    entries_max = Entry.joins(:version).where(versions: { project_id: @project.id }).maximum(:updated_at)
    last_modified = [@project.updated_at, entries_max].compact.max

    return unless stale?(etag: [@project, last_modified], last_modified: last_modified, public: true)

    @versions = @project.versions.ordered
                        .includes(:entries)
                        .reject { |v| v.unreleased? && v.entries.empty? }

    respond_to do |format|
      format.html
      format.json
      format.rss { render layout: false }
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
