module Widget
  # Single source of truth for the widget version. Bumped by hand on each
  # widget release. The same value is embedded into app/assets/builds/widget.v1.js
  # as the WIDGET_VERSION constant.
  module CurrentVersion
    VALUE = "1.5.0".freeze

    module_function

    def value
      VALUE
    end

    def immutable_path_segment
      "v#{VALUE}"
    end
  end
end
