extends Spatial

var Chunk = load("res://Land.gd")
var Graph = load("res://Graph.gd")

var chunks = {}

export (Vector2) var grid_size = Vector2(32, 32)
export (Vector2) var chunk_size = Vector3(64, 64, 64)
# export (String) var map_name = "test_map"

var player
var graph

var queue = []
var pending = {}
# var save_dir

var thread
var mutex
var gen_chunks

# Anti-clockwise square vertices
const CO = [
	Vector3( 1, 0,  0),
	Vector3( 1, 0,  1),
	Vector3( 0, 0,  1),
	Vector3(-1, 0,  1),
	Vector3(-1, 0,  0),
	Vector3(-1, 0, -1),
	Vector3( 0, 0, -1),
	Vector3( 1, 0, -1),
]

# pre-calc chunk order for rotations - depending on direction facing
const CHUNK_ORDERS = [
	[ CO[0], CO[1], CO[7], CO[2], CO[6], CO[3], CO[5], CO[4] ],
	[ CO[1], CO[2], CO[0], CO[3], CO[7], CO[4], CO[6], CO[5] ],
	[ CO[2], CO[3], CO[1], CO[4], CO[0], CO[5], CO[7], CO[6] ],
	[ CO[3], CO[4], CO[2], CO[5], CO[1], CO[6], CO[0], CO[7] ],
	[ CO[4], CO[5], CO[3], CO[6], CO[2], CO[7], CO[1], CO[0] ],
	[ CO[5], CO[6], CO[4], CO[7], CO[3], CO[0], CO[2], CO[1] ],
	[ CO[6], CO[7], CO[5], CO[0], CO[4], CO[1], CO[3], CO[2] ],
	[ CO[7], CO[0], CO[6], CO[1], CO[5], CO[2], CO[4], CO[3] ],
]

func _ready():
	print("readying chunk manager")
	graph = Graph.new()
	# Not really a physics process, a port from godot2 code
	set_physics_process(true)

	player = $"/root/Root/PlayerBody"
	
	# var save_dir_path = "user://" + map_name + "/"
	# save_dir = Directory.new()
	# if save_dir.file_exists(save_dir_path):
	# 	print ("Found dir")
	# 	save_dir.open(save_dir_path)
	# else:
	# 	print ("Making dir")
	# 	save_dir.make_dir_recursive(save_dir_path)
	# 	save_dir.open(save_dir_path)

	# Set up the threading components
	mutex = Mutex.new()
	thread = Thread.new()

	# # Need to load/create the first chunk before starting loading thread
	# var chunk_key = get_centered_chunk()
	# queue_chunk(chunk_key)
	# load_keyed_chunk(chunk_key)
	
	# Kick off the loading thread
	thread.start(self, "chunk_generation", 0)

func get_centered_chunk():
	var center = player.translation
	
	var vector = Vector3()
	vector.x = floor(center.x / chunk_size.x)
	vector.y = 0.0
	vector.z = floor(center.z / chunk_size.z)
	
	return vector

func get_chunks_viewable():
	var center_chunk = get_centered_chunk()

	var chunk_queue = [center_chunk]

	# Queue by direction facing
	var rotation = player.rotation.y
	var rot_index = int(floor( (rotation + PI) * 4 / PI + 0.5)) % 8

	for offset in CHUNK_ORDERS[rot_index]:
		chunk_queue.append(center_chunk + offset)
	
	return chunk_queue

func _physics_process(delta):
	var chunks_saveable_keys = chunks.keys()
	var chunks_viewable = get_chunks_viewable()

	# Listed the view direction chunks first
	# Load chunks in that order
	for chunk_key in chunks_viewable:
		if not chunks.has(chunk_key):
			load_keyed_chunk(chunk_key)
			chunks_saveable_keys.erase(chunk_key)
	
	# # Save generated chunks that are ready
	# for chunk_key in chunks_saveable_keys:
	# 	save_keyed_chunk(chunk_key)

