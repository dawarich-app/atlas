class Authors::ProjectsController < Authors::BaseController
  before_action :set_project, only: %i[show edit update destroy]

  def index
    @projects = author_projects.order(name: :asc)
  end

  def new
    @project = author_projects.build
  end

  def create
    @project = author_projects.build(project_params)

    if @project.save
      @project.versions.create!(number: "Unreleased", released_at: nil)
      redirect_to authors_project_path(@project), notice: "Project created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @versions = @project.versions.ordered.includes(:entries)
    @unreleased = Version.unreleased_for(@project)
    @metrics = InstanceMetrics.for(@project)
    @embed_snippet = build_embed_snippet(@project)
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to authors_project_path(@project), notice: "Project updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @project.destroy!
    redirect_to authors_projects_path, notice: "Project deleted."
  end

  private

  def set_project
    @project = author_projects.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def project_params
    params.require(:project).permit(:slug, :name, :description, :homepage_url)
  end

  def build_embed_snippet(project)
    host = Rails.application.config.x.widget_host
    <<~HTML.strip
      <script src="#{host}/w/v1/loader.js"
              data-slug="#{project.slug}"
              data-version="YOUR_VERSION"
              defer></script>
    HTML
  end
end
