require_relative '../helpers/minitest_helper'
require_relative '../helpers/create_doe_prototype_helper'


class NECB_Autozone_Tests < MiniTest::Test

  def setup()
    @output_folder = "#{File.dirname(__FILE__)}/output/autozoner"
    @relative_geometry_path = "/../../lib/openstudio-standards/standards/necb/NECB2011/data/geometry/"
    @epw_file = 'CAN_ON_Toronto.Pearson.Intl.AP.716240_CWEC2016.epw'
    @template = 'NECB2011'
    @climate_zone = 'NECB HDD Method'
    FileUtils.mkdir_p(@output_folder) unless File.directory?(@output_folder)
  end



  def test_HighriseApartment()
    model = autozone("HighriseApartment.osm")
  end

  def test_LargeOffice()
    model = autozone("LargeOffice.osm")
  end

  def test_MediumOffice()
    model = autozone("MediumOffice.osm")
  end
  def test_MidriseApartment()
    model = autozone("MidriseApartment.osm")
  end
  def test_Outpatient()
    model = autozone("Outpatient.osm")
  end
  def test_QuickServiceRestaurant()
    model = autozone("QuickServiceRestaurant.osm")
  end

  def test_RetailStandalone()
    model = autozone("RetailStandalone.osm")
  end

  def test_RetailStripmall()
    model = autozone("RetailStripmall.osm")
  end


  def test_SmallHotel()
    model = autozone("SmallHotel.osm")
  end


  def test_SmallOffice()
    model = autozone("SmallOffice.osm")
  end

  def test_Warehouse()
    model = autozone("Warehouse.osm")
  end

  def test_FullServiceRestaurant()
    model = autozone("FullServiceRestaurant.osm")
  end

  def test_LargeHotel()
    model = autozone("LargeHotel.osm")
  end

  def test_PrimarySchool()
    model = autozone("PrimarySchool.osm")
  end

  def test_SecondarySchool()
    model = autozone("SecondarySchool.osm")
  end



  # Test to validate the heat pump performance curves
  def autozone(filename)
    outfile = @output_folder + "/#{filename}_autozoned.osm"
    File.delete(outfile) if File.exist?(outfile)
    outfile_json = @output_folder + "/#{filename}_autozoned.json"
    File.delete(outfile_json) if File.exist?(outfile_json)

    standard = Standard.build(@template)
    model = BTAP::FileIO.load_osm("#{File.dirname(__FILE__)}#{@relative_geometry_path}#{filename}")
    return false unless standard.validate_initial_model(model)

    #Ensure that the space types names match the space types names in the code.
    return false unless standard.validate_space_types(model)


    #Ensure that the space types names match the space types names in the code.
    return false unless standard.validate_space_types(model)


    #Get rid of any existing Thermostats. We will only use the code schedules.
    model.getThermostatSetpointDualSetpoints(&:remove)

    #Set simulation start day to be consistent.
    model.yearDescription.get.setDayofWeekforStartDay('Sunday')

    #Set climate data.
    standard.model_add_design_days_and_weather_file(model, @climate_zone, @epw_file) # Standards
    standard.model_add_ground_temperatures(model, nil, @climate_zone) # prototype candidate

    #Add Occ sensor schedule adjustments where needed.
    standard.set_occ_sensor_spacetypes(model)

    #Set Loads/Schedules
    standard.model_add_loads(model)
    #set space_type colors
    model.getSpaceTypes.sort.each { |space_type| space_type.setRenderingColor(standard.set_random_rendering_color(space_type)) }

    #Add Infiltration
    standard.model_apply_infiltration_standard(model)

    #Modify_surface_convection_algorithm
    model.getInsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')
    model.getOutsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')

    #Add default constructions
    standard.model_add_constructions(model)
    standard.apply_standard_construction_properties(model)
    standard.auto_zoning(model)
    system_fuel_defaults = standard.get_canadian_system_defaults_by_weatherfile_name(model)
    standard.auto_system(model: model,
                         boiler_fueltype: system_fuel_defaults['boiler_fueltype'],
                         baseboard_type: system_fuel_defaults['baseboard_type'],
                         mau_type: system_fuel_defaults['mau_type'],
                         mau_heating_coil_type: system_fuel_defaults['mau_heating_coil_type'],
                         mau_cooling_type: system_fuel_defaults['mau_cooling_type'],
                         chiller_type: system_fuel_defaults['chiller_type'],
                         heating_coil_type_sys3: system_fuel_defaults['heating_coil_type_sys3'],
                         heating_coil_type_sys4: system_fuel_defaults['heating_coil_type_sys4'],
                         heating_coil_type_sys6: system_fuel_defaults['heating_coil_type_sys6']
    )

    #writing file

    puts "Writing Output #{outfile}"
    BTAP::FileIO::save_osm(model, outfile)


    air_loops = []
    model.getAirLoopHVACs.each do |airloop|
      debug = {}
      debug[:airloop_name] = airloop.name.to_s
      debug[:control_zone] = standard.determine_control_zone(airloop.thermalZones).name.to_s
      debug[:thermal_zones] = []
      airloop.thermalZones.sort.each do |tz|
        zone_data = {}
        zone_data[:name] = tz.name.to_s
        zone_data[:heating_load_per_area] = standard.stored_zone_heating_load(tz)
        zone_data[:cooling_load_per_area] = standard.stored_zone_cooling_load(tz)
        zone_data[:spaces] = []
        tz.spaces.sort.each do |space|
          space_data = {}
          space_data[:name] = space.name.get.to_s
          space_data[:space_type] = space.spaceType.get.standardsBuildingType.get.to_s + '-' + space.spaceType.get.standardsSpaceType.get.to_s
          space_data[:schedule] = standard.determine_necb_schedule_type(space).to_s
          space_data[:heating_load_per_area] = standard.stored_space_heating_load(space)
          space_data[:cooling_load_per_area] = standard.stored_space_cooling_load(space)
          space_data[:surface_report] = standard.space_surface_report(space)
          zone_data[:spaces] << space_data
        end
        zone_data[:spaces].sort! { |a, b| [a[:name]] <=> [b[:name]] }
        debug[:thermal_zones] << zone_data
      end
      debug[:thermal_zones].sort! { |a, b| [a[:thermal_zone_name]] <=> [b[:thermal_zone_name]] }
      air_loops << debug
    end
    outfile_json = @output_folder + "/#{filename}_autozoned.json"
    puts "Writing Output #{outfile_json}"
    air_loops.sort! { |a, b| [a[:airloop_name]] <=> [b[:airloop_name]] }
    File.write(outfile_json, JSON.pretty_generate(air_loops))
  end
end
