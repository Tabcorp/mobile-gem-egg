require 'singleton'
require 'pathname'
require 'git'

########################################################################
# Singleton class to encapsulate a library of git reference repositories
class GitReferenceLibrary
  include Singleton

  @@semaphore = Mutex.new

  def initialize
    libraryRootString = File.absolute_path(".eggs/.gitreferences")
    Dir.mkdir libraryRootString unless File.exists? libraryRootString
    @libraryRoot = Pathname.new libraryRootString
    #ASDTODO pull the libraryRoot from environment variable, and then default to the above if it's not set
  end

  def clone(remote, localPath)
    referencePath = referencePathForRemote(remote)
    repoKey = repoKeyForRemote(remote)
    puts "Cloning #{repoKey} From Reference"
    runCommand("git clone --reference #{referencePath} #{remote} #{localPath} 2>&1")
  end

  def update(remote)
    referencePath = referencePathForRemote(remote)
    repoKey = repoKeyForRemote(remote)
    puts "Updating #{repoKey} Reference"
    runCommand("pushd #{referencePath}; git remote update; popd;")
  end

  private
  def referencePathForRemote(remote)
    repoKey = repoKeyForRemote(remote)
    referencePath = @libraryRoot + repoKey
    referencePathString = referencePath.to_path
    if File.exists? referencePathString
      #ASDTODO ensure it's the correct thing
    else
      puts "Cloning #{repoKey} Reference"
      runCommand("git clone --mirror #{remote} #{referencePathString} 2>&1")
    end
    return referencePathString;
  end

  private
  def repoKeyForRemote(remote)
    return remote.split('/').last.split('.').first
  end

  private

  # Systen ENV variables involved in the git commands.
  #
  # @return [<String>] the names of the EVN variables involved in the git commands
  ENV_VARIABLE_NAMES = ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_SSH']

  # Takes the current git's system ENV variables and store them.
  def store_git_system_env_variables
    @git_system_env_variables = {}
    ENV_VARIABLE_NAMES.each do |env_variable_name|
      @git_system_env_variables[env_variable_name] = ENV[env_variable_name]
    end
  end

  # Takes the previously stored git's ENV variables and set them again on ENV.
  def restore_git_system_env_variables
    ENV_VARIABLE_NAMES.each do |env_variable_name|
      ENV[env_variable_name] = @git_system_env_variables[env_variable_name]
    end
  end

  # Sets git's ENV variables to the custom values for the current instance.
  def set_custom_git_env_variables
    ENV['GIT_DIR'] = nil
    ENV['GIT_WORK_TREE'] = nil
    ENV['GIT_INDEX_FILE'] = nil
    ENV['GIT_SSH'] = nil
  end

  # Runs a block inside an environment with customized ENV variables.
  # It restores the ENV after execution.
  #
  # @param [Proc] block block to be executed within the customized environment
  def with_custom_env_variables(&block)
    @@semaphore.synchronize do
      store_git_system_env_variables()
      set_custom_git_env_variables()
      return block.call()
    end
  ensure
    restore_git_system_env_variables()
  end

  def runCommand(cmd)
    with_custom_env_variables do
      command_thread = Thread.new do
        output = `#{cmd}`.chomp
        exitstatus = $?.exitstatus
      end
      command_thread.join
    end

    if exitstatus > 1 || (exitstatus == 1 && output != '')
      raise "[!] GitReferenceLibrary Command Failed!"
    end
  end

end
