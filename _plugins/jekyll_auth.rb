# Jekyll plugin: /_plugins/jekyll_auth.rb

# DEBUG
# require 'debugger'

module Jekyll
  
  # Jekyll Auth Plugin - Plugin to manage http basic auth for jekyll generated pages and directories.
  #
  # Configuration:
  #
  # - ``auth_local_user_file``: 
  #   full qualified path to the locally generated user auth file;  
  #   default: ``/tmp/.jekyll_user_file``.
  # - ``auth_remote_user_file``: 
  #   full qualified path to the user auth file, when it is deployed. is written 
  #   into the .htaccess files; no default value.
  # - ``auth_local_group_file``: 
  #   full qualified path to the locally generated group auth file;
  #   default: ``/tmp/.jekyll_group_file``.
  # - ``auth_remote_group_file``:
  #   full qualified path to the group auth file, when it is deployed. is written 
  #   into the .htaccess files; no default value.
  #
  #  
  class AuthGenerator < Generator
        
    priority :high
    
    def generate site
      puts; puts "#### Jekyll::Auth"
      
      # Read in data
      auth = Auth.new site
      
      # Validate
      auth.validate!
      
      # Write user file
      size = auth.users.size
      puts "#{size} User#{size>1||size==0 ? 's' : ''} found#{size>0 ? ':' : ''}" # Logging Users
      auth.generate_user_file
      
      # Write group file
      size = auth.groups.size
      puts "#{size} Group#{size>1||size==0 ? 's' : ''} found#{size>0 ? ':' : ''}" # Logging Groups
      auth.groups.values.each do |group|
        puts "  - #{group.groupname}: #{group.users.join(' ')}"
      end
      auth.generate_group_file
      
      # Logging Resources
      size = auth.directories.size
      puts "#{size} Director#{size>1||size==0 ? 'ies' : 'y'} with restricted access found#{size>0 ? ':' : ''}"
      auth.directories.values.each do |dir|
        puts "  - #{dir.dir}"
      end
      size = auth.files.size
      puts "#{size} File#{size>1||size==0 ? 's' : ''} with restricted access (" +
        "not supported yet".red + ") found#{size>0 ? ':' : ''}"
      auth.files.values.each do |file|
        puts "  - #{file.path}"
      end
      
      # Write directives into .htaccess files
      auth.write_directives(site)
    end
            
  end
  
  class Auth
    attr_reader :users, :groups, :directories, :files,
      :remote_user_file, :remote_group_file
    
    def initialize site
      @users = {}; @groups = {}
      @directories = {}; @files = {}
      
      read_config site
      read_posts site
      
      # TODO: validate!!
    end
    
    def read_config site
      @local_user_file = site.config['auth_local_user_file'] || '/tmp/.jekyll_user_file'
      @remote_user_file = site.config['auth_remote_user_file']
      @local_group_file = site.config['auth_local_group_file'] || '/tmp/.jekyll_group_file'
      @remote_group_file = site.config['auth_remote_group_file']
      
      add_users site.config['auth_users'] if(site.config['auth_users'])
      add_groups site.config['auth_groups'] if(site.config['auth_groups'])
      add_dirs site.config['auth_dirs'] if (site.config['auth_dirs'])
    end
    
    def read_posts site
      # collect all posts and pages with auth info
      payload = site.site_payload
      auth_pp = payload['site']['posts'].concat(payload['site']['pages']).select do |post| 
        post.data.has_key?('auth_users') || post.data.has_key?('auth_groups')
      end
      # read auth info from every page or post
      auth_pp.each do |p|
        p_users = p.data['auth_users'] ? add_users(p.data['auth_users']) : []
        p_groups = p.data['auth_groups'] ? add_groups(p.data['auth_groups']) : []
        if (p.data['layout'] == 'set')
          p.data['auth_dir'] = add_dir(p.url, p.data['auth_users'], p.data['auth_groups'], p.data['auth_valid_user'])
        end
        # TODO AuthFiles!
      end
    end
        
    def validate!
      unless (invalid_users = @users.values.select{|user| !user.valid?}).empty?
        raise Exception.new "Invalid Auth-Users found in your config/posts: #{invalid_users.map(&:username).join(', ')}"
      end
      unless (invalid_groups = @groups.values.select{|group| !group.valid?}).empty?
        raise Exception.new "Invalid Auth-Groups found in your config/posts: #{invalid_groups.map(&:groupname).join(', ')}"
      end
    end
    
    def generate_user_file
      # create user_file directory if not existant yet
      user_dir = File.dirname(@local_user_file)
      FileUtils.mkdir_p(user_dir) unless File.exists?(user_dir)
      # generate user entries in user file
      @users.values.each_with_index do |user, i|
        if i == 0
          user.generate_user_file @local_user_file
        else
          user.update_user_file @local_user_file
        end
      end
    end
    
    def generate_group_file
      # create group_file directory if not existant yet
      group_dir = File.dirname(@local_group_file)
      FileUtils.mkdir_p(group_dir) unless File.exists?(group_dir)
      # generate group entries in group file
      File.open(@local_group_file, 'w') do |groupfile|
        @groups.values.each do |auth_group|
          groupfile.puts "#{auth_group.groupname}: #{auth_group.users.join(' ')}"
        end
      end  
    end
    
    def write_directives site
      create_htaccess_files site
    end
    
    def create_htaccess_files site
      directories.values.each do |auth_dir|
        site.pages << HtaccessFile.new(site, site.source, auth_dir, self)
      end
    end
    
    # Hash with username => password mapping or String with space seperated
    # usernames
    # Returns Array of AuthUser objects
    def add_users hash_or_string
      new_users = []
      if hash_or_string.is_a?(String)
        hash_or_string.split(' ').each do |uname|
          new_users << add_user(uname)
        end
      elsif hash_or_string.is_a?(Hash)
        hash_or_string.each do |uname, pword|
          new_users << add_user(uname, pword)
        end
      end
      new_users
    end
    
    def add_user username, password=nil
      if !@users[username]
        @users[username] = AuthUser.new(username, password)
      elsif password
        if !@users[username].password 
          @users[username].password = password
        elsif password != @users[username].password
          raise Exception.new "User '#{username}' specified with different passwords!"
        end
      end
      @users[username]
    end
    
    def add_groups hash_or_string
      new_groups = []
      if hash_or_string.is_a?(String)
        hash_or_string.split(' ').each do |gname|
          new_groups << add_group(gname)
        end
      elsif hash_or_string.is_a?(Hash)
        hash_or_string.each do |gname, users|
          new_groups << add_group(gname, users)
        end
      end
      new_groups
    end
    
    def add_group name, users=''
      if !@groups[name]
        @groups[name] = AuthGroup.new(name, users.split(' '))
      elsif !users.empty?
        @groups[name].users += users.split(' ')
      end
      @groups[name]
    end
    
    # dirs is a Hash:
    # with dirnames as keys and 
    # a Hash with auth_users, auth_groups, auth_valid_user as its values
    def add_dirs dirs
      new_dirs = []
      dirs.each do |dir_name, dir|
        new_dirs << add_dir(dir_name, dir['auth_users'], dir['auth_groups'], dir['auth_valid_user'])
      end
      new_dirs
    end
    
    def add_dir dir_name, users, groups, valid_user
      # add users
      new_users = users ? add_users(users) : []
      # add groups
      new_groups = groups ? add_groups(groups) : []
        
      # add dirs
      if !@directories[dir_name]
        @directories[dir_name] = AuthDirectory.new(dir_name, new_users, new_groups, valid_user)
      else
        @directories[dir_name].users += new_users
        @directories[dir_name].groups += new_groups
      end
      @directories[dir_name]
    end
    
  end # end Auth
  
  
  class HtaccessFile < Page
    # override Page#dir: which returns / or the path as described with #permalink
    attr_accessor :dir
    def initialize(site, base, auth_dir, auth)
      @site = site
      @base = base
      @dir = auth_dir.dir
      @name = '.htaccess'
      
      self.process(@name)
      self.read_yaml(File.join(base, '_layouts'), '.htaccess')
      # pass data to the 'page'
      self.data['auth_dir'] = auth_dir
      self.data['auth_remote_user_file'] = auth.remote_user_file
      self.data['auth_remote_group_file'] = auth.remote_group_file
    end
  end
  

  class AuthResource
    attr_reader :dir
    attr_accessor :users, :groups
    # users, groups are Arrays of AuthUser and AuthGroup objects
    # valid_user is a boolean
    def initialize dir, users, groups, valid_user
      @users = users; 
      @valid_user = valid_user
      @groups = groups;
      @dir = dir
    end
        
    def to_liquid
      {
        'users' => @users.map(&:username).uniq,
        'groups' => @groups.map(&:groupname).uniq,
        'valid_user' => @valid_user,
        'dir'   => @dir
      }
    end
  end


  class AuthDirectory < AuthResource
  end
  
  # TODO: wird noch nicht geschrieben
  class AuthFile < AuthResource
    attr_reader :file, :path
    def initialize path, users, groups, valid_user
      super File.dirname(path), users, groups, valid_user
      @path = path
      @file = File.basename(path)
    end
    
    def to_liquid
      super.merge({
        'file' => @file
      })
    end
  end
    
  
  class AuthUser
    attr_reader :username
    attr_accessor :password 
    
    def initialize username, password
      @username = username
      @password = password
    end
    
    # username and password not empty, no spaces
    def valid?
      !username.nil? && !password.nil? && !username.empty? && !password.empty? &&
        username.index(/\s/).nil? && password.index(/\s/).nil?
    end

    def generate_user_file user_file_path
      `htpasswd -cb #{user_file_path} #{@username} #{@password}`
    end
    
    def update_user_file user_file_path
      `htpasswd -b #{user_file_path} #{@username} #{@password}`
    end
  end
  
  class AuthGroup
    attr_reader :groupname
    attr_accessor :users
    
    # users: Array of usernames
    def initialize groupname, users=[]
      @groupname = groupname
      @users = users
    end
    
    # groupname not empty, no spaces, users.any?
    def valid?
      !groupname.nil? && !groupname.empty? && groupname.index(/\s/).nil? && users.any?
    end
  end
  
end