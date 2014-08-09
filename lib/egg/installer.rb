require 'xcodeproj'

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
    @installedEggs = {}
  end

  def install()
    Dir.mkdir ".eggs" unless File.exists? ".eggs"
    installPath = ".eggs/#{@rootEggfile.name}"
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

    # Add an xcconfig file for inclusion
    File.open("#{installPath}/eggs.xcconfig", 'w') { |f|
      f.write("EGG_HEADER_SEARCH_PATHS =")
      @installedEggs.values.each { |dependency|
        f.write(" \"#{dependency.installationPath}\"")
      }
      f.write("\n")
    }

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
