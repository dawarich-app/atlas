class Widget::LoadersController < ApplicationController
  # Cross-origin XHR/fetch is the entire point of this endpoint.
  skip_forgery_protection

  def show
    project = Project.find_by!("lower(slug) = ?", params[:slug].to_s.downcase)
    record_beacon(project)
    set_widget_headers
    render json: WidgetPayload.call(project: project, requested_version: requested_version)
  rescue ActiveRecord::RecordNotFound
    set_widget_headers
    render json: {}, status: :not_found
  end

  private

  def requested_version
    (params[:v].presence || "unknown").to_s
  end

  def origin
    OriginNormalizer.call(request).to_s
  end

  def record_beacon(project)
    BeaconEvent.create!(
      project: project,
      origin:  origin,
      version: requested_version
    )
  rescue StandardError => e
    # Best-effort: a beacon write failure (validation, DB connection drop,
    # statement timeout, etc.) must NOT 500 the user-facing widget payload.
    Rails.error.report(e, context: { project_id: project.id, source: "widget_beacon" }, handled: true)
    Rails.logger.warn("[chibichange] beacon write failed for project=#{project.id}: #{e.class}")
  end

  def set_widget_headers
    response.headers["Cache-Control"]               = "no-store"
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Vary"]                        = "Origin"
  end
end
