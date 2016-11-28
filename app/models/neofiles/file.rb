# This model stores file metadata like name, size, md5 hash etc. A model ID is essentially what is a "file" in the
# rest of an application. In some way Neofiles::File may be seen as remote filesystem, where you drop in files and keep
# their generated IDs to fetch them later, or setup web frontend via Neofiles::Files/ImagesController and request file
# bytes by ID from there.
#
# When persisting new file to the MongoDB database one must initialize new instance with metadata and set field #file=
# to IO-like object that holds real bytes. When #save method is called, file metadata are saved into Neofiles::File
# and file content is read and saved into collection of Neofiles::FileChunk, each of maximum length of #chunk_size bytes:
#
#   logo = Neofiles::File.new
#   logo.description = 'ACME inc logo'
#   logo.file = '~/my-first-try.png' # or some opened file handle, or IO stream
#   logo.filename = 'acme.png'
#   logo.save
#   logo.chunks.to_a # return an array of Neofiles::FileChunk in order
#   logo.data # byte string of file contents
#
#   # in view.html.slim
#   - logo = Neofiles::File.find 'xxx'
#   = neofiles_file_url logo          # 'http://doma.in/neofiles/serve-file/#{logo.id}'
#   = neofiles_link logo, 'Our logo'  # '<a href="...#{logo.id}">Our logo</a>'
#
# This file/chunks concept is called Mongo GridFS (Grid File System) and is described as a standard way of storing files
# in MongoDB.
#
# MongoDB collection & client (session) can be changed via Rails.application.config.neofiles.mongo_files_collection
# and Rails.application.config.neofiles.mongo_client
#
# Model fields:
#
#   filename      - real name of file, is guessed when setting #file= but can be changed manually later
#   content_type  - MIME content type, is guessed when setting #file= but can be changed manually later
#   length        - file size in bytes
#   chunk_size    - max Neofiles::FileChunk size in bytes
#   md5           - md5 hash of file (to find duplicates for example)
#   description   - arbitrary description
#   owner_type/id - as in Mongoid polymorphic belongs_to relation, a class name & ID of object this file belongs to
#   is_deleted    - flag that file was once marked as deleted (just a flag for future use, affects nothing)
#
# There is no sense in deleting a file since space it used to hold is not reallocated by MongoDB, so files are considered
# forever lasting. But technically it is possible to delete model instance and it's chunks will be deleted as well.
#
class Neofiles::File

  include Mongoid::Document
  include Mongoid::Timestamps

  store_in collection: Rails.application.config.neofiles.mongo_files_collection, client: Rails.application.config.neofiles.mongo_client

  has_many :chunks, dependent: :destroy, order: [:n, :asc], class_name: 'Neofiles::FileChunk'

  DEFAULT_CHUNK_SIZE = Rails.application.config.neofiles.mongo_default_chunk_size

  field :filename, type: String
  field :content_type, type: String
  field :length, type: Integer, default: 0
  field :chunk_size, type: Integer, default: DEFAULT_CHUNK_SIZE
  field :md5, type: String, default: Digest::MD5.hexdigest('')
  field :description, type: String
  field :owner_type, type: String
  field :owner_id, type: String
  field :is_deleted, type: Mongoid::Boolean

  validates :filename, :length, :chunk_size, :md5, presence: true

  before_save :save_file
  after_save :nullify_unpersisted_file



  # Yield block for each chunk.
  def each(&block)
    chunks.all.order_by([:n, :asc]).each do |chunk|
      block.call(chunk.to_s)
    end
  end

  # Get a portion of chunks, either via Range of Fixnum (length).
  def slice(*args)
    case args.first
      when Range
        range = args.first
        first_chunk = (range.min / chunk_size).floor
        last_chunk = (range.max / chunk_size).ceil
        offset = range.min % chunk_size
        length = range.max - range.min + 1
      when Fixnum
        start = args.first
        start = self.length + start if start < 0
        length = args.size == 2 ? args.last : 1
        first_chunk = (start / chunk_size).floor
        last_chunk = ((start + length) / chunk_size).ceil
        offset = start % chunk_size
    end

    data = ''

    chunks.where(n: first_chunk..last_chunk).order_by(n: :asc).each do |chunk|
      data << chunk
    end

    data[offset, length]
  end

  # Chunks bytes concatenated, that is the whole file content.
  def data
    data = ''
    each { |chunk| data << chunk }
    data
  end

  # Encode bytes in base64.
  def base64
    Array(to_s).pack('m')
  end

  # Encode bytes id data uri.
  def data_uri(options = {})
    data = base64.chomp
    "data:#{content_type};base64,#{data}"
  end

  # Bytes as chunks array, if block is given — yield it.
  def bytes(&block)
    if block
      each { |data| block.call(data) }
      length
    else
      bytes = []
      each { |data| bytes.push(*data) }
      bytes
    end
  end



  attr_reader :file

  # If not nil the next call to #save will fetch bytes from this file and save them in chunks.
  # Filename and content type are guessed from argument.
  def file=(file)
    @file = file

    if @file
      self.filename = self.class.extract_basename(@file)
      self.content_type = self.class.extract_content_type(filename) || 'application/octet-stream'
    else
      self.filename = nil
      self.content_type = nil
    end
  end

  # Are we going to save file bytes on next #save?
  def unpersisted_file?
    not @file.nil?
  end

  # Real file saving goes here.
  # File length and md5 hash are computed automatically.
  def save_file
    if @file
      self.chunks.delete_all

      md5 = Digest::MD5.new
      length, n = 0, 0

      self.class.reading(@file) do |io|
        self.class.chunking(io, chunk_size) do |buf|
          md5 << buf
          length += buf.size
          chunk = self.chunks.build
          chunk.data = self.class.binary_for(buf)
          chunk.n = n
          n += 1
          chunk.save!
          self.chunks.push(chunk)
        end
      end

      self.length = length
      self.md5    = md5.hexdigest
    end
  end

  # Reset @file after save.
  def nullify_unpersisted_file
    @file = nil
  end

  # Representation of file in admin "compact" mode, @see Neofiles::AdminController#file_compact.
  # To be redefined by descendants.
  def admin_compact_view(template)
    template.neofiles_link self, nil, target: '_blank'
  end

  # Yield block with IO stream made from input arg, which can be file name or other IO readable object.
  def self.reading(arg, &block)
    if arg.respond_to?(:read)
      self.rewind(arg) do |io|
        block.call(io)
      end
    else
      open(arg.to_s) do |io|
        block.call(io)
      end
    end
  end

  # Split IO stream by chunks chunk_size bytes each and yield each chunk in block.
  def self.chunking(io, chunk_size, &block)
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
  def self.binary_for(*buf)
    BSON::Binary.new(buf.join, :generic)
  end

  # Try different methods to extract file name or path from argument object.
  def self.extract_basename(object)
    filename = nil
    %i{ original_path original_filename path filename pathname }.each do |msg|
      if object.respond_to?(msg)
        filename = object.send(msg)
        break
      end
    end
    filename ? cleanname(filename) : nil
  end

  # Try different methods to extract MIME content type from file name, e.g. jpeg -> image/jpeg
  def self.extract_content_type(basename)
    if defined?(MIME)
      content_type = MIME::Types.type_for(basename.to_s).first
    else
      ext = ::File.extname(basename.to_s).downcase.sub(/[.]/, '')
      if ext.in? %w{ jpeg jpg gif png }
        content_type = 'image/' + ext.sub(/jpg/, 'jpeg')
      elsif ext == 'swf'
        content_type = 'application/x-shockwave-flash'
      else
        content_type = nil
      end
    end

    content_type.to_s if content_type
  end

  # Extract only file name partion from path.
  def self.cleanname(pathname)
    ::File.basename(pathname.to_s)
  end

  # Guess descendant class of Neofiles::File by MIME content type to use special purpose class for different file types:
  #
  #   Neofiles::File.file_class_by_content_type('image/jpeg') # -> Neofiles::Image
  #   Neofiles::File.file_class_by_content_type('some/unknown') # -> Neofiles::File
  #
  # Can be used when persisting new files or loading from database.
  #
  def self.class_by_content_type(content_type)
    case content_type
    when /\Aimage\//
      ::Neofiles::Image
    when 'application/x-shockwave-flash'
      ::Neofiles::Swf
    else
      self
    end
  end

  # Same as file_class_by_content_type but for file name string.
  def self.class_by_file_name(file_name)
    class_by_content_type(extract_content_type(file_name))
  end

  # Same as file_class_by_content_type but for file-like object.
  def self.class_by_file_object(file_object)
    class_by_file_name(extract_basename(file_object))
  end

  # Yield IO-like argument to block rewinding it first, if possible.
  def self.rewind(io, &block)
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
