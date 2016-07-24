class Neofiles::FileChunk

  include Mongoid::Document

  store_in collection: Rails.application.config.neofiles.mongo_chunks_collection, client: Rails.application.config.neofiles.mongo_client

  belongs_to :file, class_name: 'Neofiles::File'

  field :n, type: Integer, default: 0 # что это за поле?
  field :data, type: BSON::Binary

  def to_s
    data.data
  end
end
