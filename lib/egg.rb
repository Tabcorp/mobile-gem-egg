require 'git'
require 'xcodeproj'

##############################################
# DIY Dodgy Assertion
class AssertionError < RuntimeError
end
def assert &block
    raise AssertionError unless yield
end

##############################################
# Class to represent an Egg
class Egg
	attr_reader :name, :url, :relativePath, :sha

    def initialize(name, config)
        @name = name
        @config = config

        @relativePath = config[:path]
        @url = config[:url]
        @sha = config[:sha]

        assert {url || relativePath}
    end
end

##############################################
# Class to represent an Eggfile
class Eggfile
	attr_reader :name, :eggs

	def initialize(name)
	    @name = name
		@eggs = []
	end

	def self.read(filepath)
		assert {$currentEggfile == nil}
		name = File.basename(filepath, File.extname(filepath))
		$currentEggfile = Eggfile.new(name)
		load(filepath)
		eggfile = $currentEggfile
		$currentEggfile = nil
		return eggfile
	end

	def addEgg(egg)
		@eggs << egg
	end
end

##############################################
# Eggfile DSL
def egg(name, config)
    egg = Egg.new(name, config)
	$currentEggfile.addEgg(egg)
end

##############################################
# Class to represent an egg that has been installed
# NB: dependencies may not have been installed yet, and it may need to be updated to a different commit
class InstalledEgg
	attr_reader :name, :remote, :installationPath, :relativePath, :sha

    def initialize(name, remote, relativePath, installationPath)
        @name = name
        @remote = remote
        @relativePath = relativePath
        @installationPath = installationPath
        @sha = nil
        loadEggfile
    end

    def ensureCompatibilityWith(remote)
      if @relativePath
        return
      end

  		repo = Git.open(installationPath)
  		origin = repo.remote('origin')
  		if !origin || remote != origin.url
  			raise "[!] #{name} already on disk, but does not match source repo #{remote}; aborting!"
  		end
    end

    # Installs an egg, (not its dependencies)
    # This is done by either cloning the repo, or updating the repo if it already exists
    def self.installEgg(egg, installationPath)
      name = egg.name
      sha = egg.sha

      if egg.relativePath
          assert { !File.exists? installationPath }
          # Create symlink
          FileUtils.symlink File.absolute_path(egg.relativePath), installationPath
          return InstalledEgg.new(name, nil, egg.relativePath, installationPath)
      else
          remote = egg.url

          if File.exists? installationPath
            repo = Git.open(installationPath)
            origin = repo.remote('origin')
            if !origin || remote != origin.url
              raise "[!] #{name} already on disk, but does not match source repo #{remote}; aborting!"
            end
            puts "Updating #{name}"
            repo.checkout('master')
            repo.pull
          else
            puts "Cloning #{name}"
            repo = Git.clone(remote, installationPath)
          end

          installedEgg = InstalledEgg.new(name, remote, nil, installationPath)
          if sha
            installedEgg.sha = sha
          end

          return installedEgg
      end
    end

    def sha=(value)
    	if sha == value
    		return
    	end

    	raise "#{@name} already locked to commit #{@sha}" unless !@sha
      raise "#{@name} is locked to path #{@relativePath}, cannot specify sha" unless !@relativePath
		  @sha = value

		  puts "Updating #{name} to commit #{@sha}"
    	repo = Git.open(@installationPath)
    	origin = repo.remote('origin')
    	origin.fetch
    	repo.checkout(@sha)

    	loadEggfile
    end

    def dependencies
    	if @eggfile
    		return @eggfile.eggs
    	else
    		return []
    	end
    end

    private
    def loadEggfile
    	@eggfile = nil
  		eggfilePath = "#{@installationPath}/#{@name}.eggfile"
  		if File.exists? eggfilePath
  			@eggfile = Eggfile.read(eggfilePath)
        FileUtils.symlink "..", "#{@installationPath}/#{@name}.eggs"
  		end
    end
end

