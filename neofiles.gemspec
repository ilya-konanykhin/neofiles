$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "neofiles/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "neofiles"
  s.version     = Neofiles::VERSION
  s.authors     = ["Konanykhin Ilya"]
  s.email       = ["rails@neolabs.kz"]
  s.homepage    = "http://restoran.kz"
  s.summary     = "TODO: Summary of neofiles."
  s.description = "TODO: Description of neofiles."

  s.files = Dir["{app,config,db,lib}/**/*"] + ["LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency "rails"
  # s.add_dependency "jquery-rails"

  # s.add_development_dependency "sqlite3"
end
