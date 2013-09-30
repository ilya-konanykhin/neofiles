$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "neofiles/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "neofiles"
  s.version     = Neofiles::VERSION
  s.authors     = ["Konanykhin Ilya"]
  s.email       = ["rails@neolabs.kz"]
  s.homepage    = "http://neoweb.kz"
  s.summary     = "Serves files & images."
  s.description = "No description yet."

  s.files = Dir["{app,config,db,lib}/**/*"] + ["LICENSE", "Rakefile", "README.md"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency "rails"
  s.add_dependency "mongoid"
  s.add_dependency "ruby-imagespec"
end
