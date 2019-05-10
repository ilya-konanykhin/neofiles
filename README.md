Neofiles
========

Neofiles is a filesystem-like gem for storing and managing files, mainly for organizing attachments to Active Models
in Rails applications: avatars, logotypes, product images etc.

It is simple and powerful, but has some prerequisites. If you accept them it can keep the file management subsystem of
your application lightweight and headache-free. If you find yourself fighting it instead of enjoying it, maybe it is not
fitted for your task, try switching to more classic alternatives like Paperclip or Carrierwave.

The classical approach of storing files in a local filesystem and postprocessing them at the moment of upload/save has
the following drawbacks:

1.  Hard to copy/backup/shard the entire file set or its part.
1.  Almost impossible to make batch queries like finding a subset of files by some criteria.
1.  Complex metadata handling via a companion DB model + usually gems do not provide such functionality, DIY.
1.  Hard to change postprocessing rules, say when design changes and you need an avatar 20px larger — oops, we need to
    travel through all the objects and resave originals or thumbnails (if originals are available, of course, which
    is not always the case).
1.  The last point naturally leads to another: why at all a model needs to know how its logo must be resized or otherwise
    postprocessed for the sake of design or whatever? This is completely irrelevant to the model itself and should be
    defined elsewhere.

Neofiles addresses these issues in following ways:

***Database storage***: all files are stored in MongoDB database, thus providing standard (and very efficient)
mechanisms for backup, sharding, replication, monitoring & control, you name it. Most importantly, all this is done
by standard and well described tools, no need to put tricky cron jobs at night to backup several Gb.

***File models***: host (owner) models only store IDs of file objects `Neofiles::File` which is actually a metadata
container and a handle to real file bytes (a collection of `Neofiles::FileChunk`). The file + chunks concept is called
Mongo GridFS.

***File model is environment agnostic***: it does not know anything about its URL, thumbnail size and similar things.
It only stores data and metadata. To actually stream file bytes to clients there is a set of controllers (and of course
appropriate routes must be set up).

***No postprocessing at file save***: the only thing can be done is cropping extremely large images, like resizing
them to some max value to avoid storing unnecessarily detailed pics and keep disk & memory usage low.

***Postprocessing by request***: real job like resizing an avatar to 100x100px thumbnail is done by an HTTP request
at runtime, e.g. the real file URL might be `/neofiles/serve-image/ID`, whilst the thumbnail's is
`/neofiles/serve-image/ID/100x100` — all this is done in `Neofiles::ImagesController`, dedicated to serving and modifying
images. Any special logic for handling videos, audios, pdfs or whatever can be achieved in similar way (you have to code
it, only images are supported out of the box).

***Rely on webserver cache***: to keep things simple and not worry about caches and deleting thumbnails, the image
streaming controller always generates a fresh copy of postprocessed original, be it an original with watermarks or
a resized thumbnail. The task to cache the result is a burden of frontend webserver, like Nginx.

***Immutability***: technically, any file content and metadata can be changed, and any file can be completely deleted.
But deleting is useless as MongoDB does not reallocate deleted space to avoid partitioning. And if we agree that a file
can not be changed after it is uploaded (file immutability) we strongly simplify our lives as now we always have unique
correspondence between file ID and its content.

For example, we can tell Nginx to cache forever any image or its derivative simply by its URL of form
`/neofiles/serve-image/ID(/WxH)` since we know that no mater what, the content represented by this URL is always the same.
(Well, we can change watermarks — but this happens rarely, and eventually the whole cache will be updated).

Or on upload we can check if the same file exists in DB (by md5 hash) and if it is, create new file metadata pointing
to the same set of file chunks (byte content).

So, Neofiles does not automatically delete or alter existing files, only their metadata, which is ok.

***With all this in mind***, Neofiles can be viewed as a remote filesystem, where files with their metadata
are addressed and used by their IDs, as in `belongs_to/has_many`, and real file fetching (and postprocessing) is done
via HTTP requests to Content Delivery Network represented by a set of streaming controllers + caching frontend webserver
setup.

Installation, dependencies
--------------------------

Add Neofiles and its dependencies to your gemfile:

``` ruby
gem 'neofiles'
gem 'ruby-imagespec', git: 'git://github.com/dim/ruby-imagespec.git'
gem 'mini_magick', '3.7.0'
gem 'png_quantizator', '0.2.1'
```

***ruby-imagespec*** is needed to get an image file dimensions & content type.

***mini_magick*** does resizing & watermarking. Actually it is a lightweight wrapper around command-line utility
ImageMagick, which must be installed also. Refer to the gem's description for installation instructions.

