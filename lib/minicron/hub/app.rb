# Apparently this is the only way to conditionally load this, eww
begin

  require 'better_errors'
rescue LoadError
end

require 'sinatra/activerecord'
require 'sinatra/assetpack'
require 'minicron'
require 'sinatra/base'
require 'sinatra/json'
require 'erubis'
require 'pathname'
require 'ansi-to-html'

module Minicron::Hub
  class App < Sinatra::Base
    register Sinatra::ActiveRecordExtension
    register Sinatra::AssetPack

    # Set the application root
    set :root, Minicron::HUB_PATH

    configure :development do
      if defined?(BetterErrors)
        use BetterErrors::Middleware
        BetterErrors.application_root = __dir__
      end
    end

    # General Sinatra configuration
    configure do
      # Don't log them. We'll do that ourself
      set :dump_errors, false

      # Don't capture any errors. Throw them up the stack
      set :raise_errors, true

      # Disable internal middleware for presenting errors as HTML
      set :show_exceptions, false

      # Used to enable asset compression, currently nothing else
      # relies on this
      set :environment, :production

      # Force the encoding to be UTF-8 to prevent assetpack encoding issues
      Encoding.default_external = Encoding::UTF_8
    end

    # Configure how we serve assets
    assets do
      serve '/css',   :from => 'assets/css'
      serve '/js',    :from => 'assets/js'
      serve '/fonts', :from => 'assets/fonts'

      js_compression :simple

      # Set up the application css
      css :app, '/css/all.css', [
        '/css/bootswatch.min.css',
        '/css/main.css',
        '/css/perfect-scrollbar-0.4.10.min.css'
      ]

      # Set up the application javascript
      js :app, '/js/all.js', [
        # Dependencies, the order of these is important
        '/js/jquery-2.1.0.min.js',
        '/js/bootstrap-3.1.1.min.js',
        '/js/moment-2.5.1.min.js',
        '/js/perfect-scrollbar-0.4.10.with-mousewheel.min.js',

        '/js/application.js',
        '/js/schedules.js'
      ]
    end

    # Register our helpers
    helpers do
      def route_prefix
        Minicron::Transport::Server.get_prefix
      end

      def ansi_to_html(output)
        Ansi::To::Html.new(output).to_html(:solarized)
      end
    end

    # Called on class initilisation, sets up the database and requires all
    # the application files
    def initialize
      super

      # Initialize the db
      Minicron::Hub::App.setup_db

      # Load all our models
      Dir[File.dirname(__FILE__) + '/models/*.rb'].each do |model|
        require model
      end

      # Load all our controllers
      Dir[File.dirname(__FILE__) + '/controllers/**/*.rb'].each do |controller|
        require controller
      end
    end

    # Used to set up the database connection
    def self.setup_db
      # Configure the database
      case Minicron.config['server']['database']['type']
      when /mysql|postgresql/
        set :database,
            :adapter => Minicron.get_db_adapter(Minicron.config['server']['database']['type']),
            :host => Minicron.config['server']['database']['host'],
            :database => Minicron.config['server']['database']['database'],
            :username => Minicron.config['server']['database']['username'],
            :password => Minicron.config['server']['database']['password']
      when 'sqlite'
        # Calculate the realtive path to the db because sqlite or activerecord is
        # weird and doesn't seem to handle abs paths correctly
        root = Pathname.new(Dir.pwd)
        db = Pathname.new(Minicron::HUB_PATH + '/db')
        db_rel_path = db.relative_path_from(root)

        ActiveRecord::Base.establish_connection(
          :adapter => Minicron.get_db_adapter(Minicron.config['server']['database']['type']),
          :database => "#{db_rel_path}/minicron.sqlite3" # TODO: Allow configuring this but default to this value
        )
      else
        raise Minicron::DatabaseError, "The database #{Minicron.config['server']['database']['type']} is not supported"
      end

      # Enable ActiveRecord logging if in verbose mode
      ActiveRecord::Base.logger = Minicron.config['verbose'] ? Logger.new(STDOUT) : nil
    end
  end
end
