![DCS JTAC Script for Eagle Dynamics Digital Combat Simulator.](/assets/head.png)

# DCS-MYTHS-JTAC v0.3
Adding the JTAC to your mission has never been easier.

## Contents
This script is a comprehensive rewrite and enhancement of JTAC functionality for DCS World multiplayer missions. Version 0.3 introduces significant improvements to multi-player compatibility, menu management, and laser code generation.

### Key Features
- **Multi-player Support**: Full support for multiple simultaneous JTAC missions with proper state management
- **Military-Standard Laser Codes**: Proper 1[5-7][1-8][1-8] format with intelligent generation algorithms
- **Persistent JTAC Control**: Maintain JTAC control when switching aircraft or respawning
- **Enhanced Menu System**: Robust F10 radio menu management without duplication issues
- **Debug & Monitoring**: Comprehensive debug system for troubleshooting and mission monitoring

## Changelog

### Version 0.3 - Major Multi-Player & Performance Update
**🐛 Bug Fixes:**
- Fixed F10 menu duplication when players respawn into static slots
- Resolved empty dismiss package radio menu issue
- Fixed JTAC control loss when switching between aircraft

**✨ New Features:**
- JTAC missions now persist across unit switches and respawns
- Military-standard laser code format (1[5-7][1-8][1-8]) with 192 unique codes
- Intelligent laser code generation with random assignment and systematic fallback
- Enhanced multi-player state management with proper cleanup
- Consolidated constants section for improved maintainability

**⚡ Performance Improvements:**
- Optimized laser code generation algorithm with adaptive strategies
- Reduced redundant menu operations and improved state tracking
- Smart cleanup of disconnected player resources

**🎯 Technical Enhancements:**
- Comprehensive debug messaging system for troubleshooting
- Better error handling for edge cases in multi-player environments
- Improved code organization with centralized configuration constants

# Instructions

## Quick Start
1. Open the example mission file `jtactest.miz` in the mission editor.
2. Click the Set Rules for trigger icon on the left hand nav menu (3 down from the text "MIS").
3. Note the ONCE trigger is set. Click on it.
4. Note the Time More is set to trigger on load.
5. Click the DO SCRIPT FILE and make sure it is linked to the `JTAC.lua` script.
6. Save and load the mission as a multiplayer mission.

## In-Game Usage
1. **Request JTAC Assignment**: Use F10 radio menu → JTAC → Request JTAC assignment
2. **Place Map Marker**: You'll receive a unique callsign (e.g., "jt-alpha-1567"). Place this as text on a map marker at your desired target area.
3. **Deploy JTAC**: Use F10 menu to request either:
   - **Drone Package**: Air-based JTAC with enhanced mobility
   - **Ground Package**: Ground-based JTAC team
4. **Control JTAC**: Once deployed, use the JTAC radio menu for:
   - Target designation and laser guidance
   - IR pointer control
   - Illumination bombs and smoke marking
   - Target scanning and priority setting
5. **Dismiss Package**: Use the dismiss package menu when mission is complete

## Configuration

The script includes a comprehensive configuration section at the top of `JTAC.lua`:

```lua
-- Core Settings
JTAC.debug = false               -- Enable debug messages
JTAC.production_mode = true      -- Disable all debug in production

-- Mission Parameters  
JTAC.searchRadius = 5000         -- Target scanning radius (meters)
JTAC.missionLimit = 5           -- Max simultaneous JTAC missions per player

-- Group Restrictions
JTAC.groupPrefix = false         -- Restrict to groups with specific prefix
JTAC.Prefix = "Only"            -- Group name prefix if restriction enabled
```

## Multi-Player Features
- **Unique Laser Codes**: Each JTAC automatically receives a unique military-standard laser code
- **Persistent Control**: Maintain JTAC control when switching aircraft or respawning  
- **Mission Isolation**: Each player's JTAC missions are independent
- **Automatic Cleanup**: Disconnected players' resources are automatically cleaned up
- **No Menu Conflicts**: Robust menu system prevents duplication and conflicts

## Troubleshooting

### Enable Debug Mode
```lua
JTAC.debug = true
JTAC.production_mode = false
```
This will show detailed messages in DCS log and on-screen for troubleshooting.

### Common Issues
- **Menu not appearing**: Check that your group name matches prefix restrictions if enabled
- **Laser code conflicts**: The system automatically manages 192 unique codes - conflicts should not occur
- **JTAC not responding**: Verify the JTAC unit exists and is within the target area
- **Lost JTAC control**: The new persistence system should maintain control across respawns

### Debug Commands
The script provides several debug functions accessible via F10 menu when debug mode is enabled:
- Mission status monitoring
- Active laser code tracking  
- Player state inspection

## Technical Details

### Laser Code Format
Military standard format: `1[5-7][1-8][1-8]`
- First digit: Always `1`
- Second digit: `5`, `6`, or `7`  
- Third/Fourth digits: `1` through `8`
- Total possible codes: 192 unique combinations

### Performance Optimization
- **Smart Algorithm**: Uses random selection when many codes available, systematic search when running low
- **Adaptive Thresholds**: Automatically adjusts strategy based on code usage (25% threshold)
- **Memory Efficient**: Proper cleanup prevents memory leaks in long-running missions

## Credits
- Original JTAC code concept from DCS User Files community
- Enhanced and rewritten for DCS-MYTHS by the community
- Version 0.3 improvements: Menu system fixes, multi-player enhancements, and performance optimization

![DCS JTAC Script for Eagle Dynamics Digital Combat Simulator.](/assets/map.png)