##############################################
# Installer - responsible for producing output consumable by Xcode for an eggfile
# This will include a .lib and potentially things like an .xcconfig, and a resource file list
class Installer
	def initialize(eggfile)
		@rootEggfile = eggfile
		@installedEggs = {}
	end

	def install()
    installPath = "#{@rootEggfile.name}.eggs"
		Dir.mkdir installPath unless File.exists? installPath

		# Prepare all the repositories
		@pendingEggs = @rootEggfile.eggs
		while !@pendingEggs.empty? do
			egg = @pendingEggs.shift
			installEgg(egg, installPath)
		end

		# Create an Xcode project
		eggLibraryName = "#{@rootEggfile.name}-eggs"
		project = Xcodeproj::Project.new("#{installPath}/#{eggLibraryName}.xcodeproj")
		target = project.new_target(:static_library, eggLibraryName, :ios, "5.1.1")
    # Add a dummy.m file
    File.open("#{installPath}/Dummy.m", 'w') {|f| f.write("// Dummy File to keep the compiler happy") }
    dummyFileRef = project.new_file("Dummy.m")
    target.add_file_references([dummyFileRef])

    project.build_configuration_list.set_setting("ONLY_ACTIVE_ARCH","NO")

		libGroup = project.new_group('lib');

    @installedEggs.values.each { |dependency|
      depTarget = findTarget(dependency.installationPath, dependency.name)
      depProjectReference = libGroup.new_reference(depTarget.project.path);

      # Add the dep target as a dependency of the main target
      target.add_dependency(depTarget);

      # Link the target lib to the main target
      containerItemProxy = project.new(Xcodeproj::Project::PBXContainerItemProxy)
      containerItemProxy.container_portal = depProjectReference.uuid
      containerItemProxy.proxy_type = '2'
      containerItemProxy.remote_global_id_string = depTarget.product_reference.uuid
      containerItemProxy.remote_info = dependency.name

      referenceProxy = project.new(Xcodeproj::Project::PBXReferenceProxy)
      referenceProxy.file_type = depTarget.product_reference.explicit_file_type
      referenceProxy.path = depTarget.product_reference.path
      referenceProxy.remote_ref = containerItemProxy
      referenceProxy.source_tree = depTarget.product_reference.source_tree

      productGroup = project.new(Xcodeproj::Project::PBXGroup)
      productGroup.name = "Products"
      productGroup.source_tree = "<group>"
      productGroup << referenceProxy

      attrb = Xcodeproj::Project::Object::AbstractObjectAttribute.new(:references_by_keys, :project_references, Xcodeproj::Project::PBXProject)
      attrb.classes = [Xcodeproj::Project::PBXFileReference, Xcodeproj::Project::PBXGroup]
      projectReference = Xcodeproj::Project::ObjectDictionary.new(attrb, project.root_object)
      projectReference['ProjectRef'] = depProjectReference
      projectReference['ProductGroup'] = productGroup
      project.root_object.project_references << projectReference

      target.frameworks_build_phase.add_file_reference(referenceProxy)
    }

		project.save()
	end

	private
	def installEgg(egg, path)
		installationPath = "#{path}/#{egg.name}"

		installedEgg = @installedEggs[egg.name]
		if installedEgg
			installedEgg.ensureCompatibilityWith(egg.url)
			if egg.sha
				installedEgg.sha = egg.sha
				@pendingEggs += installedEgg.dependencies;
			end
			return;
		else
			installedEgg = InstalledEgg.installEgg(egg, installationPath)
			@installedEggs[egg.name] = installedEgg
			@pendingEggs += installedEgg.dependencies;
		end
	end

  private
  def findTarget(path, targetName)
    Dir.glob("#{path}/*.xcodeproj").each { |projectPath|
      project = Xcodeproj::Project.open(projectPath)
      target = project.targets.find { |t| t.name == targetName }
      if target
        return target
      end
    }
    puts "[!] Target #{targetName} not found in #{path}/*.xcodeproj"
    assert { false }
  end
end
