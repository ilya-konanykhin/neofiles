module Neofiles::DataStore::MongoStorageHelper
  extend ActiveSupport::Concern

  included do
    DEFAULT_CHUNK_SIZE = Rails.application.config.neofiles.mongo_default_chunk_size

    def self.find(id)
      if chunks(id).any?
        new(id)
      else
        raise Neofiles::DataStore::NotFoundException
      end
    end

    attr_reader :id, :data, :length, :md5

    def initialize(id)
      @id = id
    end

    def data
      @data ||= chunks.pluck(:data).map(&:data).join
    end

    def length
      @length ||= data.length
    end

    def md5
      @md5 ||= begin
        md5 = Digest::MD5.new
        md5 << data
        md5.hexdigest
      end
    end

    def write(data)
      data_buf  = []
      md5       = Digest::MD5.new
      length, n = 0, 0

      reading(data) do |io|
        chunking(io, DEFAULT_CHUNK_SIZE) do |buf|
          md5 << buf
          data_buf << buf
          length += buf.size
          chunk = chunks.build file_id: id
          chunk.data = binary_for buf
          chunk.n = n
          n += 1
          chunk.save!
        end
      end

      @data   = data_buf.join
      @length = length
      @md5    = md5.hexdigest
    end

    private

    def chunks
      self.class.chunks id
    end

    # Yield block with IO stream made from input arg, which can be file name or other IO readable object.
    def reading(arg, &block)
      if arg.respond_to?(:read)
        rewind(arg) do |io|
          block.call(io)
        end
      else
        open(arg.to_s) do |io|
          block.call(io)
        end
      end
    end

    # Split IO stream by chunks chunk_size bytes each and yield each chunk in block.
    def chunking(io, chunk_size, &block)
      if io.method(:read).arity == 0
        data = io.read
        i = 0
        loop do
          offset = i * chunk_size
          length = i + chunk_size < data.size ? chunk_size : data.size - offset

          break if offset >= data.size

          buf = data[offset, length]
          block.call(buf)
          i += 1
        end
      else
        while buf = io.read(chunk_size)
          block.call(buf)
        end
      end
    end

    # Construct Mongoid binary object from string of bytes.
    def binary_for(*buf)
      BSON::Binary.new buf.join, :generic
    end

    # Yield IO-like argument to block rewinding it first, if possible.
    def rewind(io, &block)
      begin
        pos = io.pos
        io.flush
        io.rewind
      rescue
        nil
      end

      begin
        block.call(io)
      ensure
        begin
          io.pos = pos
        rescue
          nil
        end
      end
    end
  end
end
