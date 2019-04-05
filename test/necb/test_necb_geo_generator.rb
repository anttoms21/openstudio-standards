require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'
require 'json'
require 'parallel'
require 'etc'
require 'securerandom'
require 'fileutils'
$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)

# number of processors used for parallelization
ProcessorsUsed = (Parallel.processor_count - 1).floor

class GeoTest < Minitest::Test

  #This method will take a standard name and a range and return an array of an array of spacetypes that are in increments of the range value
  def determine_space_types_to_test(standard:, range:)
    vintage = standard
    #Get the correct standard
    standard = Standard.build(standard)
    #taking and filtering the space types (removing all wild cards)
    spacetypes_unfilterted = standard.standards_lookup_table_many(table_name: 'space_types').select {|spacetype| spacetype["necb_hvac_system_selection_type"] != "Wildcard"}
    #creating variable to place all the wanted space types in
    spacetypes = []

    #checks if the vintage is NECB2011
    if vintage == "NECB2011"
      #filters out undefined
      spacetypes_unfilterted_lockerroom = spacetypes_unfilterted.select {|spacetype| spacetype["space_type"] != "- undefined -"}
      #Filters out locker room (there is a error with the service hot water)
      spacetypes = spacetypes_unfilterted_lockerroom.select {|spacetype| spacetype["ventilation_secondary_space_type"] != "Locker room"}
    end

    #checks if the vintage is NECB2015
    if vintage == "NECB2015"
      #filters out undefined
      spacetypes_unfilterted_undefined = spacetypes_unfilterted.select {|spacetype| spacetype["space_type"] != "- undefined -"}
      #filters out Atrium (height < 6m) due issues with SHW
      spacetypes_w_atrium1 = spacetypes_unfilterted_undefined.select {|spacetype| spacetype["ventilation_secondary_space_type"] != "Atrium (height < 6m)"}
      #filters out Atrium (height > 12m due to issues with SHW)
      spacetypes = spacetypes_w_atrium1.select {|spacetype| spacetype["ventilation_secondary_space_type"] != "Atrium (height > 12m)"}
    end
    if vintage == "NECB2017"
      #filters out undefined
      spacetypes_unfilterted_undefined = spacetypes_unfilterted.select {|spacetype| spacetype["space_type"] != "- undefined -"}
      #filters out Atrium (height < 6m) due issues with SHW
      spacetypes_w_atrium1 = spacetypes_unfilterted_undefined.select {|spacetype| spacetype["ventilation_secondary_space_type"] != "Atrium (height < 6m)"}
      #filters out Atrium (height > 12m due to issues with SHW)
      spacetypes = spacetypes_w_atrium1.select {|spacetype| spacetype["ventilation_secondary_space_type"] != "Atrium (height > 12m)"}
    end
    puts "Number of space types before ajdusting for the range: #{spacetypes.size}"
    #Checks if the number of spacetypes is a multiple of the range
    while (spacetypes.size % range != 0)
      #if the space type is not a multiple of the range adjust to prevent issues when simulating the last building
      spacetypes.push(spacetypes[0])
    end
    number_of_models = (spacetypes.size / range)
    puts "the number of spacetypes is #{spacetypes.size}"
    puts "the number of building is  #{number_of_models}"

    #Add array container to save the sets of range to be used later.
    array_of_array_of_spacetypes = []
    #Interate through the number of models.
    (0..(number_of_models -1)).to_a.each do |model_number|
      #Get the starting index
      start = model_number * range
      #Save the range to the array.
      array_of_array_of_spacetypes << spacetypes[start, range]
    end
    return array_of_array_of_spacetypes
  end


  def create_building_with_space_types(standard:, all_spacetypes:, run_dir:)
    #creating an empty model object
    model = OpenStudio::Model::Model.new()
    standard = Standard.build(standard)
    number_of_floors = (all_spacetypes.size) / 5
    model.getBuilding.setStandardsNumberOfStories(number_of_floors)
    model.getBuilding.setStandardsNumberOfAboveGroundStories(number_of_floors)

    #Create Geometry shell.
    BTAP::Geometry::Wizards::create_shape_rectangle(model,
                                                    100.0,
                                                    100.0,
                                                    number_of_floors,
                                                    0,
                                                    3.8,
                                                    1,
                                                    25,
                                                    0.0,
    )

    #Array to store spacetypes by name.
    space_type_objects = []
    all_spacetypes.each do |spacetype_info|
      spacetype = OpenStudio::Model::SpaceType.new(model)
      #setting standard space type
      spacetype.setStandardsSpaceType(spacetype_info['space_type'])
      #setting standard building type
      spacetype.setStandardsBuildingType(spacetype_info['building_type'])
      #setting the space type name
      spacetype.setName(spacetype_info['building_type'] + " " + spacetype_info['space_type'])
      space_type_objects << spacetype
    end

    model.getSpaces.each_with_index do |space, index|
      #set space type name
      space.setSpaceType(space_type_objects[index])
      #set space name name (this will cause errors if not set like this)
      space.setName("#{space_type_objects[index].standardsSpaceType.get}-#{space_type_objects[index].standardsBuildingType.get}")
    end

    standard.model_create_thermal_zones(model)
    standard.model_apply_standard(model: model,
                                  epw_file: 'CAN_AB_Fort.McMurray.AP.716890_CWEC2016.epw',
                                  sizing_run_dir: run_dir,
                                  new_auto_zoner: true)

    return model
  end

  def test_main()
    #Create Test Folder to perform runs in.
    #To do.. you should remove the old runs in this folder.
    vintages = ['NECB2011', 'NECB2015', 'NECB2017']
    num_space_types_per_building = 15
    test_dir = "#{File.dirname(__FILE__)}/models/geo_test"
    if Dir.exists?(test_dir)
      FileUtils.rm_rf(test_dir)
    end
    Dir.mkdir(test_dir)
    #Get array of arrays in groups of 20. See this method above on how I did this.
    # For debugging just using .first (would be good to see what happend with .last )
    vintages.each do |vintage|
      vintage_dir = "#{test_dir}/#{vintage}"
      if Dir.exists?(vintage_dir)
        Dir.mkdir(vintage_dir)
      end
      array_of_array_of_space_types = determine_space_types_to_test(standard: vintage, range:num_space_types_per_building)
      Parallel.each_with_index(array_of_array_of_space_types, in_processes: (ProcessorsUsed), progress: "Progress :") do |array_of_space_types, index|
        #Create a unique folder name to do the runs in..
        #puts "space types in this building are#{array_of_space_types.size}"
        #name = SecureRandom.uuid.to_s

        run_dir = "#{test_dir}/#{vintage}/building#{index}"
        if Dir.exists?(run_dir)
          Dir.mkdir(run_dir)
        end
        #create the model
        model = create_building_with_space_types(standard: vintage, all_spacetypes: array_of_space_types, run_dir: run_dir)

        #run the model in the run folder. Note the version does not matter here.. I just want to run the simulation
        Standard.build(vintage).model_run_simulation_and_log_errors(model, run_dir)
        #save osm file.
        model_out_path = "#{run_dir}/final.osm"
        model.save(model_out_path, true)
      end
    end
  end
end