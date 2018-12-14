class NECB2011

  # Top level method that merges spaces into zones where possible. This requires a sizing run. This follows the spirit of
  # the EE4 modelling manual found here https://www.nrcan.gc.ca/energy/software-tools/7457 where the
  # A zone includes those areas in the building that meet three criteria:
  # * Served by the same HVAC system
  # * Similar operation and function
  # * Similar heating/cooling loads
  # Some expections are dwelling units wet zone and wild zones.  These spaces will have special considerations when autozoning a
  # building.

  def auto_zoning( model )
    #The first thing we need to do is get a sizing run to determine the heating loads of all the spaces. The default
    # btap geometry has a one to one relationship of zones to spaces.. So we simply create the thermal zones for all the spaces.
    # to do this we need to create thermals zone for each space.

    # Remove any Thermal zones assigned before
    model.getThermalZones.each(&:remove)
    # create new thermal zones one to one with spaces.
    model_create_thermal_zones(model)
    # do a sizing run.
    raise("autorun sizing run failed!") if model_run_sizing_run(model, "#{Dir.pwd}/autozone") == false
    #collect sizing information on each space.
    self.store_space_sizing_loads(model)

    # Remove any Thermal zones assigned again to start fresh.
    model.getThermalZones.each(&:remove)

    self.auto_zone_dwelling_units(model)
    self.auto_zone_wet_spaces(model)
    self.auto_zone_all_other_spaces(model)
    self.auto_zone_wild_spaces(model)
  end

  # Organizes Zones and assigns them to appropriate systems according to NECB 2011-17 systems spacetype rules in Sec 8.
  # requires requires fuel type to be assigned for each system aspect. Defaults to gas hydronic.
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


  # Method to store space sizing loads. This is needed because later when the zones are destroyed this information will be lost.
  def store_space_sizing_loads(model)
    @stored_space_heating_sizing_loads = {}
    @stored_space_cooling_sizing_loads = {}
    model.getSpaces.each do |space|
      @stored_space_heating_sizing_loads[space] = space.spaceType.get.standardsSpaceType.get == '- undefined -' ? 0.0 : space.thermalZone.get.heatingDesignLoad.get
      @stored_space_cooling_sizing_loads[space] = space.spaceType.get.standardsSpaceType.get == '- undefined -' ? 0.0 : space.thermalZone.get.coolingDesignLoad.get
    end
  end
  # Returns heating load per area for space after sizing run has been done.
  def stored_space_heating_load(space)
    @stored_space_heating_sizing_loads[space]
  end
  # Returns the cooling load per area for space after sizing runs has been done.
  def stored_space_cooling_load(space)
    @stored_space_cooling_sizing_loads[space]
  end

  # # Returns the heating load per area for zone after sizing runs has been done.
  def stored_zone_heating_load(zone)
    total = 0.0
    zone.spaces.each do |space|
      total += stored_space_heating_load(space)
    end
    return total
  end
  # Returns the cooling load per area for zone after sizing runs has been done.
  def stored_zone_cooling_load(zone)
    total = 0.0
    zone.spaces.each do |space|
      total += stored_space_cooling_load(space)
    end
    return total
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
      zone.setName("DU_BT=#{space.spaceType.get.standardsBuildingType.get}_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory().get.name}_SCH#{ determine_dominant_schedule([space])}")
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
      # get space to dominant schedule
      dominant_schedule = determine_dominant_schedule(space.model.getSpaces)
      #create new TZ and set space to the zone.
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      space.setThermalZone(zone)
      zone.setName("WET_BT=#{space.spaceType.get.standardsBuildingType.get}_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory().get.name}_SCH#{dominant_schedule}")
      #Set multiplier from the original tz multiplier.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end


      #this method will determine if the right schedule was used for this wet & wild space if not.. it will reset the space
      # to use the correct schedule version of the wet and wild space type.
      adjust_wildcard_spacetype_schedule(space, dominant_schedule)
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
          if are_space_loads_similar?(space_1: space, space_2: space_target) && space.buildingStory().get == space_target.buildingStory().get # added since chris needs zones to not span floors for costing.
            adjust_wildcard_spacetype_schedule(space_target, dominant_schedule)
            space_target.setThermalZone(zone)
          end
        end
      end
      wet_zone_array << zone
    end
    return wet_zone_array
  end

  # This method will find all the spaces that are not wet, wild or dwelling units and zone them. It will try to determine
  # if the spaces are similar based on exposure and load and blend those spaces into the same zone.  It will not merge spaces
  # from different floors, since this will impact Chris Kirneys costing algorithms.
  def auto_zone_all_other_spaces(model)
    other_tz_array = Array.new
    #iterate through all non wildcard spaces.
    model.getSpaces.select {|space| not is_a_necb_dwelling_unit?(space) and not is_an_necb_wildcard_space?(space)}.each do |space|
      #skip if already assigned to a thermal zone.
      next unless space.thermalZone.empty?
      #create new zone for this space based on the space name.
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      tz_name = "ALL_BT=#{space.spaceType.get.standardsBuildingType.get}_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory().get.name}_SCH=#{ determine_dominant_schedule([space])}"
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
          if are_space_loads_similar?(space_1: space, space_2: space_target) and space.buildingStory().get == space_target.buildingStory().get # added since chris needs zones to not span floors for costing.
            space_target.setThermalZone(zone)
          end
        end
      end
      other_tz_array << zone
    end
    return other_tz_array
  end

  # This will take all the wildcard spaces and merge them to be supported by a system 4. The control zone will be the
  # zone that has the largest heating load per area.
  def auto_zone_wild_spaces(model)
    other_tz_array = Array.new
    #iterate through wildcard spaces.
    model.getSpaces.select {|space| is_an_necb_wildcard_space?(space) and not is_an_necb_wet_space?(space)}.each do |space|
      #skip if already assigned to a thermal zone.
      next unless space.thermalZone.empty?
      #create new zone for this space based on the space name.
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setRenderingColor(self.set_random_rendering_color(zone))
      tz_name = "WILD_BT=#{space.spaceType.get.standardsBuildingType.get}_ST=#{space.spaceType.get.standardsSpaceType.get}_FL=#{space.buildingStory().get.name}_SCH=#{determine_dominant_schedule(space.model.getSpaces)}"
      zone.setName(tz_name)
      #sets space mulitplier unless it is nil or 1.
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      #Assign space to the new zone.
      space.setThermalZone(zone)

      #lets keep the wild schedules to be the same as what dominate the floor.
      dominant_floor_schedule = determine_dominant_schedule(space.model.getSpaces)
      adjust_wildcard_spacetype_schedule(space, dominant_floor_schedule)

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
      model.getSpaces.select {|space| is_an_necb_wildcard_space?(space) and not is_an_necb_wet_space?(space)}.each do |space_target|
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


    wild_zone_array = Array.new
    #Get a list of all the wild spaces.
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

  # This method will determine if the loads on a zone are similar. (Exposure, space type, space loads, and schedules, etc)
  def are_zone_loads_similar?(zone_1:, zone_2:)
    #make sure they have the same number of spaces.
    truthes = []
    return false if zone_1.spaces.size != zone_2.spaces.size
    zone_1.spaces.each do |space_1|
      zone_2.spaces.each do |space_2|
        if are_space_loads_similar?(space_1: space_1, space_2: space_2)
          truthes << true
        end
      end
    end
    #truthes sizes should be the same as the # of spaces if all spaces are similar.
    return truthes.size == zone_1.spaces.size
  end

  # This method will determine if the loads on a space are similar. (Exposure, space type, space loads, and schedules, etc)
  def are_space_loads_similar?(space_1:,
                               space_2:,
                               surface_percent_difference_tolerance: 0.01,
                               angular_percent_difference_tolerance: 0.001,
                               heating_load_percent_difference_tolerance: 10.0)
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
    #Spaces should have the same number of surface orientations.
    return false unless space_1_surface_report.size == space_2_surface_report.size
    #spaces should have similar loads
    return false unless self.percentage_difference(stored_space_heating_load(space_1), stored_space_heating_load(space_2)) <= heating_load_percent_difference_tolerance
    #Each surface should match
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
                                       space_2_surface[:opaque_subsurface_area_to_floor_ratio]) <= surface_percent_difference_tolerance

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
    surface_report.sort! {|a, b| [a[:surface_type], a[:azimuth], a[:tilt], a[:boundary_condition]] <=> [b[:surface_type], b[:azimuth], b[:tilt], b[:boundary_condition]]}


    return surface_report
  end

  #Check to see if this is a wildcard space that the NECB does not have a specified schedule or system for.
  def is_an_necb_wildcard_space?(space)
    space_type_data = standards_lookup_table_first(table_name: 'space_types',
                                                   search_criteria: {'template' => self.class.name,
                                                                     'space_type' => space.spaceType.get.standardsSpaceType.get,
                                                                     'building_type' => space.spaceType.get.standardsBuildingType.get})
    raise("#{space}") if space_type_data.nil?
    return space_type_data["necb_hvac_system_selection_type"] == "Wildcard"
  end

  # Check to see if this is a wet space that the NECB does not have a specified schedule or system for. Currently hardcoded to
  # Locker room and washroom.
  def is_an_necb_wet_space?(space)
    #Hack! Should replace this with a proper table lookup.
    return space.spaceType.get.standardsSpaceType.get.include?('Locker room') || space.spaceType.get.standardsSpaceType.get.include?('Washroom')
  end

  # Check if the space spactype is a dwelling unit as per NECB.
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

  # Determines what system index number is required for the space's spacetype by NECB rules.
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
          necb_hvac_system_select['min_cooling_capacity_kw'] <= self.stored_space_cooling_load(space) &&
          necb_hvac_system_select['max_cooling_capacity_kw'] >= self.stored_space_cooling_load(space)
    end
    raise("could not find system for given spacetype") if necb_hvac_system_select.nil?
    return necb_hvac_system_select['system_type']
  end

  # Determines what system index number is required for the thermal zone based on the spacetypes it contains
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

  # Math fundtion to determine percent difference.
  def percentage_difference(value_1, value_2)
    return 0.0 if value_1 == value_2
    return ((value_1 - value_2).abs / ((value_1 + value_2) / 2) * 100)
  end

  # Set wildcard spactype schedule to NECB letter index.
  def adjust_wildcard_spacetype_schedule(space, schedule)
    if space.spaceType.empty?
      OpenStudio.logFree(OpenStudio::Error, 'Error: No spacetype assigned for #{space.name.get}. This must be assigned. Aborting.')
    end
    # Get current spacetype name
    space_type_name = space.spaceType.get.standardsSpaceType.get.to_s
    # Determine new spacetype name.
    regex = /^(.*sch-)(\S)$/
    new_spacetype_name = "#{space_type_name.match(regex).captures.first}#{schedule}"
    new_spacetype = nil

    #if the new spacetype does not match the old space type. we gotta update the space with the new spacetype.
    if space_type_name != new_spacetype_name
      new_spacetype = space.model.getSpaceTypes.detect do |spacetype|
        not spacetype.standardsBuildingType.empty? and #need to do this to prevent an exception.
            spacetype.standardsBuildingType.get == new_spacetype_name and
            not spacetype.standardsSpaceType.empty? and #need to do this to prevent an exception.
            spacetype.standardsSpaceType.get == new_spacetype_name
      end
      if new_spacetype.nil?
        puts "must create new spacetype"
        # Space type is not in model. need to create from scratch.
        new_spacetype = OpenStudio::Model::SpaceType.new(space.model)
        new_spacetype.setStandardsBuildingType(space.spaceType.get.standardsBuildingType.get)
        new_spacetype.setStandardsSpaceType(new_spacetype_name)
        new_spacetype.setName("#{space.spaceType.get.standardsBuildingType.get} #{new_spacetype_name}")
        new_spacetype.setRenderingColor(self.set_random_rendering_color(new_spacetype))
        space_type_apply_internal_loads(new_spacetype, true, true, true, true, true, true)
        space_type_apply_internal_load_schedules(new_spacetype, true, true, true, true, true, true, true)
      end
      space.setSpaceType(new_spacetype)
      raise () if  schedule != space.spaceType.get.name.get.match(regex)[2]
    end
  end




  ################################################# NECB Systems

  # Method will create a hot water loop if systems default fuel and medium sources require it.
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

  # Default method to create a necb system and assign array of zones to be supported by it. It will try to bring zones with
  # similar loads on the same airloops and set control zones where possible for single zone systems and will create monolithic
  # system 6 multizones where possible.
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
    #puts JSON.pretty_generate(system_zones_hash)
    # go through each system and zones pairs to
    system_zones_hash.each_pair do |system, zones|
      case system
      when 0, nil
        # Do nothing no system assigned to zone. Used for Unconditioned spaces
      when 1
        group_similar_zones_together(zones).each do |zones|
          mau_air_loop = add_sys1_unitary_ac_baseboard_heating(model,
                                                               zones,
                                                               boiler_fueltype,
                                                               mau_type,
                                                               mau_heating_coil_type,
                                                               baseboard_type,
                                                               @hw_loop)
        end
      when 2
        group_similar_zones_together(zones).each do |zones|
          add_sys2_FPFC_sys5_TPFC(model,
                                  zones,
                                  boiler_fueltype,
                                  chiller_type,
                                  'FPFC',
                                  mau_cooling_type,
                                  @hw_loop)
        end
      when 3
        group_similar_zones_together(zones).each do |zones|
          add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model,
                                                                                             zones,
                                                                                             boiler_fueltype,
                                                                                             heating_coil_type_sys3,
                                                                                             baseboard_type,
                                                                                             @hw_loop)
        end
      when 4
        group_similar_zones_together(zones).each do |zones|
          add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model,
                                                                       zones,
                                                                       boiler_fueltype,
                                                                       heating_coil_type_sys4,
                                                                       baseboard_type,
                                                                       @hw_loop)
        end
      when 5
        group_similar_zones_together(zones).each do |zones|
          add_sys2_FPFC_sys5_TPFC(model,
                                  zones,
                                  boiler_fueltype,
                                  chiller_type,
                                  'TPFC',
                                  mau_cooling_type,
                                  @hw_loop)
        end
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
        group_similar_zones_together(zones).each do |zones|
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
  end

