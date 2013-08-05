# encoding: UTF-8
require "neofiles/engine"

module Neofiles
  # maybe config
  mattr_accessor :routes_proc
  @@routes_proc = proc do
    scope 'neofiles', module: :neofiles do
      get  '/admin/file_compact/', to: 'admin#file_compact', as: 'neofiles_file_compact'
      post '/admin/file_save/', to: 'admin#file_save', as: 'neofiles_file_save'
      post '/admin/file_remove/', to: 'admin#file_remove', as: 'neofiles_file_remove'

      post '/admin/redactor-upload/', to: 'admin#redactor_upload', as: 'neofiles_redactor_upload'
      get  '/admin/redactor-list/:owner_type/:owner_id/:type', to: 'admin#redactor_list', as: 'neofiles_redactor_list'

      get  '/serve/:id', to: 'files#show', as: 'neofiles_file'
      get  '/serve-image/:id(/:format(/c:crop))', to: 'images#show', as: 'neofiles_image', constraints: {format: /[1-9]\d*x[1-9]\d*/, crop: /[10]/}
    end
  end
end

require_relative "../app/models/neofiles"
