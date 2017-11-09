class Neofiles::DataStore::TempMongo
  include Neofiles::DataStore::MongoStorageHelper

  def self.chunks(id)
    Neofiles::TempFileChunk.where(file_id: id).order_by(n: :asc)
  end
end
