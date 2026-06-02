class Authors::EntriesController < Authors::BaseController
  before_action :set_project
  before_action :set_entry, only: %i[update destroy]

  def create
    unreleased = Version.unreleased_for(@project) || @project.versions.create!(number: "Unreleased", released_at: nil)
    @entry = unreleased.entries.build(entry_params.merge(body_tokens: tokens_from(entry_params[:body_markdown])))

    if @entry.save
      redirect_to authors_project_path(@project), notice: "Entry added."
    else
      flash.now[:alert] = @entry.errors.full_messages.to_sentence
      head :unprocessable_content
    end
  rescue ArgumentError => e
    flash.now[:alert] = e.message
    head :unprocessable_content
  end

  def update
    return reject_released unless @entry.version.unreleased?

    if @entry.update(entry_params.merge(body_tokens: tokens_from(entry_params[:body_markdown])))
      redirect_to authors_project_path(@project), notice: "Entry updated."
    else
      flash.now[:alert] = @entry.errors.full_messages.to_sentence
      head :unprocessable_content
    end
  rescue ArgumentError => e
    flash.now[:alert] = e.message
    head :unprocessable_content
  end

  def destroy
    return reject_released unless @entry.version.unreleased?

    @entry.destroy!
    redirect_to authors_project_path(@project), notice: "Entry deleted."
  end

  private

  def set_project
    @project = author_projects.find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def set_entry
    return if performed?

    @entry = Entry.joins(version: :project).where(versions: { project_id: @project.id }).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def entry_params
    params.require(:entry).permit(:kind, :body_markdown)
  end

  def tokens_from(md)
    Markdown::Tokenizer.call(md)
  end

  def reject_released
    flash.now[:alert] = "Cannot edit entries on a released version."
    head :unprocessable_content
  end
end
