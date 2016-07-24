$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'neofiles/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'neofiles'
  s.version     = Neofiles::VERSION
  s.authors     = ['Konanykhin Ilya']
  s.email       = ['rails@neolabs.kz']
  s.homepage    = 'http://neoweb.kz'
  s.summary     = 'Serves and manages files & images.'
  s.description = 'Library for managing files: creating & storing, linking to file owners, serving files from MongoDB'

  s.files = Dir['{app,config,db,lib}/**/*'] + ['LICENSE', 'Rakefile', 'README.md']
  s.test_files = Dir['spec/**/*']

  s.add_dependency 'rails', '4.0.0'
  s.add_dependency 'mongoid', '5.0.0'
  s.add_dependency 'ruby-imagespec' # определения ширины и высоты флешевого файла
  s.add_dependency 'mini_magick'
end
