![DCS JTAC Script for Eagle Dynamics Digital Combat Simulator.](/assets/head.png)

# DCS-MYTHS-JTAC
Adding the JTAC to your mission has never been easier.

## Contents
This script is a rewrite of some of the functionality of the original JTAC code found as freeware on dcs userfiles.
If you would like to troubleshoot in the lua script you can turn debuging on which will output messages.

# Instructions
1. Open the example mission file `jtactest.miz` in the mission editor.
3. Click the Set Rules for trigger icon on the left hand nav menu. (3 Down from the text "MIS")
4. Note the ONCE trigger is set. Click on it.
5. Note the Time More is set to trigger on load.
6. Click the DO SCRIPT FILE and make sure it is linked to the Air `JTAC.lua` script.
7. Load the mission as a multiplayer mission, then in-game:
    Use the radio menu to request a JTAC spawn, you will be given a map marker code, place the code on the map and call in the JTAC from the radio menu. Once the JTAC is on station you can either use the DCS 9 lines through the JTAC radio menu showing the radio freq. or the custom JTAC target menu to pick targets.
8. Enjoy.

![DCS JTAC Script for Eagle Dynamics Digital Combat Simulator.](/assets/map.png)
