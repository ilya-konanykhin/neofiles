$:.push File.expand_path('../lib', __FILE__)

require 'neofiles/version'

Gem::Specification.new do |s|
  s.name        = 'neofiles'
  s.version     = Neofiles::VERSION
  s.authors     = ['Konanykhin Ilya']
  s.email       = ['rails@neolabs.kz']
  s.homepage    = 'http://neoweb.kz'
  s.summary     = 'Serves and manages files & images.'
  s.description = 'Library for managing files: creating & storing, linking to file owners, serving files from MongoDB'
  s.license     = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*'] + ['LICENSE', 'Rakefile', 'README.md']
  s.test_files = Dir['spec/**/*']

  s.add_dependency 'rails', '~> 4.0'
  s.add_dependency 'mongoid', '~> 5.0'
  s.add_dependency 'ruby-imagespec', '0.4.1'  # parse SWF files for width & height info
  s.add_dependency 'mini_magick', '3.7.0'     # image manipulation utility (wrapper around famous console tool ImageMagick)
  s.add_dependency 'png_quantizator', '0.2.1' # lossless PNG compression
end
