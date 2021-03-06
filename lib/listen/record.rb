module Listen
  class Record
    include Celluloid

    attr_accessor :paths, :listener

    def initialize(listener)
      @listener = listener
      @paths    = _init_paths
    end

    def set_path(path, data)
      new_data = file_data(path).merge(data)
      @paths[::File.dirname(path)][::File.basename(path)] = new_data
    end

    def unset_path(path)
      @paths[::File.dirname(path)].delete(::File.basename(path))
    end

    def file_data(path)
      @paths[::File.dirname(path)][::File.basename(path)] || {}
    end

    def dir_entries(path)
      @paths[path.to_s]
    end

    def build
      @paths = _init_paths
      listener.directories.each do |path|
        options = { type: 'Dir', recursive: true, silence: true }
        listener.registry[:change_pool].change(path, options)
      end
    rescue
      Celluloid.logger.warn "build crashed: #{$!.inspect}"
      raise
    end

    private

    def _init_paths
      Hash.new { |h, k| h[k] = Hash.new }
    end
  end
end
