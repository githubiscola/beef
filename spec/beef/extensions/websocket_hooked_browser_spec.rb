# encoding: UTF-8
#
# Copyright (c) 2006-2020 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#

require 'rest-client'
require 'json'
require_relative '../../support/constants'
require_relative '../../support/beef_test'
require 'core/main/network_stack/websocket/websocket'
require 'websocket-client-simple'

RSpec.describe 'BeEF WebSockets: Browser Hooking', :run_on_browserstack => true do
  before(:all) do
      @config = BeEF::Core::Configuration.instance
      puts "This is the /n #@config "
      @secure_port = @config.get('beef.http.websocket.secure_port')
      puts "This is the /n #@secure_port"
      @config.set('beef.http.websocket.secure', true)
      @config.set('beef.http.websocket.enable', true)
      #set config parameters
      @username = @config.get('beef.credentials.user')
      puts "This is the /n #@username "
      @password = @config.get('beef.credentials.passwd')
      puts "This is the /n #@password "
    
		  # Load BeEF extensions and modules
	  	# Always load Extensions, as previous changes to the config from other tests may affect
		  # whether or not this test passes.
	  	print_info "Loading in BeEF::Extensions"
	  	BeEF::Extensions.load
	  	sleep 2

		  # Check if modules already loaded. No need to reload.
	  	if @config.get('beef.module').nil?
		  	print_info "Loading in BeEF::Modules"
		  	BeEF::Modules.load

		  	sleep 2
		  else
		  		print_info "Modules already loaded"
		  end

		  # Grab DB file and regenerate if requested
		  print_info "Loading database"
	  	db_file = @config.get('beef.database.file')

	  	if BeEF::Core::Console::CommandLine.parse[:resetdb]
		  	print_info 'Resetting the database for BeEF.'
		  	File.delete(db_file) if File.exists?(db_file)
		  end

	  	# Load up DB and migrate if necessary
	  	ActiveRecord::Base.logger = nil
	  	OTR::ActiveRecord.migrations_paths = [File.join('core', 'main', 'ar-migrations')]
		  OTR::ActiveRecord.configure_from_hash!(adapter:'sqlite3', database: db_file)

		  context = ActiveRecord::Migration.new.migration_context
	  	if context.needs_migration?
		    ActiveRecord::Migrator.new(:up, context.migrations, context.schema_migration).migrate
	  	end

	  	sleep 2

		  BeEF::Core::Migration.instance.update_db!

	  	# Spawn HTTP Server
	  	print_info "Starting HTTP Hook Server"
		  http_hook_server = BeEF::Core::Server.instance
    http_hook_server.prepare
    
    		# Generate a token for the server to respond with
    @token = BeEF::Core::Crypto::api_token
    
    @pids = fork do
    BeEF::API::Registrar.instance.fire(BeEF::API::Server, 'pre_http_start', http_hook_server)
    end
    @pid = fork do
    http_hook_server.start
    end
    # wait for server to start
    sleep 2

    #start the hook server instance, for it out to track the pids for graceful closure
		@caps = CONFIG['common_caps'].merge(CONFIG['browser_caps'][TASK_ID])
		@caps["name"] = self.class.description || ENV['name'] || 'no-name'
    @caps["browserstack.local"] = true
    @caps['browserstack.localIdentifier'] = ENV['BROWSERSTACK_LOCAL_IDENTIFIER']

		@driver = Selenium::WebDriver.for(:remote,
				:url => "http://#{CONFIG['user']}:#{CONFIG['key']}@#{CONFIG['server']}/wd/hub",
				:desired_capabilities => @caps)

    # Hook new victim
		print_info 'Hooking a new victim, waiting a few seconds...'
    @driver.navigate.to "#{VICTIM_URL}"
		# Give time for browser hook to occur
    sleep 2.5
    #prepare for the HTTP model


  end

  after(:all) do
    puts @driver 
  #  @driver.quit
    # cleanup: delete test browser entries and session
    # kill the server
    @config.set('beef.http.websocket.enable', false)
    Process.kill("KILL", @pid)
    Process.kill("KILL", @pids)
    puts "waiting for server to die.."
  end

  it 'can hook a browser with websockets' do
    #require 'byebug'; byebug
    https = BeEF::Core::Models::Http
    puts https
    @debug_mod_ids = JSON.parse(RestClient.get "#{RESTAPI_MODULES}?token=#{@token}")
    puts @debug_mod_ids
    @hooks = JSON.parse(RestClient.get "#{RESTAPI_HOOKS}?token=#{@token}")
    puts @hooks
    @session = @hooks['hooked-browsers']['online']
    puts @session
    puts "this is th https session that gets deleted"
    puts https.where(:hooked_browser_id => @session['0']['session'])
    expect(@session).not_to be_empty
    #https.where(:hooked_browser_id => @session['0']['session']).delete_all
  end
end