***png_quantizator*** does lossless PNG compression. Actually it is a lightweight wrapper around command-line utility
Pngquant, which must be installed also. Refer to the gem's description for installation instructions.

Also, you must have installed MongoDB with its default driver ***mongoid*** (5 version at least) and Rails framework
with HAML templating engine. By default the gem needs `neofiles` mongoid client defined in `config/mongoid.yml`, which
can be changed in ***Configuration*** section.

Next, include CSS & JS files where needed (say, application.js or admin.js)...

``` javascript
#= require jquery # neofiles requires jquery
#= require neofiles
```

... and application.css/admin.css or whatever place you need it in:

``` css
 *= require neofiles
```

The last step is to set up routing which is as simple as adding a line to the `routes.rb`:
 
``` ruby
instance_eval &Neofiles.routes_proc
```

It produces the following routes:

```
$ rake routes | grep neofiles
   neofiles_file_compact GET       /neofiles/admin/file_compact(.:format)                              neofiles/admin#file_compact
      neofiles_file_save POST      /neofiles/admin/file_save(.:format)                                 neofiles/admin#file_save
    neofiles_file_remove POST      /neofiles/admin/file_remove(.:format)                               neofiles/admin#file_remove
    neofiles_file_update POST      /neofiles/admin/file_update(.:format)                               neofiles/admin#file_update
neofiles_redactor_upload POST      /neofiles/admin/redactor-upload(.:format)                           neofiles/admin#redactor_upload
  neofiles_redactor_list GET       /neofiles/admin/redactor-list/:owner_type/:owner_id/:type(.:format) neofiles/admin#redactor_list
           neofiles_file GET       /neofiles/serve/:id(.:format)                                       neofiles/files#show
          neofiles_image GET       /neofiles/serve-image/:id(/:format(/c:crop)(/q:quality))            neofiles/images#show {:format=>/[1-9]\d*x[1-9]\d*/, :crop=>/[10]/, :quality=>/[1-9]\d*/}
     neofiles_image_nowm GET       /neofiles/nowm-serve-image/:id(.:format)                            neofiles/images#show {:nowm=>true}
```

Routes `/neofiles/admin/*` form AJAX backend for file manipulations. The last 3 routes are for streaming controllers.

Usage with CCK
--------------

