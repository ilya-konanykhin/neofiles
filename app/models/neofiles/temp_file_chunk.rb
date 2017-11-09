# Model for storing temporary portion of bytes from particular Neofiles::File. Has only two fields: the bytes string #data
# and sequence number #n
#
class Neofiles::TempFileChunk
  include Neofiles::FileChunkHelper

  store_in collection: Rails.application.config.neofiles.mongo_temp_chunks_collection, client: Rails.application.config.neofiles.mongo_client

  before_save :create_collection

  private

  def create_collection
    return if mongo_client.database.collection_names.include?(Rails.application.config.neofiles.mongo_temp_chunks_collection)
    mongo_client[
        Rails.application.config.neofiles.mongo_temp_chunks_collection,
        capped: true,
        size: Rails.application.config.neofiles.mongo_temp_chunks_collection_size
    ].create
  end
end
