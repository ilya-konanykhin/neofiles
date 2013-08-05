# encoding: UTF-8
module Neofiles
  class Engine < ::Rails::Engine
    # isolate_namespace Neofiles
    config.autoload_paths << File.expand_path("../..", __FILE__)
  end
end
