class Neofiles::DataStore::Mongo
  include Neofiles::DataStore::MongoStorageHelper

  def self.chunks(id)
    Neofiles::FileChunk.where(file_id: id).order_by(n: :asc)
  end
end
