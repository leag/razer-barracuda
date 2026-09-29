"""Starting-point EQ curves from Tarik Topalovic's Barracuda 2.4 project.

These are listening presets, not a calibration for the Barracuda X (2022).
Copyright (c) 2026 Tarik Topalovic. MIT; see LICENSES/TarikTopalovic-MIT.txt.
"""

EQ_PRESETS = {'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
 'Game': [1, 0, -3, -1, 1, 2, 4, 5, 3, 1],
 'FPS': [-3, -4, -4, -2, 0, 2, 5, 6, 4, 2],
 'Music': [0, -1, -2, 2, 2, 1, 1, 1, 1, 0],
 'Rock': [3, 2, 0, 1, 2, 2, 2, 2, 1, 0],
 'Hip-Hop': [7, 7, 4, 1, 0, 1, 2, 1, 0, 0],
 'EDM': [9, 8, 5, 1, -1, 0, 1, 2, 3, 3],
 'Bass': [8, 7, 4, 1, 0, 0, 0, 0, 1, 1],
 'Movie': [5, 4, 1, 0, 1, 2, 2, 1, 3, 3],
 'Warm': [3, 3, 2, 1, 0, 0, -1, -2, -2, -2],
 'Bright': [-2, -2, -1, 0, 1, 2, 3, 4, 5, 4],
 'Vocal': [-4, -4, -2, 1, 3, 4, 3, 1, 0, -1]}

MIC_EQ_PRESETS = {'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
 'Clarity': [-2, -1, -2, -1, 0, 1, 3, 3, 2, 1],
 'Warm': [2, 1, 0, 0, 0, 0, -1, -2, -1, -1],
 'Bright': [-3, -2, -1, 0, 1, 2, 3, 4, 3, 2],
 'Broadcast': [-1, 0, -2, -1, -2, 0, 2, 3, 2, 1],
 'Deep': [3, 3, 2, 1, 0, -1, -1, 0, 0, 0],
 'Anti-Pop': [-6, -4, -2, -1, 0, 1, 2, 2, 1, 0],
 'Telephone': [-6, -4, 0, 2, 3, 3, 1, -2, -4, -6]}
