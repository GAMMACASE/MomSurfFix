# MomSurfFix
Momentum mod surf/ramp fix ported to csgo and css.
## About
That fix modifies ``CGameMovement::TryPlayerMove()`` function to behave like momentum mod ones. [Whole function](https://github.com/momentum-mod/game/blob/develop/mp/src/game/shared/momentum/mom_gamemovement.cpp#L1838-L2282) was recreated on sourcepawn and replaced default ``CGameMovement::TryPlayerMove()``. By modifying that function and applying all fixes that momentum mod team has done, you'll get quite good surf/ramp glitch fix.

## Requirements
* [Dhooks with detour support](https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589);
* SourceMod 1.10 or higher.

## Available cvars
* **momsurffix_ramp_bumpcount** - Left from original momentum mods function, helps with fixing surf/ramp bugs;
* **momsurffix_ramp_initial_retrace_length** - Left from original momentum mods function, amount of units used in offset for retraces;
* **momsurffix_enable_asm_optimizations** - Enables ASM optimizations, that may improve performance of the plugin;
* **momsurffix_enable_noclip_workaround** - Enables workaround to prevent issue #1.

## Special thanks to
* [Momentum mod team for the actual fix](https://momentum-mod.org/);
* [Guys from bhoptimer discord for testing](https://discord.gg/jyA9q5k);