func load_keyed_chunk(chunk_key):
	if queue_chunk(chunk_key):
		var new_chunk = is_ready(chunk_key)
		if (new_chunk):
			new_chunk.set_name(str(chunk_key))
			print ("Adding chunk to scene: " + str(chunk_key))
			print ("              os time: " + str(OS.get_unix_time()))
			add_child(new_chunk, true)
			chunks[chunk_key] = new_chunk
		# else:
		# 	print ("Chunk not ready: " + str(chunk_key))

# func save_keyed_chunk(chunk_key):
# 	if chunks.has(chunk_key) and mutex.try_lock() == OK:
# 		var old_chunk = chunks[chunk_key]
# 		save_chunk_to_file(chunk_key, old_chunk)
# 		chunks.erase(chunk_key)
# 		old_chunk.queue_free()
# 		mutex.unlock()

const once_per = 0.03

func chunk_generation(unused):
	print("Starting chunk checker")
	
	gen_chunks = true
	var next_time = OS.get_unix_time() + once_per
	while gen_chunks:
		if next_time < OS.get_unix_time() and mutex.try_lock() == OK:
			next_time += once_per
			chunk_loader()
			mutex.unlock()
	
	# Save any chunk that are still loaded
	var chunks_saveable_keys = chunks.keys()
	for chunk_key in chunks_saveable_keys:
		save_keyed_chunk(chunk_key)

func chunk_loader():
	if queue:
		var chunk_key = queue.pop_front()
		var new_pos = Vector3(chunk_size.x * chunk_key.x, chunk_size.y * chunk_key.y, chunk_size.z * chunk_key.z)
		var new_chunk = Chunk.new(grid_size, chunk_key)
		new_chunk.scale = chunk_size
		new_chunk.translation = new_pos
		# var chunk_data = load_chunk_from_file(chunk_key)
		# if typeof(chunk_data) == TYPE_DICTIONARY:
		# 	new_chunk.set_content(chunk_data)
		# else:
		new_chunk.generate_content()
		#
		pending[chunk_key] = new_chunk

func queue_chunk(var chunk_key):
	var already_queued = true
	if mutex.try_lock() == OK:
		if not (chunk_key in pending or chunk_key in queue):
			already_queued = false
			queue.push_back(chunk_key)
		mutex.unlock()
	return already_queued

func is_ready(chunk_key):
	var chunk = false
	if mutex.try_lock() == OK:
		if pending.has(chunk_key):
			chunk = pending[chunk_key]
			pending.erase(chunk_key)
		mutex.unlock()
	return chunk

# func load_chunk_from_file(chunk_key):
# 	var load_chunk_file = save_dir.get_current_dir() + "/" + str(chunk_key.x) + "_" + str(chunk_key.y) + ".chunk"
# 	var load_chunk = File.new()
# 	# If file isn't there, skip it
# 	if !load_chunk.file_exists(load_chunk_file):
# 		return false
# 	# File exists, try to load it
# 	var chunk_data = {}
# 	load_chunk.open(load_chunk_file, File.READ)
# 	chunk_data.parse_json(load_chunk.get_line())
# 	load_chunk.close()
# 	return chunk_data

# func save_chunk_to_file(chunk_key, old_chunk):
# 	var chunk_data = old_chunk.get_save_data()
# 	# Only save if there's something to save
# 	if typeof(chunk_data) == TYPE_DICTIONARY:
# 		var save_chunk_file = save_dir.get_current_dir() + "/" + str(chunk_key.x) + "_" + str(chunk_key.y) + ".chunk"
# 		var save_chunk = File.new()
# 		save_chunk.open(save_chunk_file, File.WRITE)
# 		save_chunk.store_line(chunk_data.to_json())
# 		save_chunk.close()

func _exit_tree():
	self.gen_chunks = false
	thread.wait_to_finish()

