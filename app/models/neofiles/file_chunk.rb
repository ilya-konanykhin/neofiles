# Model for storing portion of bytes from particular Neofiles::File. Has only two fields: the bytes string #data
# and sequence number #n
#
class Neofiles::FileChunk
  include Neofiles::FileChunkHelper

  store_in collection: Rails.application.config.neofiles.mongo_chunks_collection, client: Rails.application.config.neofiles.mongo_client
end