Neofiles gem is used mainly with two other gems: cck & [cck_forms](http://github.com/ilya-konanykhin/cck_forms) (CCK stands for Content Construction Kit).

Using these gems together provides straightforward and extremely easy way to handle file storage and manipulation.

***As cck & cck_forms are yet to be published (soon), I will only show the basic usage.***

``` ruby
# in model, say app/models/user.rb
class User
  include Mongoid::Document
  
  field :avatar, type: Cck::ParameterTypeClass::Image
  field :slider, type: Cck::ParameterTypeClass::Album
end

# in form view, say app/views/admin/users/edit.haml
= form_for @user do |f|
  .form-group
    label= Avatar image:
    = f.standalone_cck_field :avatar

  .form-group
    %label= Slider photos:
    = f.standalone_cck_field :slider

# everywhere else where you want to use avatar or slider photos, say on user profile page app/views/users/show.haml
.user-profile
  .avatar
    = neofiles_img_tag @user.avatar.value, width=100, height=100, {crop: 1}, {alt: "#{@user.name}'s avatar", class: 'avatar-img'}

  .slider
    = @user.slider.value.each do |img| # img is Neofiles::Image instance
      .slider-img
        = neofiles_img_link img, width=800, height=300
```

Note, that fields `avatar` and `slider` are wrappers around real `Neofiles::Image` values, so you need to unwrap them
with call to `.value`.

Standalone usage
----------------

The whole idea is to handle `Neofiles::File` instances via their IDs, without direct files manipulation.

In your MongoDB model create field to store file ID:

``` ruby
class User
  include Mongoid::Document
  
  belongs_to :avatar, class_name: 'Neofiles::Image'
  belongs_to :cv, class_name: 'Neofiles::File'
  
  # OR
  #
  # field :avatar_id, type: BSON::ObjectID # or type: String
  #
  # def avatar
  #   Neofiles::Image.where(id: avatar_id).first if avatar_id.present?
  # end
  #
  # def avatar=(other)
  #   self.avatar_id = other ? other.id : nil
  # end
end
```

With ActiveRecord, create ID field in database schema and define getter and setter to construct a `Neofiles::File`
instance like in example above.

Next, to build an edit form, construct an AJAX request to special action `Neofiles::AdminController#file_compact`, it
will generate HTML subform for file upload/edit. The subform contains all HTML & JS needed to asynchronously upload/edit
or delete file. Most importantly it contains so-called ***transfer input*** (hidden field) which gets populated with ID
of the newly created `Neofiles::File` instance on file upload (also it is emptied when a file is deleted). The key is this
input should have its `name` attribute in context of the outer form (of the host object) — you pass that name as an AJAX
parameter. Hence when a user saves the outer form, the ID value will be persisted alongside other host object fields.

``` haml
= form_for @user do |f|
  .form-group
    %label= Avatar image
    #avatar-container
      = f.hidden_field :avatar_id
    
    - file_compact_path = neofiles_file_compact_path(id: @user.avatar_id, input_name: 'user[avatar]')
    :javascript
      $(function() {
        $("#avatar-container").load("#{file_compact_path}", null, function() {
          $(this).children().unwrap();
        });
      })
```

The reason for inserting default hidden field is that an AJAX request can take long to load or even fail, and all this
time there will be no input with name `user[avatar]`, so controller may be confused and nullify that field if the "Save"
button is pressed by an impatient user.

Now, we can freely use the value stored, either directly of via helper:

``` haml
- pic = @user.avatar
- if pic
  This user has an avatar image of type #{pic.content_type} and of size #{pic.length} bytes.
  %br
  The original filename was #{pic.filename}, MD5 hash is #{pic.md5}.
  %br
  The image is:
  %img{src: neofiles_image_url(pic, format: '100x100', crop: '1', q: '90'), width: 100, height: 100}

  / OR EQUIVALENTLY
  
  = neofiles_img_tag pic, 100, 100, crop: 1, q: 90   
```

Delivering bytes
----------------

To actually get file bytes to users Neofiles offers two controllers — `FilesController` and `ImagesController` — and
three routes: `neofiles_file_url`, `neofiles_image_url` and `neofiles_image_nowm_url`.

The `FilesController` delivers bytes as-is, the `ImagesController` allows resizing & watermarking. `nowm` stands for "no
watermark" and is used when an admin is logged in (see ***Watermarking*** section).

The actual URLs look like this: `/neofiles/serve-file/FILE_ID`, `/neofiles/serve-image/IMAGE_ID/...`,
`/neofiles/nowm-serve-image/IMAGE_ID/...` (prefixed with domain and protocol).

When you request an image, you have several parameters to pass along:

* `format`: a string of form `WxH`, where `W` and `H` are max width and height correspondingly, that is the returned
  image will be no greater than that size.
* `crop`: a string, if `'1'` is passed, the image will be cropped and the aspect ratio of the resulting image will
  always be `W/H` (from the `format` parameter). Otherwise (default) the original aspect ratio will be preserved.
* `q`: an integer from 1 till 100. If passed, the image will be forced to JPEG format with the specified quality.  

It is ok to request an image via the `FilesController` as it is smart enough to redirect to the correct path.

***Production notes***:

1.  It may be good to put the burden of serving files to a different server than where your main application resides.
    Create a new environment called `neofiles` and setup its deploy accordingly (leave only Neofiles and MongoDB related
    things).

1.  Server from point (1) forms naturally a simple CDN: give it a proper name, say `strg.domain.com`, set it inside
    your neofiles config as `cdns` and all your files will be downloaded faster since browser can now send more
    parallel requests.
    
    If the server is powerful enough create even more domains like `str1/2/3...` pointing to it to get
    even more speed.

1.  (1) + (2) lead to the rule: always use `*_url` route helpers instead of `*_path` ones, as the former takes into
    account `cdns`. 

1.  Make sure your session cookies (or other means of identifying admins) are available to CDN domains since they need
    to check for `is_admin?`. 

1.  You ***must*** set up caching in front of streaming controllers, with one exception: `/neofiles/nowm-serve-image`
    must always hit the application as it checks if an admin is logged in. If you cache it you will give everyone
    watermarkless cached copies of image originals. Example Nginx config:

        server {
            listen 80;
            server_name strg1.domain.com strg2.domain.com;
            root /var/www/neofiles/current/public;
            
            location /neofiles/serve {
              
              if ($http_if_modified_since) {
                return 304;
              }
              if ($http_if_none_match) {
                return 304;
              }
            
              expires max;
              add_header Cache-Control public;
              add_header Last-Modified "Sat, 1 Jan 2012 00:00:00 GMT";
            
              proxy_cache_valid 200 30d;
              proxy_cache_valid 404 301 302 304 5m;
              proxy_cache_key "$request_uri";
              proxy_ignore_headers "Expires" "Cache-Control" "Set-Cookie";
            
              proxy_cache neofiles;
              proxy_pass http://neofiles;
            }
        }
        
        upstream neofiles {
            server unix:/var/run/neofiles.sock;
        }

View helpers
------------

The following view helpers are available, by example:

``` haml
- file  = Neofiles::File.first
- image = Neofiles::Image.first
- swf   = Neofiles::Swf.first

# <img src="/neofiles/serve-image/..." alt="..." width...>
= neofiles_img_tag image, 100, 100, {crop: 1}, {alt: '...'}

# <a href="/neofiles/serve-image/..." title="See fullsize"><img src=....></a>
= neofiles_img_link image, 100, 100, {crop: 0, q: 50}, {title: 'See fullsize'}, {alt: '...}

# <a href="/neofiles/serve-file/..." title="Download it!">My CV</a>
= neofiles_link file, "My CV", title: "Download it!"

# <object id="bnr_object_1" width... classid...>...</object>
= swf_embed 'bnr_object_1', neofiles_image_url(swf), swf.width, swf.height, '#f00', ''
```

Watermarks
----------

By default this gem watermarks images with a single watermark (at the bottom) from `app/assets/images/neofiles/watermark.png`
(it is a 1x1 transparent pixel by default). You can change this by redefining the config option `config.neofiles.watermarker`.
Its value must be a proc with signature `image, no_watermark:, watermark_width:, watermark_height:`. The arguments
are:

* `image`: a `MiniMagick::Image` instance to be watermarked.
* `no_watermark`: if this is `true` the proc must return the image's blob intact
* `watermark_width`, `watermark_height`: the image dimensions

The returned value must be converted to blob by the `MiniMagick::Image#to_blob` method.

As admins usually need watermarkless originals of images, you can specify the current admin via `config.neofiles.current_admin`.
If that proc returns something truthy a request to `/neofiles/nowm-serve-image/...` will not stamp watermarks. Otherwise
it will return an HTTP 403 Forbidden response. Check out watermarks caching problems in ***Delivering bytes*** section.

Configuration
-------------

Neofiles offers the following config options which can be set in `config/application.rb` or `config/environments/*.rb`:

``` ruby
# array of CDN strings like 'http://strg1.example.com'
config.neofiles.cdns = []

# if you need some special logic done before file save IN ADMIN CONTROLLER, put it here
# `file` is a Neofiles::File instance
config.neofiles.before_save = ->(file) do
  ...
end

# if you have a notion of "admin" (whatever it is), put here a logic to get the current "admin" object,
# it is used only when deciding if the current user can access watermarkless version of an image
# (`context` is a controller instance where the proc is called, so with Devise you can just do `context.current_admin`)
config.neofiles.current_admin = ->(context) do
  ...
end

# mongo specific settings — override them if you need to store data in some other database and/or collections
config.neofiles.mongo_files_collection    = 'files.files'
config.neofiles.mongo_chunks_collection   = 'files.chunks'
config.neofiles.mongo_client              = 'neofiles'
config.neofiles.mongo_default_chunk_size  = 4.megabytes

# image related settings
config.neofiles.image_rotate_exif     = true # rotate image, if exif contains orientation info
config.neofiles.image_clean_exif      = true # clean all exif fields on save
config.neofiles.image_max_dimensions  = nil  # resize huge originals to meaningful size: [w, h], {width: w, height: h}, wh
config.neofiles.image_max_crop_width  = 2000 # users can request resizing only up to this width
config.neofiles.image_max_crop_height = 2000 # users can request resizing only up to this height

# default watermarker — redefine to set special watermarking logic
# by default, watermark only images larger than 300x300 with a watermark at the bottom center, taken from
# app/assets/images/neofiles/watermark.png
config.neofiles.watermarker = ->(image, no_watermark: false, watermark_width:, watermark_height:) do
  ...
end
# config.neofiles.album_append_create_side = :right # picture when added is displayed on the right
```

Roadmap, TODOs
--------------

* Move HTML-building methods `admin_compact_view` to views or helper.
* Add proper authorization for admin controllers.
* Speed up image resize (`Image#save_file` has unnecessary steps).
* Move airbrake `notify_airbrake` calls to config.
* Configurable WYCIWYG editor (on/off, ability to use other than proprietary RadactorJS).
* Transform controller exceptions into meaningful error messages to users.

License
-------

Released under the [MIT License](http://www.opensource.org/licenses/MIT).
