class NECB2011
  # This method will take a model that uses NECB2011 spacetypes , and..
  # 1. Create a building story schema.
  # 2. Remove all existing Thermal Zone defintions.
  # 3. Create new thermal zones based on the following definitions.
  # Rule1 all zones must contain only the same schedule / occupancy schedule.
  # Rule2 zones must cater to similar solar gains (N,E,S,W)
  # Rule3 zones must not pass from floor to floor. They must be contained to a single floor or level.
  # Rule4 Wildcard spaces will be associated with the nearest zone of similar schedule type in which is shared most of it's internal surface with.
  # Rule5 For NECB zones must contain spaces of similar system type only.
  # Rule6 Residential / dwelling units must not share systems with other space types.
  # @author phylroy.lopez@nrcan.gc.ca
  # @param model [OpenStudio::model::Model] A model object
  # @return [String] system_zone_array

  def necb_autozone_and_autosystem(model: nil, runner: nil, use_ideal_air_loads: false, system_fuel_defaults:)
    # Create a data struct for the space to system to placement information.

    # system assignment.
    unless ['NaturalGas', 'Electricity', 'PropaneGas', 'FuelOil#1', 'FuelOil#2', 'Coal', 'Diesel', 'Gasoline', 'OtherFuel1'].include?(system_fuel_defaults['boiler_fueltype'])
      BTAP.runner_register('ERROR', "boiler_fueltype = #{system_fuel_defaults['boiler_fueltype']}", runner)
      return false
    end

    unless [true, false].include?(system_fuel_defaults['mau_type'])
      BTAP.runner_register('ERROR', "mau_type = #{system_fuel_defaults['mau_type']}", runner)
      return false
    end

    unless ['Hot Water', 'Electric'].include?(system_fuel_defaults['mau_heating_coil_type'])
      BTAP.runner_register('ERROR', "mau_heating_coil_type = #{system_fuel_defaults['mau_heating_coil_type']}", runner)
      return false
    end

    unless ['Hot Water', 'Electric'].include?(system_fuel_defaults['baseboard_type'])
      BTAP.runner_register('ERROR', "baseboard_type = #{system_fuel_defaults['baseboard_type']}", runner)
      return false
    end

    unless ['Scroll', 'Centrifugal', 'Rotary Screw', 'Reciprocating'].include?(system_fuel_defaults['chiller_type'])
      BTAP.runner_register('ERROR', "chiller_type = #{system_fuel_defaults['chiller_type']}", runner)
      return false
    end
    unless ['DX', 'Hydronic'].include?(system_fuel_defaults['mau_cooling_type'])
      BTAP.runner_register('ERROR', "mau_cooling_type = #{system_fuel_defaults['mau_cooling_type']}", runner)
      return false
    end

    unless ['Electric', 'Gas', 'DX'].include?(system_fuel_defaults['heating_coil_type_sys3'])
      BTAP.runner_register('ERROR', "heating_coil_type_sys3 = #{system_fuel_defaults['heating_coil_type_sys3']}", runner)
      return false
    end

    unless ['Electric', 'Gas', 'DX'].include?(system_fuel_defaults['heating_coil_type_sys4'])
      BTAP.runner_register('ERROR', "heating_coil_type_sys4 = #{system_fuel_defaults['heating_coil_type_sys4']}", runner)
      return false
    end

    unless ['Hot Water', 'Electric'].include?(system_fuel_defaults['heating_coil_type_sys6'])
      BTAP.runner_register('ERROR', "heating_coil_type_sys6 = #{system_fuel_defaults['heating_coil_type_sys6']}", runner)
      return false
    end

    unless ['AF_or_BI_rdg_fancurve', 'AF_or_BI_inletvanes', 'fc_inletvanes', 'var_speed_drive'].include?(system_fuel_defaults['fan_type'])
      BTAP.runner_register('ERROR', "fan_type = #{system_fuel_defaults['fan_type']}", runner)
      return false
    end
    # REPEATED CODE!!
    unless ['Electric', 'Hot Water'].include?(system_fuel_defaults['heating_coil_type_sys6'])
      BTAP.runner_register('ERROR', "heating_coil_type_sys6 = #{system_fuel_defaults['heating_coil_type_sys6']}", runner)
      return false
    end
    # REPEATED CODE!!
    unless ['Electric', 'Gas'].include?(system_fuel_defaults['heating_coil_type_sys4'])
      BTAP.runner_register('ERROR', "heating_coil_type_sys4 = #{system_fuel_defaults['heating_coil_type_sys4']}", runner)
      return false
    end

    unique_schedule_types = [] # Array to store schedule objects
    space_zoning_data_array_json = []

    # First pass of spaces to collect information into the space_zoning_data_array .
    model.getSpaces.sort.each do |space|
      space_type_data = nil
      # this will get the spacetype system index 8.4.4.8A  from the SpaceTypeData and BuildingTypeData in  (1-12)
      space_system_index = nil
      unless space.spaceType.empty?
        # gets row information from standards spreadsheet.
        space_type_data = standards_lookup_table_first(table_name: 'space_types', search_criteria: {'template' => self.class.name,
                                                                                                    'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                                                                    'building_type' => space.spaceType.get.standardsBuildingType.get})
        raise("Could not find spacetype information in #{self.class.name} for space_type => #{space.spaceType.get.standardsSpaceType.get} - #{space.spaceType.get.standardsBuildingType.get}") if space_type_data.nil?
      end

      #Get Heating and cooling loads
      cooling_design_load = space.spaceType.get.standardsSpaceType.get == '- undefined -' ? 0.0 : space.thermalZone.get.coolingDesignLoad.get * space.floorArea * space.multiplier / 1000.0
      heating_design_load = space.spaceType.get.standardsSpaceType.get == '- undefined -' ? 0.0 : space.thermalZone.get.heatingDesignLoad.get * space.floorArea * space.multiplier / 1000.0


      # identify space-system_index and assign the right NECB system type 1-7.
      necb_hvac_system_selection_table = standards_lookup_table_many(table_name: 'necb_hvac_system_selection_type')
      necb_hvac_system_select = necb_hvac_system_selection_table.detect do |necb_hvac_system_select|
        necb_hvac_system_select['necb_hvac_system_selection_type'] == space_type_data['necb_hvac_system_selection_type'] &&
            necb_hvac_system_select['min_stories'] <= model.getBuilding.standardsNumberOfAboveGroundStories.get &&
            necb_hvac_system_select['max_stories'] >= model.getBuilding.standardsNumberOfAboveGroundStories.get &&
            necb_hvac_system_select['min_cooling_capacity_kw'] <= cooling_design_load &&
            necb_hvac_system_select['max_cooling_capacity_kw'] >= cooling_design_load
      end

      #======

      horizontal_placement = nil
      vertical_placement = nil
      json_data = nil

      #get all exterior surfaces.
      surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces,
                                                                        ["Outdoors",
                                                                         "Ground",
                                                                         "GroundFCfactorMethod",
                                                                         "GroundSlabPreprocessorAverage",
                                                                         "GroundSlabPreprocessorCore",
                                                                         "GroundSlabPreprocessorPerimeter",
                                                                         "GroundBasementPreprocessorAverageWall",
                                                                         "GroundBasementPreprocessorAverageFloor",
                                                                         "GroundBasementPreprocessorUpperWall",
                                                                         "GroundBasementPreprocessorLowerWall"])

      #exterior Surfaces
      ext_wall_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, ["Wall"])
      ext_bottom_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, ["Floor"])
      ext_top_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(surfaces, ["RoofCeiling"])

      #Interior Surfaces..if needed....
      internal_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(space.surfaces, ["Surface"])
      int_wall_surfaces = BTAP::Geometry::Surfaces::filter_by_surface_types(internal_surfaces, ["Wall"])
      int_bottom_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(internal_surfaces, ["Floor"])
      int_top_surface = BTAP::Geometry::Surfaces::filter_by_surface_types(internal_surfaces, ["RoofCeiling"])


      vertical_placement = "NA"
      #determine if space is a top or bottom, both or middle space.
      if ext_bottom_surface.size > 0 and ext_top_surface.size > 0 and int_bottom_surface.size == 0 and int_top_surface.size == 0
        vertical_placement = "single_story_space"
      elsif int_bottom_surface.size > 0 and ext_top_surface.size > 0 and int_bottom_surface.size > 0
        vertical_placement = "top"
      elsif ext_bottom_surface.size > 0 and ext_top_surface.size == 0
        vertical_placement = "bottom"
      elsif ext_bottom_surface.size == 0 and ext_top_surface.size == 0
        vertical_placement = "middle"
      end


      #determine if what cardinal direction has the majority of external
      #surface area of the space.
      #set this to 'core' by default and change it if it is found to be a space exposed to a cardinal direction.
      horizontal_placement = nil
      #set up summing hashes for each direction.
      json_data = Hash.new
      walls_area_array = Hash.new
      subsurface_area_array = Hash.new
      boundary_conditions = {}
      boundary_conditions[:outdoors] = ["Outdoors"]
      boundary_conditions[:ground] = [
          "Ground",
          "GroundFCfactorMethod",
          "GroundSlabPreprocessorAverage",
          "GroundSlabPreprocessorCore",
          "GroundSlabPreprocessorPerimeter",
          "GroundBasementPreprocessorAverageWall",
          "GroundBasementPreprocessorAverageFloor",
          "GroundBasementPreprocessorUpperWall",
          "GroundBasementPreprocessorLowerWall"]
      #go through all directions.. need to do north twice since that goes around zero degree mark.
      orientations = [
          {:surface_type => 'Wall', :direction => 'north', :azimuth_from => 0.00, :azimuth_to => 45.0, :tilt_from => 0.0, :tilt_to => 180.0},
          {:surface_type => 'Wall', :direction => 'north', :azimuth_from => 315.001, :azimuth_to => 360.0, :tilt_from => 0.0, :tilt_to => 180.0},
          {:surface_type => 'Wall', :direction => 'east', :azimuth_from => 45.001, :azimuth_to => 135.0, :tilt_from => 0.0, :tilt_to => 180.0},
          {:surface_type => 'Wall', :direction => 'south', :azimuth_from => 135.001, :azimuth_to => 225.0, :tilt_from => 0.0, :tilt_to => 180.0},
          {:surface_type => 'Wall', :direction => 'west', :azimuth_from => 225.001, :azimuth_to => 315.0, :tilt_from => 0.0, :tilt_to => 180.0},
          {:surface_type => 'RoofCeiling', :direction => 'top', :azimuth_from => 0.0, :azimuth_to => 360.0, :tilt_from => 0.0, :tilt_to => 180.0},
          {:surface_type => 'Floor', :direction => 'bottom', :azimuth_from => 0.0, :azimuth_to => 360.0, :tilt_from => 0.0, :tilt_to => 180.0}
      ]
      [:outdoors, :ground].each do |bc|
        orientations.each do |orientation|
          walls_area_array[orientation[:direction]] = 0.0
          subsurface_area_array[orientation[:direction]] = 0.0
          json_data[:surface_data] = []
        end
      end


      [:outdoors, :ground].each do |bc|
        orientations.each do |orientation|
          surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(space.surfaces, boundary_conditions[bc])
          selected_surfaces = BTAP::Geometry::Surfaces.filter_by_surface_types(surfaces, [orientation[:surface_type]])
          BTAP::Geometry::Surfaces::filter_by_azimuth_and_tilt(selected_surfaces, orientation[:azimuth_from], orientation[:azimuth_to], orientation[:tilt_from], orientation[:tilt_to]).each do |surface|
            #sum wall area and subsurface area by direction. This is the old way so excluding top and bottom surfaces.
            walls_area_array[orientation[:direction]] += surface.grossArea unless ['RoofCeiling', 'Floor'].include?(orientation[:surface_type])
            #new way
            glazings = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(surface.subSurfaces, ["FixedWindow", "OperableWindow", "GlassDoor", "Skylight", "TubularDaylightDiffuser", "TubularDaylightDome"])
            doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(surface.subSurfaces, ["Door", "OverheadDoor"])
            azimuth = (surface.azimuth() * 180.0 / Math::PI).to_i
            tilt = (surface.tilt() * 180.0 / Math::PI).to_i
            surface_data = json_data[:surface_data].detect {|surface_data| surface_data[:surface_type] == surface.surfaceType && surface.surfaceType && surface_data[:azimuth] == azimuth && surface_data[:tilt] == tilt && surface_data[:boundary_condition] == bc}
            if surface_data.nil?
              surface_data = {surface_type: surface.surfaceType, azimuth: azimuth, tilt: tilt, boundary_condition: bc, surface_area: 0.0, glazed_subsurface_area: 0.0, opaque_subsurface_area: 0.0}
              json_data[:surface_data] << surface_data
            end
            surface_data[:surface_area] += surface.grossArea.to_i
            surface_data[:glazed_subsurface_area] += glazings.map {|subsurface| subsurface.grossArea}.inject(0) {|sum, x| sum + x}.to_i
            surface_data[:surface_area] += doors.map {|subsurface| subsurface.grossArea}.inject(0) {|sum, x| sum + x}.to_i
          end
        end
      end

      horizontal_placement = nil
      wall_surface_data = json_data[:surface_data].select {|surface| surface[:surface_type] == "Wall"}
      if wall_surface_data.empty?
        horizontal_placement = 'core' #should change to attic.
      else
        max_area_azimuth = wall_surface_data.max_by {|k| k[:surface_area]}[:azimuth]

        #if no surfaces ext or ground.. then set the space as a core space.
        if json_data[:surface_data].inject(0) {|sum, hash| sum + hash[:surface_area]} == 0.0
          horizontal_placement = 'core'
        elsif (max_area_azimuth >= 0.0 && max_area_azimuth <= 45.00) || (max_area_azimuth >= 315.01 && max_area_azimuth <= 360.00)
          horizontal_placement = 'north'
        elsif (max_area_azimuth >= 45.01 && max_area_azimuth <= 135.00)
          horizontal_placement = 'east'
        elsif (max_area_azimuth >= 135.01 && max_area_azimuth <= 225.00)
          horizontal_placement = 'south'
        elsif (max_area_azimuth >= 225.01 && max_area_azimuth <= 315.00)
          horizontal_placement = 'west'
        end
      end

      # dump all info into an array for debugging and iteration.
      unless space.spaceType.empty?
        space_zoning_data_array_json << {
            space: space,
            space_name: space.name,
            floor_area: space.floorArea.to_i,
            horizontal_placement: horizontal_placement,
            vertical_placement: vertical_placement,
            building_type_name: space.spaceType.get.standardsBuildingType.get, # space type name
            space_type_name: space.spaceType.get.standardsSpaceType.get, # space type name
            short_space_type_name: "#{space.spaceType.get.standardsBuildingType.get}-#{space.spaceType.get.standardsSpaceType.get}",
            necb_hvac_system_selection_type: space_type_data['necb_hvac_system_selection_type'], #
            system_number: necb_hvac_system_select['system_type'].nil? ? nil : necb_hvac_system_select['system_type'], # the necb system type
            number_of_stories: model.getBuilding.standardsNumberOfAboveGroundStories.get, # number of stories
            heating_design_load: heating_design_load,
            cooling_design_load: cooling_design_load,
            is_dwelling_unit: necb_hvac_system_select['dwelling'], # Checks if it is a dwelling unit.
            is_wildcard: necb_hvac_system_select['necb_hvac_system_selection_type'] == 'Wildcard' ? true : nil,
            schedule_type: determine_necb_schedule_type(space).to_s,
            multiplier: (@space_multiplier_map[space.name.to_s].nil? ? 1 : @space_multiplier_map[space.name.to_s]),
            surface_data: json_data[:surface_data]
        }
      end
    end
    File.write("#{File.dirname(__FILE__)}/newway.json", JSON.pretty_generate(space_zoning_data_array_json))
    # reduce the number of zones by first finding spaces with similar load profiles.. That means
    # 1. same space_type
    # 2. same envelope exposure
    # 3. same schedule (should be the same as #2)

    # Get all the spacetypes used in the spaces.
    dwelling_group_index = 0
    wildcard_group_index = 0
    regular_group_index = 0
    #Thermal Zone iterator
    unique_spacetypes = space_zoning_data_array_json.map {|space_info| space_info[:short_space_type_name]}.uniq()
    unique_spacetypes.each do |unique_spacetype|
      spaces_of_a_spacetype = space_zoning_data_array_json.select {|space_info| space_info[:short_space_type_name] == unique_spacetype}
      spaces_of_a_spacetype.each do |space_info|
        # Find spacetypes that have similar envelop loads in the same.
        # find all spaces with same envelope loads.
        spaces_of_a_spacetype.each do |space_info_2|
          does_space_have_similar_envelope_load = true
          if space_info[:surface_data].size == space_info_2[:surface_data].size
            space_info[:surface_data].each do |surface_info|
              does_space_have_similar_envelope_load = false unless space_info_2[:surface_data].include?(surface_info)
            end
          else
            does_space_have_similar_envelope_load = false
          end
          if does_space_have_similar_envelope_load
            #If there are similar spaces.. they should be placed into the same Thermal zone.
          end
        end
      end
    end


    # Deal with Wildcard spaces. Might wish to have logic to do coridors first.
    space_zoning_data_array_json.each do |space_zone_data|
      # If it is a wildcard space.
      if space_zone_data[:system_number].nil?
        # iterate through all adjacent spaces from largest shared wall area to smallest.
        # Set system type to match first space system that is not nil.
        adj_spaces = space_get_adjacent_spaces_with_shared_wall_areas(space_zone_data[:space], true)
        if adj_spaces.nil?
          puts "Warning: No adjacent spaces for #{space_zone_data[:space].name} on same floor, looking for others above and below to set system"
          adj_spaces = space_get_adjacent_spaces_with_shared_wall_areas(space_zone_data[:space], false)
        end
        adj_spaces.sort.each do |adj_space|
          # if there are no adjacent spaces. Raise an error.
          raise "Could not determine adj space to space #{space_zone_data[:space].name.get}" if adj_space.nil?

          adj_space_data = space_zoning_data_array_json.find {|data| data[:space] == adj_space[0]}
          if adj_space_data[:system_number].nil?
            next
          else
            space_zone_data[:system_number] = adj_space_data[:system_number]
            break
          end
        end
        raise "Could not determine adj space system to space #{space_zone_data.space.name.get}" if space_zone_data[:system_number].nil?
      end
    end

    # remove any thermal zones used for sizing to start fresh. Should only do this after the above system selection method.
    model.getThermalZones.sort.each(&:remove)

    # now lets apply the rules.
    # Rule1 all zones must contain only the same schedule / occupancy schedule.
    # Rule2 zones must cater to similar solar gains (N,E,S,W)
    # Rule3 zones must not pass from floor to floor. They must be contained to a single floor or level.
    # Rule4 Wildcard spaces will be associated with the nearest zone of similar schedule type in which is shared most of it's internal surface with.
    # Rule5 NECB zones must contain spaces of similar system type only.
    # Rule6 Multiplier zone will be part of the floor and orientation of the base space.
    # Rule7 Residential / dwelling units must not share systems with other space types.
    # Array of system types of Array of Spaces
    system_zone_array = []
    # Lets iterate by system
    (0..7).each do |system_number|
      system_zone_array[system_number] = []
      # iterate by story
      model.getBuildingStorys.sort.each_with_index do |story, building_index|
        # iterate by unique schedule type.
        space_zoning_data_array_json.map {|item| item[:schedule_type]}.uniq!.each do |schedule_type|
          # iterate by horizontal location
          ['north', 'east', 'west', 'south', 'core'].each do |horizontal_placement|
            # puts "horizontal_placement:#{horizontal_placement}"
            [true, false].each do |is_dwelling_unit|
              space_info_array = []
              space_zoning_data_array_json.each do |space_info|
                # puts "Spacename: #{space_info.space.name}:#{space_info.space.spaceType.get.name}"
                if (space_info[:system_number] == system_number) &&
                    (space_info[:space].buildingStory.get == story) &&
                    (determine_necb_schedule_type(space_info[:space]).to_s == schedule_type) &&
                    (space_info[:horizontal_placement] == horizontal_placement) &&
                    (space_info[:is_dwelling_unit] == is_dwelling_unit)
                  space_info_array << space_info
                end
              end

              # create Thermal Zone if space_array is not empty.
              unless space_info_array.empty?
                # Process spaces that have multipliers associated with them first.
                # This map define the multipliers for spaces with multipliers not equals to 1
                space_multiplier_map = @space_multiplier_map

                # create new zone and add the spaces to it.
                space_info_array.each do |space_info|
                  # Create thermalzone for each space.
                  thermal_zone = OpenStudio::Model::ThermalZone.new(model)
                  thermal_zone.setRenderingColor(self.set_random_rendering_color(thermal_zone))

                  # Create a more informative space name.
                  thermal_zone.setName("Sp-#{space_info[:space].name} Sys-#{system_number} Flr-#{building_index + 1} Sch-#{schedule_type} HPlcmt-#{horizontal_placement} ZN")
                  # Add zone mulitplier if required.
                  thermal_zone.setMultiplier(space_info[:multiplier]) unless space_info[:multiplier] == 1
                  # Space to thermal zone. (for archetype work it is one to one)
                  space_info[:space].setThermalZone(thermal_zone)
                  # Get thermostat for space type if it already exists.
                  space_type_name = space_info[:space].spaceType.get.name.get
                  thermostat_name = space_type_name + ' Thermostat'
                  thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
                  if thermostat.empty?
                    OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space_info[:space].name} ZN")
                    raise " Thermostat #{thermostat_name} not found for space name: #{space_info[:space].name}"
                  else
                    thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
                    thermal_zone.setThermostatSetpointDualSetpoint(thermostat_clone)
                  end
                  # Add thermal to zone system number.
                  system_zone_array[system_number] << thermal_zone
                end
              end
            end
          end
        end
      end
    end
    # system iteration

    # Create and assign the zones to the systems.
    if use_ideal_air_loads == true
      # otherwise use ideal loads.
      model.getThermalZones.sort.each do |thermal_zone|
        thermal_zone_ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        thermal_zone_ideal_loads.addToThermalZone(thermal_zone)
      end
    else
      hw_loop_needed = false
      system_zone_array.each_with_index do |zones, system_index|
        next if zones.empty?

        if system_index == 1 && (system_fuel_defaults['mau_heating_coil_type'] == 'Hot Water' || system_fuel_defaults['baseboard_type'] == 'Hot Water')
          hw_loop_needed = true
        elsif system_index == 2 || system_index == 5 || system_index == 7
          hw_loop_needed = true
        elsif (system_index == 3 || system_index == 4) && system_fuel_defaults['baseboard_type'] == 'Hot Water'
          hw_loop_needed = true
        elsif system_index == 6 && (system_fuel_defaults['mau_heating_coil_type'] == 'Hot Water' || system_fuel_defaults['baseboard_type'] == 'Hot Water')
          hw_loop_needed = true
        end
        if hw_loop_needed
          break
        end
      end
      if hw_loop_needed
        hw_loop = OpenStudio::Model::PlantLoop.new(model)
        always_on = model.alwaysOnDiscreteSchedule
        setup_hw_loop_with_components(model, hw_loop, system_fuel_defaults['boiler_fueltype'], always_on)
      end
      system_zone_array.each_with_index do |zones, system_index|
        # skip if no thermal zones for this system.
        next if zones.empty?

        case system_index
        when 0, nil
          # Do nothing no system assigned to zone. Used for Unconditioned spaces
        when 1
          add_sys1_unitary_ac_baseboard_heating(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['mau_type'], system_fuel_defaults['mau_heating_coil_type'], system_fuel_defaults['baseboard_type'], hw_loop)
        when 2
          add_sys2_FPFC_sys5_TPFC(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['chiller_type'], 'FPFC', system_fuel_defaults['mau_cooling_type'], hw_loop)
        when 3
          add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['heating_coil_type_sys3'], system_fuel_defaults['baseboard_type'], hw_loop)
        when 4
          add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['heating_coil_type_sys4'], system_fuel_defaults['baseboard_type'], hw_loop)
        when 5
          add_sys2_FPFC_sys5_TPFC(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['chiller_type'], 'TPFC', system_fuel_defaults['mau_cooling_type'], hw_loop)
        when 6
          add_sys6_multi_zone_built_up_system_with_baseboard_heating(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['heating_coil_type_sys6'], system_fuel_defaults['baseboard_type'], system_fuel_defaults['chiller_type'], system_fuel_defaults['fan_type'], hw_loop)
        when 7
          add_sys2_FPFC_sys5_TPFC(model, zones, system_fuel_defaults['boiler_fueltype'], system_fuel_defaults['chiller_type'], 'FPFC', system_fuel_defaults['mau_cooling_type'], hw_loop)
        end
      end
    end
    # Check to ensure that all spaces are assigned to zones except undefined ones.
    errors = []
    model.getSpaces.sort.each do |space|
      if space.thermalZone.empty? && (space.spaceType.get.name.get != 'Space Function - undefined -')
        errors << "space #{space.name} with spacetype #{space.spaceType.get.name.get} was not assigned a thermalzone."
      end
    end
    raise(" #{errors}") unless errors.empty?
  end

  # Creates thermal zones to contain each space, as defined for each building in the
  # system_to_space_map inside the Prototype.building_name
  # e.g. (Prototype.secondary_school.rb) file.
  #
  # @param (see #add_constructions)
  # @return [Bool] returns true if successful, false if not
  def model_create_thermal_zones(model, space_multiplier_map = nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started creating thermal zones')
    space_multiplier_map = {} if space_multiplier_map.nil?

    # Remove any Thermal zones assigned
    model.getThermalZones.each(&:remove)

    # Create a thermal zone for each space in the self
    model.getSpaces.sort.each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      zone.setName("#{space.name} ZN")
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      space.setThermalZone(zone)

      # Skip thermostat for spaces with no space type
      next if space.spaceType.empty?

      # Add a thermostat
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished creating thermal zones')
  end


  def auto_zoning(model)
    #The first thing we need to do is get a sizing run to determine the heating loads of all the spaces. The default
    # btap geometry has a one to one relationship of zones to spaces.. So we simply create the thermal zones for all the spaces.
    # to do this we need to create thermals zone for each space.
    # Remove any Thermal zones assigned before
    model.getThermalZones.each(&:remove)
    # create new thermal zones one to one with spaces.
    model_create_thermal_zones(model)
    # do a sizing run.
    raise("autorun sizing run failed!") if model_run_sizing_run(model, "#{Dir.pwd}/autozone") == false

    #store sizing loads for each space into a class hash.
    @space_heating_load = {}
    @space_cooling_load = {}
    model.getSpaces.each do |space|
      @space_heating_load[space] = space.spaceType.get.standardsSpaceType.get == '- undefined -' ? 0.0 : space.thermalZone.get.heatingDesignLoad.get * space.floorArea * space.multiplier / 1000.0
      @space_cooling_load[space] = space.spaceType.get.standardsSpaceType.get == '- undefined -' ? 0.0 : space.thermalZone.get.coolingDesignLoad.get * space.floorArea * space.multiplier / 1000.0
    end

    # Remove any Thermal zones assigned again to start fresh.
    model.getThermalZones.each(&:remove)

    #create zones for dwelling units.
    dwelling_tz_array = self.auto_zone_dwelling_units(model)
    #wet zone creation.
    wet_zone_array = self.auto_zone_wet_spaces(model)

    self.auto_zone_all_other_spaces(model)
    self.auto_zone_wild_spaces(model)
  end


  def auto_system(model)
    #ensure each dwelling unit has its own system.
    auto_system_dwelling_units(model)
    #Assign a single system 4 for all wet spaces.. and assign the control zone to the one with the largest load.
    auto_system_wet_spaces(model)
    #Assign the wild spaces to a single system 4 system with a control zone with the largest load.
    auto_system_wild_spaces(model)
    # do the regular assignment for the rest and group where possible.
    auto_system_all_other_spaces(model)
  end


  def auto_system_dwelling_units
    #dwelling units are either system 1 or 3.
    dwellling_tz = []
    model.getSpaces.select {|space| is_a_necb_dwelling_unit?(space)}.each do |space|
      dwellling_tz << space.thermalZone.get
    end
    dwellling_tz.uniq!.each do |tz|
      #check what system type to assign.

    end

  end


  # Dwelling unit spaces need to have their own HVAC system. Thankfully NECB defines what spacetypes are considering
  # dwelling units and have been defined as spaces that are
  # openstudio-standards/standards/necb/NECB2011/data/necb_hvac_system_selection_type.json as spaces that are Residential/Accomodation and Sleeping area'
  # this is determine by the is_a_necb_dwelling_unit? method. The thermostat is set by the space-type schedule. This will return an array of TZ.
  def auto_zone_dwelling_units(model)
    dwelling_tz_array = []
    # ----Dwelling units----------- will always have their own system per unit, so they should have their own thermal zone.
    model.getSpaces.select {|space| is_a_necb_dwelling_unit?(space)}.each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      zone.setName("DU-ZN:BT=#{space.spaceType.get.standardsBuildingType.get}:ST=#{space.spaceType.get.standardsSpaceType.get}:FL=#{space.buildingStory().get.name}:")
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      space.setThermalZone(zone)

      # Add a thermostat based on the space type.
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model).addToThermalZone(zone)
      end
      dwelling_tz_array << zone
    end
    return dwelling_tz_array
  end

  # Something that the code is silent on are smelly humid areas that should not be on the same system as the rest of the
  #  building.. These are the 'wet' spaces and have been defined as locker and washroom areas.. These will be put under
  # their own single system 4 system. These will be set to the dominant floor schedule.
  def auto_zone_wet_spaces(model)
    wet_zone_array = Array.new
    model.getSpaces.select {|space| is_an_necb_wet_space?(space)}.each do |space|
      #if this space was already assigned to something skip it.
      next unless space.thermalZone.empty?
      #create new TZ and set space to the zone.
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      space.setThermalZone(zone)
      zone.setName("WET-ZN:BT=#{space.spaceType.get.standardsBuildingType.get}:ST=#{space.spaceType.get.standardsSpaceType.get}:FL=#{space.buildingStory().get.name}:")
      #Set multiplier from the original tz multiplier.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end

      # Set space to dominant
      dominant_floor_schedule = determine_dominant_schedule(space.buildingStory().get.spaces)
      #this method will determine if the right schedule was used for this wet & wild space if not.. it will reset the space
      # to use the correct schedule version of the wet and wild space type.
      adjust_wildcard_spacetype_schedule(space, dominant_floor_schedule)
      #Find spacetype thermostat and assign it to the zone.
      thermostat_name = space.spaceType.get.name.get + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}-")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      # Go through other spaces to see if there are similar spaces with similar loads on the same floor that can be grouped.
      model.getSpaces.select {|s| is_an_necb_wet_space?(s)}.each do |space_target|
        if space_target.thermalZone.empty?
          if are_space_loads_similar?(space_1: space, space_2: space_target) &&
              space.buildingStory().get == space_target.buildingStory().get # added since chris needs zones to not span floors for costing.
            adjust_wildcard_spacetype_schedule(space_target, dominant_floor_schedule)
            space_target.setThermalZone(zone)
          end
        end
      end
      wet_zone_array << zone
    end
    return wet_zone_array
  end

  def auto_zone_all_other_spaces(model)
    other_tz_array = Array.new
    #iterate through all non wildcard spaces.
    model.getSpaces.select {|space| not is_a_necb_dwelling_unit?(space) and not is_an_necb_wildcard_space?(space)}.each do |space|
      #skip if already assigned to a thermal zone.
      next unless space.thermalZone.empty?
      #create new zone for this space based on the space name.
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      tz_name = "All-ZN:BT=#{space.spaceType.get.standardsBuildingType.get}:ST=#{space.spaceType.get.standardsSpaceType.get}:FL=#{space.buildingStory().get.name}:"
      zone.setName(tz_name)
      #sets space mulitplier unless it is nil or 1.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      #Assign space to the new zone.
      space.setThermalZone(zone)

      # Add a thermostat
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      # Go through other spaces and if you find something with similar loads on the same floor, add it to the zone.
      model.getSpaces.select {|space| not is_a_necb_dwelling_unit?(space) and not is_an_necb_wildcard_space?(space)}.each do |space_target|
        if space_target.thermalZone.empty?
          if are_space_loads_similar?(space_1: space, space_2: space_target) and
              space.buildingStory().get == space_target.buildingStory().get # added since chris needs zones to not span floors for costing.
            space_target.setThermalZone(zone)
          end
        end
      end
      other_tz_array << zone
    end
    return other_tz_array
  end

  def auto_zone_wild_spaces(model)
    wild_zone_array = Array.new
    model.getSpaces.select {|space| is_an_necb_wildcard_space?(space) and not is_an_necb_wet_space?(space)}.each do |space|
      #if this space was already assigned to something skip it.
      next unless space.thermalZone.empty?
      #find adjacent spaces to the current space.
      adj_spaces = space_get_adjacent_spaces_with_shared_wall_areas(space, true)
      adj_spaces = adj_spaces.map {|key, value| key}
      # find unassigned adjacent wild spaces that have not been assigned that have the same multiplier these will be
      # lumped together in the same zone.
      wild_adjacent_spaces = adj_spaces.select {|adj_space|
        is_an_necb_wildcard_space?(adj_space) and
            not is_an_necb_wet_space?(adj_space) and
            adj_space.thermalZone.empty? and
            space_multiplier_map[space.name.to_s] == space_multiplier_map[adj_space.name.to_s]
      }
      #put them all together.
      wild_adjacent_spaces << space

      # Get adjacent candidate foster zones. Must not be a wildcard space and must not be linked to another space incase
      # it is part of a mirrored space.
      other_adjacent_spaces = adj_spaces.select do |adj_space|
        is_an_necb_wildcard_space?(adj_space) == false and
            adj_space.thermalZone.get.spaces.size == 1 and
            space_multiplier_map[space.name.to_s] == space_multiplier_map[adj_space.name.to_s]
      end

      #If there are adjacent spaces that fit the above criteria.
      # We will need to set each space to the dominant floor schedule by setting the spaces spacetypes to that
      # schedule version and eventually set it to a system 4
      unless other_adjacent_spaces.empty?
        #assign the space(s) to the adjacent thermal zone.
        schedule_type = determine_dominant_schedule(space.buildingStory.get.spaces)
        zone = other_adjacent_spaces.first.thermalZone.get
        wild_adjacent_spaces.each do |space|
          adjust_wildcard_spacetype_schedule(space, schedule_type)
          space.setThermalZone(zone)
        end
      end

      #create new TZ and set space to the zone.
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      space.setThermalZone(zone)
      zone.setName("Wild-ZN:BT=#{space.spaceType.get.standardsBuildingType.get}:ST=#{space.spaceType.get.standardsSpaceType.get}:FL=#{space.buildingStory().get.name}:")
      #Set multiplier from the original tz multiplier.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end

      # Set space to dominant

      dominant_floor_schedule = determine_dominant_schedule(space.buildingStory().get.spaces)
      #this method will determine if the right schedule was used for this wet & wild space if not.. it will reset the space
      # to use the correct schedule version of the wet and wild space type.
      adjust_wildcard_spacetype_schedule(space, dominant_floor_schedule)
      #Find spacetype thermostat and assign it to the zone.
      thermostat_name = space.spaceType.get.name.get + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        # The thermostat name for the spacetype should exist.
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
      # Go through other spaces to see if there are similar spaces with similar loads on the same floor that can be grouped.
      model.getSpaces.select {|s| is_an_necb_wildcard_space?(s) and not is_an_necb_wet_space?(s)}.each do |space_target|
        if space_target.thermalZone.empty?
          if are_space_loads_similar?(space_1: space, space_2: space_target) &&
              space.buildingStory().get == space_target.buildingStory().get # added since chris needs zones to not span floors for costing.
            adjust_wildcard_spacetype_schedule(space_target, dominant_floor_schedule)
            space_target.setThermalZone(zone)
          end
        end
      end
      wild_zone_array << zone
    end
    return wild_zone_array
  end

  # This method will try to determine if the spaces have similar loads. This will ensure:
  # 1) Space have the same multiplier.
  # 2) Spaces have space types and that they are the same.
  # 3) That the spaces have the same exposed surfaces area relative to the floor area in the same direction. by a
  # percent difference and angular percent difference.
  def are_space_loads_similar?(space_1:, space_2:, surface_percent_difference_tolerance: 0.0, angular_percent_difference_tolerance: 0.00)
    # Do they have the same space type?
    return false unless space_1.multiplier == space_2.multiplier
    # Ensure that they both have defined spacetypes
    return false if space_1.spaceType.empty?
    return false if space_2.spaceType.empty?
    # ensure that they have the same spacetype.
    return false unless space_1.spaceType.get == space_2.spaceType.get
    # Perform surface comparision. If ranges are within percent_difference_tolerance.. they can be considered the same.
    space_1_floor_area = space_1.floorArea
    space_2_floor_area = space_2.floorArea
    space_1_surface_report = space_surface_report(space_1)
    space_2_surface_report = space_surface_report(space_2)

    space_1_surface_report.each do |space_1_surface|
      surface_match = space_2_surface_report.detect do |space_2_surface|
        space_1_surface[:surface_type] == space_2_surface[:surface_type] &&
            space_1_surface[:boundary_condition] == space_2_surface[:boundary_condition] &&
            self.percentage_difference(space_1_surface[:tilt], space_2_surface[:tilt]) <= angular_percent_difference_tolerance &&
            self.percentage_difference(space_1_surface[:azimuth], space_2_surface[:azimuth]) <= angular_percent_difference_tolerance &&
            self.percentage_difference(space_1_surface[:surface_area_to_floor_ratio],
                                       space_2_surface[:surface_area_to_floor_ratio]) <= surface_percent_difference_tolerance &&
            self.percentage_difference(space_1_surface[:glazed_subsurface_area_to_floor_ratio],
                                       space_2_surface[:glazed_subsurface_area_to_floor_ratio]) <= surface_percent_difference_tolerance &&
            self.percentage_difference(space_1_surface[:opaque_subsurface_area_to_floor_ratio],
                                       space_2_surface[:opaque_subsurface_area_to_floor_ratio]) <= surface_percent_difference_tolerance &&
            self.percentage_difference(@space_heating_load[space_1], @space_heating_load[space_2]) <= 5.0

      end
      return false if surface_match.nil?
    end
    return true
  end

  #This method gathers the surface information for the space to determine if spaces are the same.
  def space_surface_report(space)
    surface_report = []
    space_floor_area = space.floorArea
    ['Outdoors', 'Ground'].each do |bc|
      surfaces = BTAP::Geometry::Surfaces.filter_by_boundary_condition(space.surfaces, [bc]).each do |surface|
        #sum wall area and subsurface area by direction. This is the old way so excluding top and bottom surfaces.
        #new way
        glazings = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(surface.subSurfaces, ["FixedWindow",
                                                                                               "OperableWindow",
                                                                                               "GlassDoor",
                                                                                               "Skylight",
                                                                                               "TubularDaylightDiffuser",
                                                                                               "TubularDaylightDome"])
        doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(surface.subSurfaces, ["Door",
                                                                                            "OverheadDoor"])
        azimuth = (surface.azimuth() * 180.0 / Math::PI)
        tilt = (surface.tilt() * 180.0 / Math::PI)
        surface_data = surface_report.detect do |surface_data|
          surface_data[:surface_type] == surface.surfaceType &&
              surface_data[:azimuth] == azimuth &&
              surface_data[:tilt] == tilt &&
              surface_data[:boundary_condition] == bc
        end

        if surface_data.nil?
          surface_data = {
              surface_type: surface.surfaceType,
              azimuth: azimuth,
              tilt: tilt,
              boundary_condition: bc,
              surface_area: 0,
              surface_area_to_floor_ratio: 0,
              glazed_subsurface_area: 0,
              glazed_subsurface_area_to_floor_ratio: 0,
              opaque_subsurface_area: 0,
              opaque_subsurface_area_to_floor_ratio: 0
          }
          surface_report << surface_data
        end
        surface_data[:surface_area] += surface.grossArea.to_i
        surface_data[:surface_area_to_floor_ratio] += surface.grossArea / space.floorArea

        surface_data[:glazed_subsurface_area] += glazings.map {|subsurface| subsurface.grossArea * subsurface.multiplier}.inject(0) {|sum, x| sum + x}.to_i
        surface_data[:glazed_subsurface_area_to_floor_ratio] += glazings.map {|subsurface| subsurface.grossArea * subsurface.multiplier}.inject(0) {|sum, x| sum + x} / space.floorArea

        surface_data[:surface_area] += doors.map {|subsurface| subsurface.grossArea * subsurface.multiplier}.inject(0) {|sum, x| sum + x}.to_i
        surface_data[:surface_area_to_floor_ratio] += doors.map {|subsurface| subsurface.grossArea * subsurface.multiplier}.inject(0) {|sum, x| sum + x} / space.floorArea
      end
    end
    return surface_report
  end

  def is_an_necb_wildcard_space?(space)
    space_type_data = standards_lookup_table_first(table_name: 'space_types',
                                                   search_criteria: {'template' => self.class.name,
                                                                     'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                                     'building_type' => space.spaceType.get.standardsBuildingType.get})
    return space_type_data["necb_hvac_system_selection_type"] == "Wildcard"
  end

  def is_an_necb_wet_space?(space)
    #Hack! Should replace this with a proper table lookup.
    return space.spaceType.get.standardsSpaceType.get.include?('Locker room') || space.spaceType.get.standardsSpaceType.get.include?('Washroom')
  end

  def is_a_necb_dwelling_unit?(space)
    space_type_data = standards_lookup_table_first(table_name: 'space_types',
                                                   search_criteria: {'template' => self.class.name,
                                                                     'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                                     'building_type' => space.spaceType.get.standardsBuildingType.get})

    necb_hvac_system_selection_table = standards_lookup_table_many(table_name: 'necb_hvac_system_selection_type')
    necb_hvac_system_select = necb_hvac_system_selection_table.detect do |necb_hvac_system_select|
      necb_hvac_system_select['necb_hvac_system_selection_type'] == space_type_data['necb_hvac_system_selection_type'] &&
          necb_hvac_system_select['min_stories'] <= space.model.getBuilding.standardsNumberOfAboveGroundStories.get &&
          necb_hvac_system_select['max_stories'] >= space.model.getBuilding.standardsNumberOfAboveGroundStories.get
    end
    return necb_hvac_system_select['dwelling'] == true
  end

  def get_necb_spacetype_system_selection(space)
    space_type_data = standards_lookup_table_first(table_name: 'space_types', search_criteria: {'template' => self.class.name,
                                                                                                'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                                                                'building_type' => space.spaceType.get.standardsBuildingType.get})

    # identify space-system_index and assign the right NECB system type 1-7.
    necb_hvac_system_selection_table = standards_lookup_table_many(table_name: 'necb_hvac_system_selection_type')
    necb_hvac_system_select = necb_hvac_system_selection_table.detect do |necb_hvac_system_select|
      necb_hvac_system_select['necb_hvac_system_selection_type'] == space_type_data['necb_hvac_system_selection_type'] &&
          necb_hvac_system_select['min_stories'] <= space.model.getBuilding.standardsNumberOfAboveGroundStories.get &&
          necb_hvac_system_select['max_stories'] >= space.model.getBuilding.standardsNumberOfAboveGroundStories.get &&
          necb_hvac_system_select['min_cooling_capacity_kw'] <= @space_cooling_load[space] &&
          necb_hvac_system_select['max_cooling_capacity_kw'] >= @space_cooling_load[space]
    end
    raise("could not find system for given spacetype") if necb_hvac_system_select.nil?
    return necb_hvac_system_select['system_type']
  end

  def get_necb_thermal_zone_system_selection(tz)
    systems = []
    tz.spaces.each do |space|
      systems << get_necb_spacetype_system_selection(space)
    end
    systems.uniq!
    systems.compact!
    raise("This thermal zone spaces require different systems.") if systems.size > 1
    return systems.first
  end


  def percentage_difference(value_1, value_2)
    return 0.0 if value_1 == value_2
    return ((value_1 - value_2).abs / ((value_1 + value_2) / 2) * 100)
  end

  def adjust_wildcard_spacetype_schedule(space, schedule)
    if space.spaceType.empty?
      OpenStudio.logFree(OpenStudio::Error, 'Error: No spacetype assigned for #{space.name.get}. This must be assigned. Aborting.')
    end
    # Get current spacetype name
    space_type_name = space.spaceType.get.name.get
    # Determine new spacetype name.
    regex = /^(.*sch-)(\S)$/
    new_spacetype_name = "#{space_type_name.match(regex).captures.first}#{schedule}"
    new_space_type = nil

    #if the new spacetype does not match the old space type. we gotta update the space with the new spacetype.
    unless space_type_name == new_spacetype_name
      new_spacetype = space.model.getSpaceTypes.detect do |spacetype|
        not spacetype.standardsBuildingType.empty? and #need to do this to prevent an exception.
            spacetype.standardsBuildingType.get == space.spaceType.get.standardsBuildingType.get and
            not spacetype.standardsSpaceType.empty? and #need to do this to prevent an exception.
            spacetype.standardsSpaceType.get == space.spaceType.get.standardsSpaceType.get
      end
      if new_spacetype.nil?
        # Space type is not in model. need to create from scratch.
        new_spacetype = OpenStudio::Model::SpaceType.new(space.model)
        new_spacetype.setStandardsBuildingType(space.spaceType.get.standardsBuildingType.get)
        new_spacetype.setStandardsSpaceType(new_spacetype_name)
        new_spacetype.setName("#{space.spaceType.get.standardsBuildingType.get} #{new_spacetype_name}")
        new_spacetype.setRenderingColor(self.set_random_rendering_color(new_spacetype))
        space_type_apply_internal_loads(new_space_type, true, true, true, true, true, true)
        space_type_apply_internal_load_schedules(new_spacetype, true, true, true, true, true, true, true)

      end
      space.setSpaceType(new_spacetype)
    end
  end


  ############autosystem

  def auto_system(model:,
                  boiler_fueltype: "NaturalGas",
                  baseboard_type: "Hot Water",
                  mau_type: true,
                  mau_heating_coil_type: "Hot Water",
                  mau_cooling_type: "DX",
                  chiller_type: "Scroll",
                  heating_coil_type_sys3: "Gas",
                  heating_coil_type_sys4: "Gas",
                  heating_coil_type_sys6: "Hot Water",
                  fan_type: "var_speed_drive",
                  swh_fueltype: "NaturalGas"
  )

    #remove idealair from zones if any.
    model.getZoneHVACIdealLoadsAirSystems.each(&:remove)
    @hw_loop = create_hw_loop_if_required(baseboard_type,
                                          boiler_fueltype,
                                          mau_heating_coil_type,
                                          model)
    #Rule that all dwelling units have their own zone and system.
    auto_system_dwelling_units(model: model,
                               baseboard_type: baseboard_type,
                               boiler_fueltype: boiler_fueltype,
                               chiller_type: chiller_type,
                               fan_type: fan_type,
                               heating_coil_type_sys3: heating_coil_type_sys3,
                               heating_coil_type_sys4: heating_coil_type_sys4,
                               hw_loop: @hw_loop,
                               heating_coil_type_sys6: heating_coil_type_sys6,
                               mau_cooling_type: mau_cooling_type,
                               mau_heating_coil_type: mau_heating_coil_type,
                               mau_type: mau_type
    )

    #Assign a single system 4 for all wet spaces.. and assign the control zone to the one with the largest load.
    auto_system_wet_spaces(baseboard_type: baseboard_type,
                           boiler_fueltype: boiler_fueltype,
                           heating_coil_type_sys4: heating_coil_type_sys4,
                           model: model)

    #Assign the wild spaces to a single system 4 system with a control zone with the largest load.
    auto_system_wild_spaces(baseboard_type: baseboard_type,
                            boiler_fueltype: boiler_fueltype,
                            heating_coil_type_sys4: heating_coil_type_sys4,
                            model: model)
    # do the regular assignment for the rest and group where possible.
    auto_system_all_other_spaces(model: model,
                                 baseboard_type: baseboard_type,
                                 boiler_fueltype: boiler_fueltype,
                                 chiller_type: chiller_type,
                                 fan_type: fan_type,
                                 heating_coil_type_sys3: heating_coil_type_sys3,
                                 heating_coil_type_sys4: heating_coil_type_sys4,
                                 hw_loop: @hw_loop,
                                 heating_coil_type_sys6: heating_coil_type_sys6,
                                 mau_cooling_type: mau_cooling_type,
                                 mau_heating_coil_type: mau_heating_coil_type,
                                 mau_type: mau_type
    )
  end

  def create_hw_loop_if_required(baseboard_type, boiler_fueltype, mau_heating_coil_type, model)
    #get systems that will be used in the model based on the space types to determine if a hw_loop is required.
    systems_used = []
    model.getSpaces.each do |space|
      systems_used << get_necb_spacetype_system_selection(space)
      systems_used.uniq!
    end

    #See if we need to create a hot water loop based on fueltype and systems used.
    hw_loop_needed = false
    systems_used.each do |system|
      case system.to_s
      when '2', '5', '7'
        hw_loop_needed = true
      when '1', '6'
        if mau_heating_coil_type == 'Hot Water' or baseboard_type == 'Hot Water'
          hw_loop_needed = true
        end
      when '3', '4'
        if mau_heating_coil_type == 'Hot Water' or baseboard_type == 'Hot Water'
          hw_loop_needed = true if (baseboard_type == 'Hot Water')
        end
      end
      if hw_loop_needed
        # just need one true condition to need a boiler.
        break
      end
    end # each
    #create hw_loop as needed.. Assuming one loop per model.
    if hw_loop_needed
      @hw_loop = OpenStudio::Model::PlantLoop.new(model)
      always_on = model.alwaysOnDiscreteSchedule
      setup_hw_loop_with_components(model, @hw_loop, boiler_fueltype, always_on)
    end
    return @hw_loop
  end

  def create_necb_system(baseboard_type:,
                         boiler_fueltype:,
                         chiller_type:,
                         fan_type:,
                         heating_coil_type_sys3:,
                         heating_coil_type_sys4:,
                         heating_coil_type_sys6:,
                         hw_loop:,
                         mau_cooling_type:,
                         mau_heating_coil_type:,
                         mau_type:,
                         model:,
                         zones:)

    # The goal is to minimize the number of system when possible.
    system_zones_hash = {}
    zones.each do |zone|
      system_zones_hash[get_necb_thermal_zone_system_selection(zone)] = [] if system_zones_hash[get_necb_thermal_zone_system_selection(zone)].nil?
      system_zones_hash[get_necb_thermal_zone_system_selection(zone)] << zone
    end

    # go through each system and zones pairs to
    system_zones_hash.each_pair do |system, zones|
      case system
      when 0, nil
        # Do nothing no system assigned to zone. Used for Unconditioned spaces
      when 1
        mau_air_loop = add_sys1_unitary_ac_baseboard_heating(model,
                                                             zones,
                                                             boiler_fueltype,
                                                             mau_type,
                                                             mau_heating_coil_type,
                                                             baseboard_type,
                                                             @hw_loop)

      when 2
        add_sys2_FPFC_sys5_TPFC(model,
                                zones,
                                boiler_fueltype,
                                chiller_type,
                                'FPFC',
                                mau_cooling_type,
                                @hw_loop)
      when 3
        add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model,
                                                                                           zones,
                                                                                           boiler_fueltype,
                                                                                           heating_coil_type_sys3,
                                                                                           baseboard_type,
                                                                                           @hw_loop)
      when 4
        add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model,
                                                                     zones,
                                                                     boiler_fueltype,
                                                                     heating_coil_type_sys4,
                                                                     baseboard_type,
                                                                     @hw_loop)
      when 5
        add_sys2_FPFC_sys5_TPFC(model,
                                zones,
                                boiler_fueltype,
                                chiller_type,
                                'TPFC',
                                mau_cooling_type,
                                @hw_loop)
      when 6
        add_sys6_multi_zone_built_up_system_with_baseboard_heating(model,
                                                                   zones,
                                                                   boiler_fueltype,
                                                                   heating_coil_type_sys6,
                                                                   baseboard_type,
                                                                   chiller_type,
                                                                   fan_type,
                                                                   @hw_loop)
      when 7
        add_sys2_FPFC_sys5_TPFC(model,
                                zones,
                                boiler_fueltype,
                                chiller_type,
                                'FPFC',
                                mau_cooling_type,
                                @hw_loop)
      end
    end
  end


  def auto_system_all_other_spaces(baseboard_type:,
                                   boiler_fueltype:,
                                   chiller_type:,
                                   fan_type:,
                                   heating_coil_type_sys3:,
                                   heating_coil_type_sys4:,
                                   heating_coil_type_sys6:,
                                   hw_loop:,
                                   mau_cooling_type:,
                                   mau_heating_coil_type:,
                                   mau_type:,
                                   model:
  )
    #dwelling units are either system 1 or 3.
    zones = []
    other_spaces = model.getSpaces.select do |space|
      (not is_a_necb_dwelling_unit?(space)) and
          (not is_an_necb_wildcard_space?(space))
    end
    other_spaces.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!
    zones.each do |tz|
      #since dwelling units are all zoned 1:1 to space:zone we simply add the zone to the appropriate btap system.
      create_necb_system(baseboard_type: baseboard_type,
                         boiler_fueltype: boiler_fueltype,
                         chiller_type: chiller_type,
                         fan_type: fan_type,
                         heating_coil_type_sys3: heating_coil_type_sys3,
                         heating_coil_type_sys4: heating_coil_type_sys4,
                         heating_coil_type_sys6: heating_coil_type_sys6,
                         hw_loop: @hw_loop,
                         mau_cooling_type: mau_cooling_type,
                         mau_heating_coil_type: mau_heating_coil_type,
                         mau_type: mau_type,
                         model: model,
                         zones: [tz])
    end
  end


  def auto_system_dwelling_units(baseboard_type:,
                                 boiler_fueltype:,
                                 chiller_type:,
                                 fan_type:,
                                 heating_coil_type_sys3:,
                                 heating_coil_type_sys4:,
                                 heating_coil_type_sys6:,
                                 hw_loop:,
                                 mau_cooling_type:,
                                 mau_heating_coil_type:,
                                 mau_type:,
                                 model:
  )
    #dwelling units are either system 1 or 3.
    zones = []
    model.getSpaces.select {|space| is_a_necb_dwelling_unit?(space)}.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!
    zones.each do |tz|
      #since dwelling units are all zoned 1:1 to space:zone we simply add the zone to the appropriate btap system.
      create_necb_system(baseboard_type: baseboard_type,
                         boiler_fueltype: boiler_fueltype,
                         chiller_type: chiller_type,
                         fan_type: fan_type,
                         heating_coil_type_sys3: heating_coil_type_sys3,
                         heating_coil_type_sys4: heating_coil_type_sys4,
                         heating_coil_type_sys6: heating_coil_type_sys6,
                         hw_loop: @hw_loop,
                         mau_cooling_type: mau_cooling_type,
                         mau_heating_coil_type: mau_heating_coil_type,
                         mau_type: mau_type,
                         model: model,
                         zones: [tz])
    end
  end

  def auto_system_wet_spaces(baseboard_type:,
                             boiler_fueltype:,
                             heating_coil_type_sys4:,
                             model:
  )
    #Determine what zones are wet zones.
    wet_tz = []
    model.getSpaces.select {|space|
      is_an_necb_wet_space?(space)}.each do |space|
      wet_tz << space.thermalZone.get
    end
    wet_tz.uniq!
    #create a system 4 for the wet zones.
    unless wet_tz.empty?
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model,
                                                                   wet_tz,
                                                                   boiler_fueltype,
                                                                   heating_coil_type_sys4,
                                                                   baseboard_type,
                                                                   @hw_loop)
    end
  end

  def auto_system_wild_spaces(baseboard_type:,
                              boiler_fueltype:,
                              heating_coil_type_sys4:,
                              model:
  )
    #Determine what zones are wet zones.
    zones = []
    model.getSpaces.select {|space|
      not is_an_necb_wet_space?(space) and is_an_necb_wildcard_space?(space)}.each do |space|
      zones << space.thermalZone.get
    end

    zones.uniq!
    unless zones.empty?
      #create a system 4 for the wet zones.
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model,
                                                                   zones,
                                                                   boiler_fueltype,
                                                                   heating_coil_type_sys4,
                                                                   baseboard_type,
                                                                   @hw_loop)
    end
  end

  def determine_control_zone(zones)
    # In this case the control zone is the load with the largest heating loads. This may cause overheating of some zones.
    # but this is preferred to unmet heating.
    #Iterate through zones.
    zone_heating_load_hash = {}
    zones.each do |zone|
      zone_heating_load = 0.0
      zone.spaces.each do |space|
        puts space.name
        puts @space_heating_load[space]
        zone_heating_load += @space_heating_load[space]
      end
      zone_heating_load_hash[zone] = zone_heating_load
    end
    return zone_heating_load_hash.max_by(&:last).first
  end

  def set_random_rendering_color(object)
    rendering_color = OpenStudio::Model::RenderingColor.new(object.model)
    rendering_color.setName(object.name.get)
    rendering_color.setRenderingRedValue(@random.rand(255))
    rendering_color.setRenderingGreenValue(@random.rand(255))
    rendering_color.setRenderingBlueValue(@random.rand(255))
    return rendering_color
  end

  #### NECB Systems ####
  def add_sys1_unitary_ac_baseboard_heating(model,
                                            zones,
                                            boiler_fueltype,
                                            mau,
                                            mau_heating_coil_type,
                                            baseboard_type,
                                            hw_loop)
    # System Type 1: PTAC with no heating (unitary AC)
    # Zone baseboards, electric or hot water depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # PSZ to represent make-up air unit (if present)
    # This measure creates:
    # a PTAC  unit for each zone in the building; DX cooling coil
    # and heating coil that is always off
    # Baseboards ("Hot Water or "Electric") in zones connected to hot water loop
    # MAU is present if argument mau == true, not present if argument mau == false
    # MAU is PSZ; DX cooling
    # MAU heating coil: hot water coil or electric, depending on argument mau_heating_coil_type
    # mau_heating_coil_type choices are "Hot Water", "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"

    # Some system parameters are set after system is set up; by applying method 'apply_hvac_efficiency_standard'

    always_on = model.alwaysOnDiscreteSchedule

    # define always off schedule for ptac heating coil
    always_off = BTAP::Resources::Schedules::StandardSchedules::ON_OFF.always_off(model)

    # Create MAU
    # TO DO: MAU sizing, characteristics (fan operation schedules, temperature setpoints, outdoor air, etc)

    if mau == true

      mau_air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

      mau_air_loop.setName('Sys_1_Make-up air unit')

      # When an air_loop is constructed, its constructor creates a sizing:system object
      # the default sizing:system constructor makes a system:sizing object
      # appropriate for a multizone VAV system
      # this systems is a constant volume system with no VAV terminals,
      # and therfore needs different default settings
      air_loop_sizing = mau_air_loop.sizingSystem # TODO units
      air_loop_sizing.setTypeofLoadtoSizeOn('VentilationRequirement')
      air_loop_sizing.autosizeDesignOutdoorAirFlowRate
      air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
      air_loop_sizing.setPreheatDesignTemperature(7.0)
      air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
      air_loop_sizing.setPrecoolDesignTemperature(13.0)
      air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
      air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(13)
      air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(43)
      air_loop_sizing.setSizingOption('NonCoincident')
      air_loop_sizing.setAllOutdoorAirinCooling(true)
      air_loop_sizing.setAllOutdoorAirinHeating(true)
      air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
      air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
      air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

      mau_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

      if mau_heating_coil_type == 'Electric' # electric coil
        mau_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      end

      if mau_heating_coil_type == 'Hot Water'
        mau_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
        hw_loop.addDemandBranchForComponent(mau_htg_coil)
      end

      # Set up DX coil with default curves (set to NECB);

      mau_clg_coil = BTAP::Resources::HVAC::Plant.add_onespeed_DX_coil(model, always_on)

      # oa_controller
      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.autosizeMinimumOutdoorAirFlowRate
      # oa_controller.setEconomizerControlType("DifferentialEnthalpy")

      # oa_system
      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

      # Add the components to the air loop
      # in order from closest to zone to furthest from zone
      supply_inlet_node = mau_air_loop.supplyInletNode
      mau_fan.addToNode(supply_inlet_node)
      mau_htg_coil.addToNode(supply_inlet_node)
      mau_clg_coil.addToNode(supply_inlet_node)
      oa_system.addToNode(supply_inlet_node)

      # Add a setpoint manager to control the supply air temperature
      sat = 20.0
      sat_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      sat_sch.setName('Makeup-Air Unit Supply Air Temp')
      sat_sch.defaultDaySchedule.setName('Makeup Air Unit Supply Air Temp Default')
      sat_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), sat)
      setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, sat_sch)
      setpoint_mgr.addToNode(mau_air_loop.supplyOutletNode)

    end # Create MAU

    # Create a PTAC for each zone:
    # PTAC DX Cooling with electric heating coil; electric heating coil is always off

    # TO DO: need to apply this system to space types:
    # (1) data processing area: control room, data centre
    # when cooling capacity <= 20kW and
    # (2) residential/accommodation: murb, hotel/motel guest room
    # when building/space heated only (this as per NECB; apply to
    # all for initial work? CAN-QUEST limitation)

    # TO DO: PTAC characteristics: sizing, fan schedules, temperature setpoints, interaction with MAU

    zones.each do |zone|
      # Zone sizing temperature
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
      sizing_zone.setZoneCoolingSizingFactor(1.1)
      sizing_zone.setZoneHeatingSizingFactor(1.3)

      # Set up PTAC heating coil; apply always off schedule

      # htg_coil_elec = OpenStudio::Model::CoilHeatingElectric.new(model,always_on)
      htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_off)

      # Set up PTAC DX coil with NECB performance curve characteristics;
      clg_coil = BTAP::Resources::HVAC::Plant.add_onespeed_DX_coil(model, always_on)

      # Set up PTAC constant volume supply fan
      fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
      fan.setPressureRise(640)

      ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                           always_on,
                                                                           fan,
                                                                           htg_coil,
                                                                           clg_coil)
      ptac.setName("#{zone.name} PTAC")
      ptac.addToThermalZone(zone)

      # add zone baseboards
      if baseboard_type == 'Electric'

        #  zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
        zone_elec_baseboard = BTAP::Resources::HVAC::Plant.add_elec_baseboard(model)
        zone_elec_baseboard.addToThermalZone(zone)

      end

      if baseboard_type == 'Hot Water'
        baseboard_coil = BTAP::Resources::HVAC::Plant.add_hw_baseboard_coil(model)
        # Connect baseboard coil to hot water loop
        hw_loop.addDemandBranchForComponent(baseboard_coil)

        zone_baseboard = BTAP::Resources::HVAC::ZoneEquipment.add_zone_baseboard_convective_water(model, always_on, baseboard_coil)
        # add zone_baseboard to zone
        zone_baseboard.addToThermalZone(zone)

      end

      #  # Create a diffuser and attach the zone/diffuser pair to the MAU air loop, if applicable
      if mau == true

        diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
        mau_air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      end # components for MAU
    end # of zone loop

    return mau_air_loop
  end

  # sys1_unitary_ac_baseboard_heating

  def add_sys1_unitary_ac_baseboard_heating_multi_speed(model,
                                                        zones,
                                                        boiler_fueltype,
                                                        mau,
                                                        mau_heating_coil_type,
                                                        baseboard_type,
                                                        hw_loop)

    # System Type 1: PTAC with no heating (unitary AC)
    # Zone baseboards, electric or hot water depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # PSZ to represent make-up air unit (if present)
    # This measure creates:
    # a PTAC  unit for each zone in the building; DX cooling coil
    # and heating coil that is always off
    # Baseboards ("Hot Water or "Electric") in zones connected to hot water loop
    # MAU is present if argument mau == true, not present if argument mau == false
    # MAU is PSZ; DX cooling
    # MAU heating coil: hot water coil or electric, depending on argument mau_heating_coil_type
    # mau_heating_coil_type choices are "Hot Water", "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"

    # Some system parameters are set after system is set up; by applying method 'apply_hvac_efficiency_standard'

    always_on = model.alwaysOnDiscreteSchedule

    # define always off schedule for ptac heating coil
    always_off = BTAP::Resources::Schedules::StandardSchedules::ON_OFF.always_off(model)

    # TODO: Heating and cooling temperature set point schedules are set somewhere else
    # TODO: For now fetch the schedules and use them in setting up the heat pump system
    # TODO: Later on these schedules need to be passed on to this method
    htg_temp_sch = nil
    clg_temp_sch = nil
    zones.each do |izone|
      if izone.thermostat.is_initialized
        zone_thermostat = izone.thermostat.get
        if zone_thermostat.to_ThermostatSetpointDualSetpoint.is_initialized
          dual_thermostat = zone_thermostat.to_ThermostatSetpointDualSetpoint.get
          htg_temp_sch = dual_thermostat.heatingSetpointTemperatureSchedule.get
          clg_temp_sch = dual_thermostat.coolingSetpointTemperatureSchedule.get
          break
        end
      end
    end

    # Create MAU
    # TO DO: MAU sizing, characteristics (fan operation schedules, temperature setpoints, outdoor air, etc)

    if mau == true

      staged_thermostat = OpenStudio::Model::ZoneControlThermostatStagedDualSetpoint.new(model)
      staged_thermostat.setHeatingTemperatureSetpointSchedule(htg_temp_sch)
      staged_thermostat.setNumberofHeatingStages(4)
      staged_thermostat.setCoolingTemperatureSetpointBaseSchedule(clg_temp_sch)
      staged_thermostat.setNumberofCoolingStages(4)

      mau_air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

      mau_air_loop.setName('Sys_1_Make-up air unit')

      # When an air_loop is constructed, its constructor creates a sizing:system object
      # the default sizing:system constructor makes a system:sizing object
      # appropriate for a multizone VAV system
      # this systems is a constant volume system with no VAV terminals,
      # and therfore needs different default settings
      air_loop_sizing = mau_air_loop.sizingSystem # TODO units
      air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
      air_loop_sizing.autosizeDesignOutdoorAirFlowRate
      air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
      air_loop_sizing.setPreheatDesignTemperature(7.0)
      air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
      air_loop_sizing.setPrecoolDesignTemperature(12.8)
      air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
      air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(13.0)
      air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(43.0)
      air_loop_sizing.setSizingOption('NonCoincident')
      air_loop_sizing.setAllOutdoorAirinCooling(false)
      air_loop_sizing.setAllOutdoorAirinHeating(false)
      air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
      air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
      air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
      air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

      mau_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

      # Multi-stage gas heating coil
      if mau_heating_coil_type == 'Electric' || mau_heating_coil_type == 'Hot Water'

        mau_htg_coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
        mau_htg_stage_1 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
        mau_htg_stage_2 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
        mau_htg_stage_3 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
        mau_htg_stage_4 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)

        if mau_heating_coil_type == 'Electric'

          mau_supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)

        elsif mau_heating_coil_type == 'Hot Water'

          mau_supplemental_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
          hw_loop.addDemandBranchForComponent(mau_supplemental_htg_coil)

        end

        mau_htg_stage_1.setNominalCapacity(0.1)
        mau_htg_stage_2.setNominalCapacity(0.2)
        mau_htg_stage_3.setNominalCapacity(0.3)
        mau_htg_stage_4.setNominalCapacity(0.4)

      end

      # Add stages to heating coil
      mau_htg_coil.addStage(mau_htg_stage_1)
      mau_htg_coil.addStage(mau_htg_stage_2)
      mau_htg_coil.addStage(mau_htg_stage_3)
      mau_htg_coil.addStage(mau_htg_stage_4)

      # TODO: other fuel-fired heating coil types? (not available in OpenStudio/E+ - may need to play with efficiency to mimic other fuel types)

      # Set up DX cooling coil
      mau_clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
      mau_clg_coil.setFuelType('Electricity')
      mau_clg_stage_1 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      mau_clg_stage_2 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      mau_clg_stage_3 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      mau_clg_stage_4 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      mau_clg_coil.addStage(mau_clg_stage_1)
      mau_clg_coil.addStage(mau_clg_stage_2)
      mau_clg_coil.addStage(mau_clg_stage_3)
      mau_clg_coil.addStage(mau_clg_stage_4)

      air_to_air_heatpump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(model, mau_fan, mau_htg_coil, mau_clg_coil, mau_supplemental_htg_coil)
      #              air_to_air_heatpump.setName("#{zone.name} ASHP")
      air_to_air_heatpump.setControllingZoneorThermostatLocation(zones[1])
      air_to_air_heatpump.setSupplyAirFanOperatingModeSchedule(always_on)
      air_to_air_heatpump.setNumberofSpeedsforHeating(4)
      air_to_air_heatpump.setNumberofSpeedsforCooling(4)

      # oa_controller
      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.autosizeMinimumOutdoorAirFlowRate
      # oa_controller.setEconomizerControlType("DifferentialEnthalpy")

      # oa_system
      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

      # Add the components to the air loop
      # in order from closest to zone to furthest from zone
      supply_inlet_node = mau_air_loop.supplyInletNode
      air_to_air_heatpump.addToNode(supply_inlet_node)
      oa_system.addToNode(supply_inlet_node)

    end # Create MAU

    # Create a PTAC for each zone:
    # PTAC DX Cooling with electric heating coil; electric heating coil is always off

    # TO DO: need to apply this system to space types:
    # (1) data processing area: control room, data centre
    # when cooling capacity <= 20kW and
    # (2) residential/accommodation: murb, hotel/motel guest room
    # when building/space heated only (this as per NECB; apply to
    # all for initial work? CAN-QUEST limitation)

    # TO DO: PTAC characteristics: sizing, fan schedules, temperature setpoints, interaction with MAU

    zones.each do |zone|
      # Zone sizing temperature
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
      sizing_zone.setZoneCoolingSizingFactor(1.1)
      sizing_zone.setZoneHeatingSizingFactor(1.3)

      # Set up PTAC heating coil; apply always off schedule

      # htg_coil_elec = OpenStudio::Model::CoilHeatingElectric.new(model,always_on)
      htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_off)

      # Set up PTAC DX coil with NECB performance curve characteristics;
      clg_coil = BTAP::Resources::HVAC::Plant.add_onespeed_DX_coil(model, always_on)

      # Set up PTAC constant volume supply fan
      fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
      fan.setPressureRise(640)

      ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                           always_on,
                                                                           fan,
                                                                           htg_coil,
                                                                           clg_coil)
      ptac.setName("#{zone.name} PTAC")
      ptac.addToThermalZone(zone)

      # add zone baseboards
      if baseboard_type == 'Electric'

        #  zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
        zone_elec_baseboard = BTAP::Resources::HVAC::Plant.add_elec_baseboard(model)
        zone_elec_baseboard.addToThermalZone(zone)

      end

      if baseboard_type == 'Hot Water'
        baseboard_coil = BTAP::Resources::HVAC::Plant.add_hw_baseboard_coil(model)
        # Connect baseboard coil to hot water loop
        hw_loop.addDemandBranchForComponent(baseboard_coil)

        zone_baseboard = BTAP::Resources::HVAC::ZoneEquipment.add_zone_baseboard_convective_water(model, always_on, baseboard_coil)
        # add zone_baseboard to zone
        zone_baseboard.addToThermalZone(zone)

      end

      #  # Create a diffuser and attach the zone/diffuser pair to the MAU air loop, if applicable
      if mau == true

        diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
        mau_air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      end # components for MAU
    end # of zone loop

    return true
  end

  # sys1_unitary_ac_baseboard_heating

  def add_sys2_FPFC_sys5_TPFC(model,
                              zones,
                              boiler_fueltype,
                              chiller_type,
                              fan_coil_type,
                              mua_cooling_type,
                              hw_loop)
    # System Type 2: FPFC or System 5: TPFC
    # This measure creates:
    # -a four pipe or a two pipe fan coil unit for each zone in the building;
    # -a make up air-unit to provide ventilation to each zone;
    # -a heating loop, cooling loop and condenser loop to serve four pipe fan coil units
    # Arguments:
    #   boiler_fueltype: "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"
    #   chiller_type: "Scroll";"Centrifugal";"Rotary Screw";"Reciprocating"
    #   mua_cooling_type: make-up air unit cooling type "DX";"Hydronic"
    #   fan_coil_type options are "TPFC" or "FPFC"

    # TODO: Add arguments as needed when the sizing routine is finalized. For example we will need to know the
    # required size of the boilers to decide on how many units are needed based on NECB rules.

    always_on = model.alwaysOnDiscreteSchedule

    # schedule for two-pipe fan coil operation

    twenty_four_hrs = OpenStudio::Time.new(0, 24, 0, 0)

    # Heating coil availability schedule for tpfc
    tpfc_htg_availability_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    tpfc_htg_availability_sch.setName('tpfc_htg_availability')
    # Cooling coil availability schedule for tpfc
    tpfc_clg_availability_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    tpfc_clg_availability_sch.setName('tpfc_clg_availability')
    istart_month = [1, 7, 11]
    istart_day = [1, 1, 1]
    iend_month = [6, 10, 12]
    iend_day = [30, 31, 31]
    sch_htg_value = [1, 0, 1]
    sch_clg_value = [0, 1, 0]
    for i in 0..2
      tpfc_htg_availability_sch_rule = OpenStudio::Model::ScheduleRule.new(tpfc_htg_availability_sch)
      tpfc_htg_availability_sch_rule.setName('tpfc_htg_availability_sch_rule')
      tpfc_htg_availability_sch_rule.setStartDate(model.getYearDescription.makeDate(istart_month[i], istart_day[i]))
      tpfc_htg_availability_sch_rule.setEndDate(model.getYearDescription.makeDate(iend_month[i], iend_day[i]))
      tpfc_htg_availability_sch_rule.setApplySunday(true)
      tpfc_htg_availability_sch_rule.setApplyMonday(true)
      tpfc_htg_availability_sch_rule.setApplyTuesday(true)
      tpfc_htg_availability_sch_rule.setApplyWednesday(true)
      tpfc_htg_availability_sch_rule.setApplyThursday(true)
      tpfc_htg_availability_sch_rule.setApplyFriday(true)
      tpfc_htg_availability_sch_rule.setApplySaturday(true)
      day_schedule = tpfc_htg_availability_sch_rule.daySchedule
      day_schedule.setName('tpfc_htg_availability_sch_rule_day')
      day_schedule.addValue(twenty_four_hrs, sch_htg_value[i])

      tpfc_clg_availability_sch_rule = OpenStudio::Model::ScheduleRule.new(tpfc_clg_availability_sch)
      tpfc_clg_availability_sch_rule.setName('tpfc_clg_availability_sch_rule')
      tpfc_clg_availability_sch_rule.setStartDate(model.getYearDescription.makeDate(istart_month[i], istart_day[i]))
      tpfc_clg_availability_sch_rule.setEndDate(model.getYearDescription.makeDate(iend_month[i], iend_day[i]))
      tpfc_clg_availability_sch_rule.setApplySunday(true)
      tpfc_clg_availability_sch_rule.setApplyMonday(true)
      tpfc_clg_availability_sch_rule.setApplyTuesday(true)
      tpfc_clg_availability_sch_rule.setApplyWednesday(true)
      tpfc_clg_availability_sch_rule.setApplyThursday(true)
      tpfc_clg_availability_sch_rule.setApplyFriday(true)
      tpfc_clg_availability_sch_rule.setApplySaturday(true)
      day_schedule = tpfc_clg_availability_sch_rule.daySchedule
      day_schedule.setName('tpfc_clg_availability_sch_rule_day')
      day_schedule.addValue(twenty_four_hrs, sch_clg_value[i])

    end

    # Create a chilled water loop

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = BTAP::Resources::HVAC::HVACTemplates::NECB2011.setup_chw_loop_with_components(model, chw_loop, chiller_type)

    # Create a condenser Loop

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    ctower = BTAP::Resources::HVAC::HVACTemplates::NECB2011.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Set up make-up air unit for ventilation
    # TO DO: Need to investigate characteristics of make-up air unit for NECB reference
    # and define them here

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    air_loop.setName('Sys_2_Make-up air unit')

    # When an air_loop is contructed, its constructor creates a sizing:system object
    # the default sizing:system constructor makes a system:sizing object
    # appropriate for a multizone VAV system
    # this systems is a constant volume system with no VAV terminals,
    # and therfore needs different default settings
    air_loop_sizing = air_loop.sizingSystem # TODO units
    air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
    air_loop_sizing.setPreheatDesignTemperature(7.0)
    air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
    air_loop_sizing.setPrecoolDesignTemperature(13.0)
    air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(13.0)
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(13.1)
    air_loop_sizing.setSizingOption('NonCoincident')
    air_loop_sizing.setAllOutdoorAirinCooling(false)
    air_loop_sizing.setAllOutdoorAirinHeating(false)
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.008)
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.008)
    air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
    air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
    air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

    # Assume direct-fired gas heating coil for now; need to add logic
    # to set up hydronic or electric coil depending on proposed?

    htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)

    # Add DX or hydronic cooling coil
    if mua_cooling_type == 'DX'
      clg_coil = BTAP::Resources::HVAC::Plant.add_onespeed_DX_coil(model, tpfc_clg_availability_sch)
    elsif mua_cooling_type == 'Hydronic'
      clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, tpfc_clg_availability_sch)
      chw_loop.addDemandBranchForComponent(clg_coil)
    end

    # does MAU have an economizer?
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate

    # oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model,oa_controller)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

    # Add the components to the air loop
    # in order from closest to zone to furthest from zone
    supply_inlet_node = air_loop.supplyInletNode
    fan.addToNode(supply_inlet_node)
    htg_coil.addToNode(supply_inlet_node)
    clg_coil.addToNode(supply_inlet_node)
    oa_system.addToNode(supply_inlet_node)

    # Add a setpoint manager single zone reheat to control the
    # supply air temperature based on the needs of default zone (OpenStudio picks one)
    # TO DO: need to have method to pick appropriate control zone?

    setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
    setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(13.0)
    setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(13.1)
    setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

    # Set up FC (ZoneHVAC,cooling coil, heating coil, fan) in each zone

    zones.each do |zone|
      # Zone sizing temperature
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
      sizing_zone.setZoneCoolingSizingFactor(1.1)
      sizing_zone.setZoneHeatingSizingFactor(1.3)

      # fc supply fan
      fc_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

      if fan_coil_type == 'FPFC'
        # heating coil
        fc_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)

        # cooling coil
        fc_clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, always_on)
      elsif fan_coil_type == 'TPFC'
        # heating coil
        fc_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, tpfc_htg_availability_sch)

        # cooling coil
        fc_clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, tpfc_clg_availability_sch)
      end

      # connect heating coil to hot water loop
      hw_loop.addDemandBranchForComponent(fc_htg_coil)
      # connect cooling coil to chilled water loop
      chw_loop.addDemandBranchForComponent(fc_clg_coil)

      zone_fc = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, always_on, fc_fan, fc_clg_coil, fc_htg_coil)
      zone_fc.addToThermalZone(zone)

      # Create a diffuser and attach the zone/diffuser pair to the air loop (make-up air unit)
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
    end # zone loop
    return air_loop
  end

  # add_sys2_FPFC_sys5_TPFC

  def add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model,
                                                                                         zones,
                                                                                         boiler_fueltype,
                                                                                         heating_coil_type,
                                                                                         baseboard_type,
                                                                                         hw_loop)
    # System Type 3: PSZ-AC
    # This measure creates:
    # -a constant volume packaged single-zone A/C unit
    # for each zone in the building; DX cooling with
    # heating coil: fuel-fired or electric, depending on argument heating_coil_type
    # heating_coil_type choices are "Electric", "Gas", "DX"
    # zone baseboards: hot water or electric, depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"

    always_on = model.alwaysOnDiscreteSchedule
    control_zone = determine_control_zone(zones)

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    air_loop.setName("Sys_3_PSZ #{control_zone.name}")

    # When an air_loop is constructed, its constructor creates a sizing:system object
    # the default sizing:system constructor makes a system:sizing object
    # appropriate for a multizone VAV system
    # this systems is a constant volume system with no VAV terminals,
    # and therfore needs different default settings
    air_loop_sizing = air_loop.sizingSystem # TODO units
    air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
    air_loop_sizing.setPreheatDesignTemperature(7.0)
    air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
    air_loop_sizing.setPrecoolDesignTemperature(13.0)
    air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(13.0)
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(43)
    air_loop_sizing.setSizingOption('NonCoincident')
    air_loop_sizing.setAllOutdoorAirinCooling(false)
    air_loop_sizing.setAllOutdoorAirinHeating(false)
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
    air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
    air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
    air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

    # Zone sizing temperature
    sizing_zone = control_zone.sizingZone
    sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
    sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
    sizing_zone.setZoneCoolingSizingFactor(1.1)
    sizing_zone.setZoneHeatingSizingFactor(1.3)

    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

    case heating_coil_type
    when 'Electric' # electric coil
      htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)

    when 'Gas'
      htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)

    when 'DX'
      htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
      supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      htg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-10.0)
      sizing_zone.setZoneHeatingSizingFactor(1.3)
      sizing_zone.setZoneCoolingSizingFactor(1.0)
    else
      raise("#{heating_coil_type} is not a valid heating coil type.)")
    end

    # TO DO: other fuel-fired heating coil types? (not available in OpenStudio/E+ - may need to play with efficiency to mimic other fuel types)

    # Set up DX coil with NECB performance curve characteristics;
    clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)

    # oa_controller
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate

    # oa_system
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

    # Add the components to the air loop
    # in order from closest to zone to furthest from zone
    supply_inlet_node = air_loop.supplyInletNode
    #              fan.addToNode(supply_inlet_node)
    #              supplemental_htg_coil.addToNode(supply_inlet_node) if heating_coil_type == "DX"
    #              htg_coil.addToNode(supply_inlet_node)
    #              clg_coil.addToNode(supply_inlet_node)
    #              oa_system.addToNode(supply_inlet_node)
    if heating_coil_type == 'DX'
      air_to_air_heatpump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(model, always_on, fan, htg_coil, clg_coil, supplemental_htg_coil)
      air_to_air_heatpump.setName("#{control_zone.name} ASHP")
      air_to_air_heatpump.setControllingZone(control_zone)
      air_to_air_heatpump.setSupplyAirFanOperatingModeSchedule(always_on)
      air_to_air_heatpump.addToNode(supply_inlet_node)
    else
      fan.addToNode(supply_inlet_node)
      htg_coil.addToNode(supply_inlet_node)
      clg_coil.addToNode(supply_inlet_node)
    end
    oa_system.addToNode(supply_inlet_node)

    # Add a setpoint manager single zone reheat to control the
    # supply air temperature based on the needs of this zone
    setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
    setpoint_mgr_single_zone_reheat.setControlZone(control_zone)
    setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(13)
    setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(43)
    setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

    zones.each do |zone|
      # Create a diffuser and attach the zone/diffuser pair to the air loop
      # diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model,always_on)
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      if baseboard_type == 'Electric'

        #  zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
        zone_elec_baseboard = BTAP::Resources::HVAC::Plant.add_elec_baseboard(model)
        zone_elec_baseboard.addToThermalZone(zone)

      end

      if baseboard_type == 'Hot Water'
        baseboard_coil = BTAP::Resources::HVAC::Plant.add_hw_baseboard_coil(model)
        # Connect baseboard coil to hot water loop
        hw_loop.addDemandBranchForComponent(baseboard_coil)

        zone_baseboard = BTAP::Resources::HVAC::ZoneEquipment.add_zone_baseboard_convective_water(model, always_on, baseboard_coil)
        # add zone_baseboard to zone
        zone_baseboard.addToThermalZone(zone)
      end
    end # zone loop

    return true
  end

  # end add_sys3_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed

  def add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(model,
                                                                                        zones,
                                                                                        boiler_fueltype,
                                                                                        heating_coil_type,
                                                                                        baseboard_type,
                                                                                        hw_loop)
    # System Type 3: PSZ-AC
    # This measure creates:
    # -a constant volume packaged single-zone A/C unit
    # for each zone in the building; DX cooling with
    # heating coil: fuel-fired or electric, depending on argument heating_coil_type
    # heating_coil_type choices are "Electric", "Gas", "DX"
    # zone baseboards: hot water or electric, depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"

    always_on = model.alwaysOnDiscreteSchedule
    control_zone = determine_control_zone(zones)

    # TODO: Heating and cooling temperature set point schedules are set somewhere else
    # TODO: For now fetch the schedules and use them in setting up the heat pump system
    # TODO: Later on these schedules need to be passed on to this method
    htg_temp_sch = nil
    clg_temp_sch = nil
    zones.each do |izone|
      if izone.thermostat.is_initialized
        zone_thermostat = izone.thermostat.get
        if zone_thermostat.to_ThermostatSetpointDualSetpoint.is_initialized
          dual_thermostat = zone_thermostat.to_ThermostatSetpointDualSetpoint.get
          htg_temp_sch = dual_thermostat.heatingSetpointTemperatureSchedule.get
          clg_temp_sch = dual_thermostat.coolingSetpointTemperatureSchedule.get
          break
        end
      end
    end


    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    air_loop.setName("Sys_3_PSZ_#{control_zone.name}")

    # When an air_loop is constructed, its constructor creates a sizing:system object
    # the default sizing:system constructor makes a system:sizing object
    # appropriate for a multizone VAV system
    # this systems is a constant volume system with no VAV terminals,
    # and therfore needs different default settings
    air_loop_sizing = air_loop.sizingSystem # TODO units
    air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
    air_loop_sizing.setPreheatDesignTemperature(7.0)
    air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
    air_loop_sizing.setPrecoolDesignTemperature(13.0)
    air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(13.0)
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(43.0)
    air_loop_sizing.setSizingOption('NonCoincident')
    air_loop_sizing.setAllOutdoorAirinCooling(false)
    air_loop_sizing.setAllOutdoorAirinHeating(false)
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
    air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
    air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
    air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

    # Zone sizing temperature
    sizing_zone = control_zone.sizingZone
    sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
    sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
    sizing_zone.setZoneCoolingSizingFactor(1.1)
    sizing_zone.setZoneHeatingSizingFactor(1.3)

    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

    staged_thermostat = OpenStudio::Model::ZoneControlThermostatStagedDualSetpoint.new(model)
    staged_thermostat.setHeatingTemperatureSetpointSchedule(htg_temp_sch)
    staged_thermostat.setNumberofHeatingStages(4)
    staged_thermostat.setCoolingTemperatureSetpointBaseSchedule(clg_temp_sch)
    staged_thermostat.setNumberofCoolingStages(4)
    control_zone.setThermostat(staged_thermostat)

    # Multi-stage gas heating coil
    if heating_coil_type == 'Gas' || heating_coil_type == 'Electric'
      htg_coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
      htg_stage_1 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      htg_stage_2 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      htg_stage_3 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      htg_stage_4 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      if heating_coil_type == 'Gas'
        supplemental_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
      elsif heating_coil_type == 'Electric'
        supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
        htg_stage_1.setNominalCapacity(0.1)
        htg_stage_2.setNominalCapacity(0.2)
        htg_stage_3.setNominalCapacity(0.3)
        htg_stage_4.setNominalCapacity(0.4)
      end

      # Multi-Stage DX or Electric heating coil
    elsif heating_coil_type == 'DX'
      htg_coil = OpenStudio::Model::CoilHeatingDXMultiSpeed.new(model)
      htg_stage_1 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      htg_stage_2 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      htg_stage_3 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      htg_stage_4 = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      sizing_zone.setZoneHeatingSizingFactor(1.3)
      sizing_zone.setZoneCoolingSizingFactor(1.0)
    else
      raise("#{heating_coil_type} is not a valid heating coil type.)")
    end

    # Add stages to heating coil
    htg_coil.addStage(htg_stage_1)
    htg_coil.addStage(htg_stage_2)
    htg_coil.addStage(htg_stage_3)
    htg_coil.addStage(htg_stage_4)

    # TODO: other fuel-fired heating coil types? (not available in OpenStudio/E+ - may need to play with efficiency to mimic other fuel types)

    # Set up DX cooling coil
    clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
    clg_coil.setFuelType('Electricity')
    clg_stage_1 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_stage_2 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_stage_3 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_stage_4 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
    clg_coil.addStage(clg_stage_1)
    clg_coil.addStage(clg_stage_2)
    clg_coil.addStage(clg_stage_3)
    clg_coil.addStage(clg_stage_4)

    # oa_controller
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate

    # oa_system
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

    # Add the components to the air loop
    # in order from closest to zone to furthest from zone
    supply_inlet_node = air_loop.supplyInletNode

    air_to_air_heatpump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(model, fan, htg_coil, clg_coil, supplemental_htg_coil)
    air_to_air_heatpump.setName("#{control_zone.name} ASHP")
    air_to_air_heatpump.setControllingZoneorThermostatLocation(control_zone)
    air_to_air_heatpump.setSupplyAirFanOperatingModeSchedule(always_on)
    air_to_air_heatpump.addToNode(supply_inlet_node)
    air_to_air_heatpump.setNumberofSpeedsforHeating(4)
    air_to_air_heatpump.setNumberofSpeedsforCooling(4)

    oa_system.addToNode(supply_inlet_node)


    zones.each do |zone|
      # Create a diffuser and attach the zone/diffuser pair to the air loop
      # diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model,always_on)
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      if baseboard_type == 'Electric'

        #  zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
        zone_elec_baseboard = BTAP::Resources::HVAC::Plant.add_elec_baseboard(model)
        zone_elec_baseboard.addToThermalZone(zone)

      end

      if baseboard_type == 'Hot Water'
        baseboard_coil = BTAP::Resources::HVAC::Plant.add_hw_baseboard_coil(model)
        # Connect baseboard coil to hot water loop
        hw_loop.addDemandBranchForComponent(baseboard_coil)

        zone_baseboard = BTAP::Resources::HVAC::ZoneEquipment.add_zone_baseboard_convective_water(model, always_on, baseboard_coil)
        # add zone_baseboard to zone
        zone_baseboard.addToThermalZone(zone)
      end
    end # zone loop

    return true
  end

  # end add_sys3_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed

  def add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model,
                                                                   zones,
                                                                   boiler_fueltype,
                                                                   heating_coil_type,
                                                                   baseboard_type,
                                                                   hw_loop)
    # System Type 4: PSZ-AC
    # This measure creates:
    # -a constant volume packaged single-zone A/C unit
    # for each zone in the building; DX cooling with
    # heating coil: fuel-fired or electric, depending on argument heating_coil_type
    # heating_coil_type choices are "Electric", "Gas"
    # zone baseboards: hot water or electric, depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"
    # NOTE: This is the same as system type 3 (single zone make-up air unit and single zone rooftop unit are both PSZ systems)
    # SHOULD WE COMBINE sys3 and sys4 into one script?

    always_on = model.alwaysOnDiscreteSchedule
    control_zone = determine_control_zone(zones)

    # Create a PSZ for each zone
    # TO DO: need to apply this system to space types:
    # (1) automotive area: repair/parking garage, fire engine room, indoor truck bay
    # (2) supermarket/food service: food preparation with kitchen hood/vented appliance
    # (3) warehouse area (non-refrigerated spaces)


    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

    air_loop.setName("Sys_4_PSZ_#{control_zone.name}")

    # When an air_loop is constructed, its constructor creates a sizing:system object
    # the default sizing:system constructor makes a system:sizing object
    # appropriate for a multizone VAV system
    # this systems is a constant volume system with no VAV terminals,
    # and therfore needs different default settings
    air_loop_sizing = air_loop.sizingSystem # TODO units
    air_loop_sizing.setTypeofLoadtoSizeOn('Sensible')
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setMinimumSystemAirFlowRatio(1.0)
    air_loop_sizing.setPreheatDesignTemperature(7.0)
    air_loop_sizing.setPreheatDesignHumidityRatio(0.008)
    air_loop_sizing.setPrecoolDesignTemperature(13.0)
    air_loop_sizing.setPrecoolDesignHumidityRatio(0.008)
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(13.0)
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(43.0)
    air_loop_sizing.setSizingOption('NonCoincident')
    air_loop_sizing.setAllOutdoorAirinCooling(false)
    air_loop_sizing.setAllOutdoorAirinHeating(false)
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
    air_loop_sizing.setCoolingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setCoolingDesignAirFlowRate(0.0)
    air_loop_sizing.setHeatingDesignAirFlowMethod('DesignDay')
    air_loop_sizing.setHeatingDesignAirFlowRate(0.0)
    air_loop_sizing.setSystemOutdoorAirMethod('ZoneSum')

    # Zone sizing temperature
    sizing_zone = control_zone.sizingZone
    sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
    sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
    sizing_zone.setZoneCoolingSizingFactor(1.1)
    sizing_zone.setZoneHeatingSizingFactor(1.3)

    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

    if heating_coil_type == 'Electric' # electric coil
      htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
    end

    if heating_coil_type == 'Gas'
      htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
    end

    # TO DO: other fuel-fired heating coil types? (not available in OpenStudio/E+ - may need to play with efficiency to mimic other fuel types)

    # Set up DX coil with NECB performance curve characteristics;

    clg_coil = BTAP::Resources::HVAC::Plant.add_onespeed_DX_coil(model, always_on)

    # oa_controller
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate

    # oa_system
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

    # Add the components to the air loop
    # in order from closest to zone to furthest from zone
    supply_inlet_node = air_loop.supplyInletNode
    fan.addToNode(supply_inlet_node)
    htg_coil.addToNode(supply_inlet_node)
    clg_coil.addToNode(supply_inlet_node)
    oa_system.addToNode(supply_inlet_node)

    # Add a setpoint manager single zone reheat to control the
    # supply air temperature based on the needs of this zone
    setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
    setpoint_mgr_single_zone_reheat.setControlZone(control_zone)
    setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(13.0)
    setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(43.0)
    setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

    # Create sensible heat exchanger
    #              heat_exchanger = BTAP::Resources::HVAC::Plant::add_hrv(model)
    #              heat_exchanger.setSensibleEffectivenessat100HeatingAirFlow(0.5)
    #              heat_exchanger.setSensibleEffectivenessat75HeatingAirFlow(0.5)
    #              heat_exchanger.setSensibleEffectivenessat100CoolingAirFlow(0.5)
    #              heat_exchanger.setSensibleEffectivenessat75CoolingAirFlow(0.5)
    #              heat_exchanger.setLatentEffectivenessat100HeatingAirFlow(0.0)
    #              heat_exchanger.setLatentEffectivenessat75HeatingAirFlow(0.0)
    #              heat_exchanger.setLatentEffectivenessat100CoolingAirFlow(0.0)
    #              heat_exchanger.setLatentEffectivenessat75CoolingAirFlow(0.0)
    #              heat_exchanger.setSupplyAirOutletTemperatureControl(false)
    #
    #              Connect heat exchanger
    #              oa_node = oa_system.outboardOANode
    #              heat_exchanger.addToNode(oa_node.get)

    zones.each do |zone|
      # Create a diffuser and attach the zone/diffuser pair to the air loop
      # diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model,always_on)
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      if baseboard_type == 'Electric'

        #  zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
        zone_elec_baseboard = BTAP::Resources::HVAC::Plant.add_elec_baseboard(model)
        zone_elec_baseboard.addToThermalZone(zone)

      end

      if baseboard_type == 'Hot Water'
        baseboard_coil = BTAP::Resources::HVAC::Plant.add_hw_baseboard_coil(model)
        # Connect baseboard coil to hot water loop
        hw_loop.addDemandBranchForComponent(baseboard_coil)

        zone_baseboard = BTAP::Resources::HVAC::ZoneEquipment.add_zone_baseboard_convective_water(model, always_on, baseboard_coil)
        # add zone_baseboard to zone
        zone_baseboard.addToThermalZone(zone)
      end
    end # zone loop

    return true
  end

  # end add_sys4_single_zone_make_up_air_unit_with_baseboard_heating

  def add_sys6_multi_zone_built_up_system_with_baseboard_heating(model,
                                                                 zones,
                                                                 boiler_fueltype,
                                                                 heating_coil_type,
                                                                 baseboard_type,
                                                                 chiller_type,
                                                                 fan_type,
                                                                 hw_loop)
    # System Type 6: VAV w/ Reheat
    # This measure creates:
    # a single hot water loop with a natural gas or electric boiler or for the building
    # a single chilled water loop with water cooled chiller for the building
    # a single condenser water loop for heat rejection from the chiller
    # a VAV system w/ hot water or electric heating, chilled water cooling, and
    # hot water or electric reheat for each story of the building
    # Arguments:
    # "boiler_fueltype" choices match OS choices for boiler fuel type:
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"
    # "heating_coil_type": "Electric" or "Hot Water"
    # "baseboard_type": "Electric" and "Hot Water"
    # "chiller_type": "Scroll";"Centrifugal";""Screw";"Reciprocating"
    # "fan_type": "AF_or_BI_rdg_fancurve";"AF_or_BI_inletvanes";"fc_inletvanes";"var_speed_drive"

    always_on = model.alwaysOnDiscreteSchedule

    # Chilled Water Plant

    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = BTAP::Resources::HVAC::HVACTemplates::NECB2011.setup_chw_loop_with_components(model, chw_loop, chiller_type)

    # Condenser System

    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    ctower = BTAP::Resources::HVAC::HVACTemplates::NECB2011.setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Make a Packaged VAV w/ PFP Boxes for each story of the building
    model.getBuildingStorys.sort.each do |story|
      unless (BTAP::Geometry::BuildingStoreys.get_zones_from_storey(story) & zones).empty?

        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        air_loop.setName('Sys_6_VAV with Reheat')
        sizing_system = air_loop.sizingSystem
        sizing_system.setCentralCoolingDesignSupplyAirTemperature(13.0)
        sizing_system.setCentralHeatingDesignSupplyAirTemperature(13.1)
        sizing_system.autosizeDesignOutdoorAirFlowRate
        sizing_system.setMinimumSystemAirFlowRatio(0.3)
        sizing_system.setPreheatDesignTemperature(7.0)
        sizing_system.setPreheatDesignHumidityRatio(0.008)
        sizing_system.setPrecoolDesignTemperature(13.0)
        sizing_system.setPrecoolDesignHumidityRatio(0.008)
        sizing_system.setSizingOption('NonCoincident')
        sizing_system.setAllOutdoorAirinCooling(false)
        sizing_system.setAllOutdoorAirinHeating(false)
        sizing_system.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
        sizing_system.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
        sizing_system.setCoolingDesignAirFlowMethod('DesignDay')
        sizing_system.setCoolingDesignAirFlowRate(0.0)
        sizing_system.setHeatingDesignAirFlowMethod('DesignDay')
        sizing_system.setHeatingDesignAirFlowRate(0.0)
        sizing_system.setSystemOutdoorAirMethod('ZoneSum')

        supply_fan = OpenStudio::Model::FanVariableVolume.new(model, always_on)
        supply_fan.setName('Sys6 Supply Fan')
        return_fan = OpenStudio::Model::FanVariableVolume.new(model, always_on)
        return_fan.setName('Sys6 Return Fan')

        if heating_coil_type == 'Hot Water'
          htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
          hw_loop.addDemandBranchForComponent(htg_coil)
        end
        if heating_coil_type == 'Electric'
          htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
        end

        clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, always_on)
        chw_loop.addDemandBranchForComponent(clg_coil)

        oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
        oa_controller.autosizeMinimumOutdoorAirFlowRate

        oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

        # Add the components to the air loop
        # in order from closest to zone to furthest from zone
        supply_inlet_node = air_loop.supplyInletNode
        supply_outlet_node = air_loop.supplyOutletNode
        supply_fan.addToNode(supply_inlet_node)
        htg_coil.addToNode(supply_inlet_node)
        clg_coil.addToNode(supply_inlet_node)
        oa_system.addToNode(supply_inlet_node)
        returnAirNode = oa_system.returnAirModelObject.get.to_Node.get
        return_fan.addToNode(returnAirNode)

        # Add a setpoint manager to control the
        # supply air to a constant temperature
        sat_c = 13.0
        sat_sch = OpenStudio::Model::ScheduleRuleset.new(model)
        sat_sch.setName('Supply Air Temp')
        sat_sch.defaultDaySchedule.setName('Supply Air Temp Default')
        sat_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), sat_c)
        sat_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, sat_sch)
        sat_stpt_manager.addToNode(supply_outlet_node)

        # Make a VAV terminal with HW reheat for each zone on this story that is in intersection with the zones array.
        # and hook the reheat coil to the HW loop
        (BTAP::Geometry::BuildingStoreys.get_zones_from_storey(story) & zones).each do |zone|
          # Zone sizing parameters
          sizing_zone = zone.sizingZone
          sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
          sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
          sizing_zone.setZoneCoolingSizingFactor(1.1)
          sizing_zone.setZoneHeatingSizingFactor(1.3)

          if heating_coil_type == 'Hot Water'
            reheat_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
            hw_loop.addDemandBranchForComponent(reheat_coil)
          elsif heating_coil_type == 'Electric'
            reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
          end

          vav_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, always_on, reheat_coil)
          air_loop.addBranchForZone(zone, vav_terminal.to_StraightComponent)
          # NECB2011 minimum zone airflow setting
          min_flow_rate = 0.002 * zone.floorArea
          vav_terminal.setFixedMinimumAirFlowRate(min_flow_rate)
          vav_terminal.setMaximumReheatAirTemperature(43.0)
          vav_terminal.setDamperHeatingAction('Normal')

          # Set zone baseboards
          if baseboard_type == 'Electric'
            zone_elec_baseboard = BTAP::Resources::HVAC::Plant.add_elec_baseboard(model)
            zone_elec_baseboard.addToThermalZone(zone)
          end
          if baseboard_type == 'Hot Water'
            baseboard_coil = BTAP::Resources::HVAC::Plant.add_hw_baseboard_coil(model)
            # Connect baseboard coil to hot water loop
            hw_loop.addDemandBranchForComponent(baseboard_coil)
            zone_baseboard = BTAP::Resources::HVAC::ZoneEquipment.add_zone_baseboard_convective_water(model, always_on, baseboard_coil)
            # add zone_baseboard to zone
            zone_baseboard.addToThermalZone(zone)
          end
        end
      end
    end # next story

    # for debugging
    # puts "end add_sys6_multi_zone_built_up_with_baseboard_heating"

    return true
  end

end

