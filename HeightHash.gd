extends Object

# This is designed as a height map generation tool
# Internally it can use many techniques, but ultimately 
# should return a simple height per coordinate call

var Perlin = load("res://PerlinRef.gd")

var zoom
var hashes
var base_height
var start_amp
var amp_multiplier

func _init():
	zoom = 0.5
	hashes = [
		Perlin.new(0.125, 0.125, 1.0, zoom),
		Perlin.new(1.0, 1.0, 1.0, zoom),
		Perlin.new(0.03125, 0.03125, 1.0, zoom),
		Perlin.new(0.0078125, 0.0078125, 1.0, zoom),
	]

	base_height = 0.125
	start_amp = 0.25
	amp_multiplier = 0.125

func getHash(x, y):
	var new_height = base_height
	var amp = start_amp
	for p in hashes:
		new_height += p.getHash(x, y) * amp
		amp *= amp_multiplier
	return new_height