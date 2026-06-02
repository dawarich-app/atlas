class Authors::VersionsController < Authors::BaseController
  before_action :set_project_and_version

  def release
    @version.release!(number: params.require(:number), released_at: Date.parse(params.require(:released_at)))
    @project.versions.create!(number: "Unreleased", released_at: nil)
    redirect_to authors_project_path(@project), notice: "Released #{@version.number}."
  rescue Version::AlreadyReleased, ActiveRecord::RecordInvalid, Date::Error => e
    flash.now[:alert] = e.message
    head :unprocessable_content
  end

  def yank
    @version.yank!
    redirect_to authors_project_path(@project), notice: "Yanked #{@version.number}."
  rescue Version::CannotYankUnreleased => e
    flash.now[:alert] = e.message
    head :unprocessable_content
  end

  private

  def set_project_and_version
    @project = author_projects.find_by!(slug: params[:project_slug])
    @version = @project.versions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
