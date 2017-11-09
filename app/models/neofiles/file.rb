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
  include Neofiles::DataStore::Mongo::FileHelper
  include Neofiles::DataStore::TempMongo::FileHelper

  store_in collection: Rails.application.config.neofiles.mongo_files_collection, client: Rails.application.config.neofiles.mongo_client

  field :filename, type: String
  field :content_type, type: String
  field :length, type: Integer, default: 0
  field :md5, type: String, default: Digest::MD5.hexdigest('')
  field :description, type: String
  field :owner_type, type: String
  field :owner_id, type: String
  field :is_deleted, type: Mongoid::Boolean
  field :is_temp, type: Mongoid::Boolean, default: false

  before_save :save_file
  after_save :nullify_unpersisted_file

  # Chunks bytes concatenated, that is the whole file content.
  def data
    self.class.read_data_stores(is_temp).each do |store|
      begin
        return store.find(id).data
      rescue Neofiles::DataStore::NotFoundException
        next
      end
    end
  end

  # Encode bytes in base64.
  def base64
    Array(data).pack('m')
  end

  # Encode bytes id data uri.
  def data_uri(options = {})
    data = base64.chomp
    "data:#{content_type};base64,#{data}"
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
      self.is_temp = true if Rails.application.config.neofiles.use_temp_storage

      self.class.write_data_stores(is_temp).each do |store|
        begin
          data_store_object = store.new id
          data_store_object.write @file
          self.length = data_store_object.length
          self.md5    = data_store_object.md5
        rescue => ex
          notify_airbrake(ex) if defined? notify_airbrake
          next
        end
      end
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
      elsif ext == 'svg'
        content_type = 'image/svg+xml'
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
    when 'image/svg+xml'
      ::Neofiles::File
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

  def self.read_data_stores(temp = false)
    stores = temp ? Rails.application.config.neofiles.read_temp_data_stores : Rails.application.config.neofiles.read_data_stores
    get_stores_class_name stores
  end

  def self.write_data_stores(temp = false)
    stores = temp ? Rails.application.config.neofiles.write_temp_data_stores : Rails.application.config.neofiles.write_data_stores
    get_stores_class_name stores
  end

  # return array with names for each store
  def self.get_stores_class_name(stores)
    if stores.is_a?(Array)
      stores.map { |store| Neofiles::DataStore.const_get(store.camelize) }
    else
      get_stores_class_name [stores]
    end
  end

end
