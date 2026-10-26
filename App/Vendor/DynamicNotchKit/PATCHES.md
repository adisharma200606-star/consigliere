# What was changed in this copy of DynamicNotchKit

This folder is a copy of [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 1.1.0 by Kai Azim, used under its MIT licence (see `LICENSE`).

It is copied into the repo, instead of being downloaded, for one reason: the library draws the notch's shape, shadow and black surface itself, and masks whatever you put inside to the notch's shape. The glow around the notch, the rim of light along its bottom edge and the grain on its surface all have to be drawn as part of that shape, so they cannot be added from outside the library. Three small edits add them. All are marked `CONSIGLIERE PATCH` in the source.

1. `Sources/DynamicNotchKit/DynamicNotch/DynamicNotch.swift` gains two published properties, `glowColors` and `glowStrength`. Leave them alone and the library behaves exactly as upstream.
2. `Sources/DynamicNotchKit/Views/NotchContentView.swift` adds three coloured shadows that are only visible while the notch is expanded.
3. `DynamicNotch.swift` gains `rimColor`, `grainImage` and `grainOpacity`, and `Sources/DynamicNotchKit/Views/NotchView.swift` draws them inside the notch's mask while it is expanded. Nil or zero leaves the library as upstream.

Also removed: the `Documentation.docc` folder and the `swift-docc-plugin` dependency in `Package.swift`, so building needs no extra downloads.

To update to a newer upstream version: replace `Sources/` with the new one and re-apply the three edits.
