module Admin
  class RegionsController < BaseController
    def update
      names = Array(params[:regions]).map(&:to_s)
      catalog = RegionCatalog.load_dir(regions_dir)

      names.each { |n| catalog.find(n) }

      RegionSelection.transaction do
        RegionSelection.delete_all
        names.each_with_index do |name, position|
          RegionSelection.create!(region_name: name, active: true, position: position)
        end
      end

      region = RegionContext.current(regions_dir: regions_dir)
      Turbo::StreamsChannel.broadcast_replace_to(
        "region_channel",
        target: "region_meta",
        partial: "home/region_meta",
        locals: { region: region }
      )

      respond_to do |format|
        format.html { head :ok }
        format.json { render json: { regions: RegionSelection.active_names }, status: :ok }
      end
    end

    private

    def regions_dir
      ENV.fetch("REGIONS_DIR") do
        candidates = [Rails.root.join("regions"), Rails.root.join("..", "regions")]
        candidates.find { |p| File.directory?(p) } || candidates.first
      end
    end
  end
end