# This method will deal with all non wet, non-wild, and non-dwelling units thermal zones.
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

    zones = []
    other_spaces = model.getSpaces.select do |space|
      (not is_a_necb_dwelling_unit?(space)) and
          (not is_an_necb_wildcard_space?(space))
    end
    other_spaces.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!

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
                       zones: zones)
  end


  # This methos will ensure that all dwelling units are assigned to a system 1 or 3. There is an option to have a shared
  # AHU or not. Currently set to false. So by default all dwelling units will have their own AHU.
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
                                 model:,
                                 dwelling_shared_ahu: false
  )

    system_zones_hash = {}
    zones = []
    model.getSpaces.select {|space| is_a_necb_dwelling_unit?(space)}.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!
    zones.each do |zone|
      system_zones_hash[get_necb_thermal_zone_system_selection(zone)] = [] if system_zones_hash[get_necb_thermal_zone_system_selection(zone)].nil?
      system_zones_hash[get_necb_thermal_zone_system_selection(zone)] << zone
    end


    # go through each system and zones pairs to
    system_zones_hash.each_pair do |system, zones|
      case system
      when 1
        if dwelling_shared_ahu
          add_sys1_unitary_ac_baseboard_heating(model,
                                                zones,
                                                boiler_fueltype,
                                                mau_type,
                                                mau_heating_coil_type,
                                                baseboard_type,
                                                @hw_loop)
        else
          #Create a separate air loop for each unit.
          zones.each do |zone|
            add_sys1_unitary_ac_baseboard_heating(model,
                                                  [zone],
                                                  boiler_fueltype,
                                                  mau_type,
                                                  mau_heating_coil_type,
                                                  baseboard_type,
                                                  @hw_loop)

          end
        end

      when 3
        if dwelling_shared_ahu
          add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model,
                                                                                             zones,
                                                                                             boiler_fueltype,
                                                                                             heating_coil_type_sys3,
                                                                                             baseboard_type,
                                                                                             @hw_loop)
        else
          #Create a separate air loop for each unit.
          zones.each do |zone|
            add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_single_speed(model,
                                                                                               zones,
                                                                                               boiler_fueltype,
                                                                                               heating_coil_type_sys3,
                                                                                               baseboard_type,
                                                                                               @hw_loop)

          end
        end
      end

    end
  end

  # All wet spaces will be on their own system 4 AHU.
  def auto_system_wet_spaces(baseboard_type:,
                             boiler_fueltype:,
                             heating_coil_type_sys4:,
                             model:)
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

  # All wild spaces will be on a single system 4 ahu with the largests heating load zone being the control zone.
  def auto_system_wild_spaces(baseboard_type:,
                              boiler_fueltype:,
                              heating_coil_type_sys4:,
                              model:
  )

    zones = []
    model.getSpaces.select {|space|
      not is_an_necb_wet_space?(space) and is_an_necb_wildcard_space?(space)}.each do |space|
      zones << space.thermalZone.get
    end
    zones.uniq!
      #create a system 4 for the wild zones.
      add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(model,
                                                                   zones,
                                                                   boiler_fueltype,
                                                                   heating_coil_type_sys4,
                                                                   baseboard_type,
                                                                   @hw_loop)
  end

  #This method will determine the control zone from the last sizing run space loads.
  def determine_control_zone(zones)
    # In this case the control zone is the load with the largest heating loads. This may cause overheating of some zones.
    # but this is preferred to unmet heating.
    #Iterate through zones.
    zone_heating_load_hash = {}
    zones.each {|zone| zone_heating_load_hash[zone] = self.stored_zone_heating_load(zone)}
    return zone_heating_load_hash.max_by(&:last).first
  end


  # This method is used to determine if there are single zones that can be grouped with zones of similar loads.
  def group_similar_zones_together(zones)
    total_zones_input = zones.size
    array_of_array_of_zones = []
    accounted_for = []
    # Go through other zones to see if there are similar zones with similar loads on the same floor that can be grouped.
    zones.each do |zone|
      similar_array_of_zones = []
      next if accounted_for.include?(zone.name.to_s)
      similar_array_of_zones << zone
      accounted_for << zone.name.to_s
      zones.each do |zone_target|
        unless accounted_for.include?(zone_target.name.to_s)
          if are_zone_loads_similar?(zone_1: zone,
                                     zone_2: zone_target)
            similar_array_of_zones << zone_target
            accounted_for << zone_target.name.to_s
          end
        end
      end
      array_of_array_of_zones << similar_array_of_zones
    end
    total_zones_output = 0
    array_of_array_of_zones.each do |zones|
      total_zones_output += zones.size
    end
    #puts total_zones_output
    #puts accounted_for.sort
    #sanity check.
    if total_zones_output != total_zones_input
      #puts JSON.pretty_generate(array_of_array_of_zones)
      #puts JSON.pretty_generate(accounted_for.sort)
      raise("#{}")
    end
    return array_of_array_of_zones
  end

  # This method will create a color object used in SU, 3D Viewer and Floorspace.js
  def set_random_rendering_color(object)
    rendering_color = OpenStudio::Model::RenderingColor.new(object.model)
    rendering_color.setName(object.name.get)
    rendering_color.setRenderingRedValue(@random.rand(255))
    rendering_color.setRenderingGreenValue(@random.rand(255))
    rendering_color.setRenderingBlueValue(@random.rand(255))
    return rendering_color
  end

  #### NECB Systems ####

  # This will add a add all zones included into a system 1 ahu with the zone with the largest load as the control zone.
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
      add_zonal_ptac(operation_schedule: always_on, model: model, zone: zone)

      add_zonal_baseboard_heating(operation_shedule: always_on, baseboard_type: baseboard_type, hw_loop: hw_loop,
                                  model: model, zone: zone)

      #  # Create a diffuser and attach the zone/diffuser pair to the MAU air loop, if applicable
      if mau == true

        diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
        mau_air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

      end # components for MAU
    end # of zone loop

    return mau_air_loop
  end


  # sys1_unitary_ac_baseboard_heating
  # This will add a add all zones included into a system 1 ahu with the zone with the largest load as the control zone.
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

      # Add PTAC heating coil; apply always off schedule
      add_zonal_ptac(operation_schedule: always_on, model: model, zone: zone)

      # add zone baseboards
      add_zonal_baseboard_heating(operation_shedule: always_on, baseboard_type: baseboard_type, hw_loop: hw_loop,
                                  model: model, zone: zone)


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

      #add baseboard
      add_zonal_baseboard_heating(operation_shedule: always_on, baseboard_type: baseboard_type, hw_loop: hw_loop, zone: zone, model: model)

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
      # add baseboard
      add_zonal_baseboard_heating(operation_shedule: always_on, baseboard_type: baseboard_type, hw_loop: hw_loop, zone: zone, model: model)
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
      #add baseboard
      add_zonal_baseboard_heating(operation_shedule: always_on, baseboard_type: baseboard_type, hw_loop: hw_loop, zone: zone, model: model)
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
    #Determine how may zones we are working with including multipliers.


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
    zones.each do |zone|
      # Zone sizing parameters
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperature(13.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperature(43.0)
      sizing_zone.setZoneCoolingSizingFactor(1.1)
      sizing_zone.setZoneHeatingSizingFactor(1.3)

      #add zone VAV terminal
      add_zone_vav_terminal(air_loop: air_loop,
                            always_on: always_on,
                            heating_coil_type: heating_coil_type,
                            hw_loop: hw_loop,
                            model: model,
                            zone: zone)

      # Set zone baseboards
      add_zonal_baseboard_heating(operation_shedule: always_on,
                                  baseboard_type: baseboard_type,
                                  hw_loop: hw_loop,
                                  model: model,
                                  zone: zone)
    end
    return true
  end
  ########################################################### Zonal Equipment

  # this will add a single duct vav terminal with reheat to the zone provided.
  # @return vav_terminal : the vav terminal object.
  def add_zone_vav_terminal(air_loop:,
                            always_on:,
                            heating_coil_type:,
                            hw_loop:,
                            model:,
                            zone:)
    case heating_coil_type
    when 'Hot Water'
      reheat_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
      hw_loop.addDemandBranchForComponent(reheat_coil)
    when heating_coil_type == 'Electric'
      reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
    end

    vav_terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, always_on, reheat_coil)
    air_loop.addBranchForZone(zone, vav_terminal.to_StraightComponent)
    # NECB2011 minimum zone airflow setting
    min_flow_rate = 0.002 * zone.floorArea
    vav_terminal.setFixedMinimumAirFlowRate(min_flow_rate)
    vav_terminal.setMaximumReheatAirTemperature(43.0)
    vav_terminal.setDamperHeatingAction('Normal')
    return vav_terminal
  end

  # This will add a ptac unit (no heating) to the zone.
  # returns the ZoneHVACPackagedTerminalAirConditioner wiht heating off.
  def add_zonal_ptac(operation_schedule:, model:, zone:)
    #No heating since the baseboards will pro

    htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOffDiscreteSchedule)

    # Set Always on schedule
    # Set up PTAC DX coil with NECB performance curve characteristics;
    clg_coil = BTAP::Resources::HVAC::Plant.add_onespeed_DX_coil(model, operation_schedule)

    # Set up PTAC constant volume supply fan
    fan = OpenStudio::Model::FanConstantVolume.new(model, operation_schedule)
    fan.setPressureRise(640)

    ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                         operation_schedule,
                                                                         fan,
                                                                         htg_coil,
                                                                         clg_coil)
    ptac.setName("#{zone.name} PTAC")
    ptac.addToThermalZone(zone)
    return ptac
  end

  #Adds a baseboard heater to the zone.
  def add_zonal_baseboard_heating(operation_shedule:,
                                  baseboard_type: 'Electric',
                                  hw_loop: nil,
                                  model:,
                                  zone:)
    zone_baseboard = nil
    case baseboard_type
    when 'Electric'
      #  zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
      zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
      zone_elec_baseboard.addToThermalZone(zone)
    when 'Hot Water'
      baseboard_coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model);
      # Connect baseboard coil to hot water loop
      hw_loop.addDemandBranchForComponent(baseboard_coil)
      zone_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(model,operation_shedule,baseboard_coil);
      # add zone_baseboard to zone
    end
    zone_baseboard.addToThermalZone(zone)
    return zone_baseboard
  end
end


