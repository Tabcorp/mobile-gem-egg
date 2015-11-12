require 'xcodeproj'

require 'pathname'

require 'egg/assertion'
require 'egg/eggfile'
require 'egg/egg'
require 'egg/installedegg'

##############################################
# Installer - responsible for producing output consumable by Xcode for an eggfile
# This will include a .lib and potentially things like an .xcconfig, and a resource file list
class Installer
  def initialize(eggfile)
    @rootEggfile = eggfile
    puts "[!] Root Eggfile must specify platform" unless eggfile.platform != nil
    assert {eggfile.platform != nil}
    @installedEggs = {}
  end

  def install()
    Dir.mkdir ".eggs" unless File.exists? ".eggs"
    installPathString = ".eggs/#{@rootEggfile.name}"
    rootPath = Pathname.new(File.absolute_path(""))
    Dir.mkdir installPathString unless File.exists? installPathString

    # Prepare all the repositories
    @pendingEggs = @rootEggfile.eggs
    while !@pendingEggs.empty? do
      egg = @pendingEggs.shift
      installEgg(egg, installPathString)
    end

    # Create an Xcode project
    eggLibraryName = "#{@rootEggfile.name}-eggs"
    project = Xcodeproj::Project.new("#{installPathString}/#{eggLibraryName}.xcodeproj")
    deploymentTarget = "5.1.1"
    if (@rootEggfile.platform == :osx)
      deploymentTarget = "10.9"
    end

    target = project.new_target(:static_library, eggLibraryName, @rootEggfile.platform, deploymentTarget)
    target.instance_variable_set(:@uuid, Digest::MD5.hexdigest(eggLibraryName)[0,24].upcase)
    target.build_configuration_list.set_setting("COPY_PHASE_STRIP","NO")

    # Add a dummy.m file
    File.open("#{installPathString}/Dummy.m", 'w') {|f| f.write("// Dummy File to keep the compiler happy") }
    dummyFileRef = project.new_file("Dummy.m")
    target.add_file_references([dummyFileRef])

    project.build_configuration_list.set_setting("ONLY_ACTIVE_ARCH","NO")
    project.build_configuration_list.set_setting("COPY_PHASE_STRIP","NO")
    project.build_configuration_list.set_setting("STRIP_INSTALLED_PRODUCT","NO")

    includePaths = []
    frameworks = []

    libGroup = project.new_group('lib');
    @installedEggs.values.each { |dependency|
      depTarget = findTarget(dependency.installationPath, dependency.name)
      projectPath = Pathname.new depTarget.project.path
      depProjectReference = libGroup.new_reference(projectPath.to_s);

      includePaths << projectPath.dirname.relative_path_from(rootPath).to_s

      # Add the dep target as a dependency of the main target
      target.add_dependency(depTarget);

      if depTarget.product_reference.explicit_file_type == "wrapper.framework"
        # If it's a framework, we need to instruct the application to link it
        frameworks << depTarget.product_reference.path.gsub(/\.framework\Z/,"")
      else
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
      end
    }

    # Add an xcconfig file for inclusion
    File.open("#{installPathString}/eggs.xcconfig", 'w') { |f|
      f.write("EGG_HEADER_SEARCH_PATHS =")
      includePaths.each { |path|
        f.write(" \"#{path}\"")
      }
      f.write("\n")

      f.write("EGG_OTHER_LDFLAGS =")
      frameworks.each { |framework|
        f.write(" -framework \"#{framework}\"")
      }
      f.write("\n")

      if frameworks.count > 0
        f.write("EGG_FRAMEWORK_SEARCH_PATHS = $(CONFIGURATION_BUILD_DIR)")
      end
    }

    project.save()
  end

  private
  def installEgg(egg, path)
    installedEgg = @installedEggs[egg.name]
    if installedEgg
      installedEgg.ensureCompatibilityWith(egg.url)
      if egg.sha
        installedEgg.sha = egg.sha
        @pendingEggs += installedEgg.dependencies;
      end
      return;
    else
      installedEgg = InstalledEgg.installEgg(egg, path)
      @installedEggs[egg.name] = installedEgg
      @pendingEggs += installedEgg.dependencies;
    end
  end

  private
  def findTarget(path, targetName)
    globPattern = File.join(path,"**","/*.xcodeproj")
    Dir.glob(globPattern).each { |projectPath|
      project = Xcodeproj::Project.open(projectPath)
      target = project.targets.find { |t| t.name == targetName }
      if target
        return target
      end
    }

    puts "[!] Target #{targetName} not found in #{globPattern}"
    assert { false }
  end
end
