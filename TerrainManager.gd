extends Spatial

var Chunk = load("res://Land.gd")
var Graph = load("res://Graph.gd")
var HeightHash = load("res://HeightHash.gd")

var chunks = {} # All loaded chunks

export (Vector2) var grid_size = Vector2(32, 32)
export (Vector2) var chunk_size = Vector3(64, 64, 64)
export (ShaderMaterial) var material
# export (String) var map_name = "test_map"

var player
var graph

var queue = []   # Chunks not yet created
var queue_mutex

var pending = {} # Chunks to be added to the scene
var pending_mutex
# var save_dir

var thread
# var mutex
var gen_chunks

var status_output

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
	status_output = $"/root/Root/HUD/Panel/TerrainLabel"
	player = $"/root/Root/PlayerBody"

	# Create the re-usable graph layer we dump meshes from
	var hhash = HeightHash.new()
	graph = Graph.new(hhash)
	graph.create_base_square_grid(grid_size.x, grid_size.y)

	# Set up the threading components
	# mutex = Mutex.new()
	queue_mutex = Mutex.new()
	pending_mutex = Mutex.new()
	thread = Thread.new()

	# Need to load/create the first chunk before starting loading thread
	var chunk_key = get_centered_chunk()
	queue_chunk(chunk_key)
	chunk_loader()
	load_keyed_chunk(chunk_key)

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

func _process(delta):
	var chunks_viewable = get_chunks_viewable()

	# Listed the view direction chunks first
	# Load chunks in that order
	for chunk_key in chunks_viewable:
		if not chunks.has(chunk_key):
			load_keyed_chunk(chunk_key)

	var status = ""
	status += "queue   : " + str(queue) + "\n"
	status += "pending : " + str(pending.keys()) + "\n"
	status += "chunks  : " + str(chunks.keys()) + "\n"
	status += "height difference : from " + str(graph.min_height) + " to " + str(graph.max_height)

	status_output.text = status

func load_keyed_chunk(chunk_key):
	var new_chunk = is_ready(chunk_key)
	if (new_chunk):
		new_chunk.set_name(str(chunk_key))
		# print ("Adding chunk to scene: " + str(chunk_key))
		# print ("              os time: " + str(OS.get_unix_time()))
		add_child(new_chunk)
		chunks[chunk_key] = new_chunk
	else:
		queue_chunk(chunk_key)

const once_per = 0.03

func chunk_generation(unused):
	print("Starting chunk checker")
	
	gen_chunks = true
	var next_time = OS.get_unix_time() + once_per
	while gen_chunks:
		var new_chunk
		if next_time < OS.get_unix_time():
			next_time += once_per
			chunk_loader()

func chunk_loader():
	if queue:
		queue_mutex.lock()
		var chunk_key = queue.pop_front()
		queue_mutex.unlock()

		if chunks.has(chunk_key) or pending.has(chunk_key):
			return

		print ("create: " + str(chunk_key))
		var new_pos = Vector3(chunk_size.x * chunk_key.x, chunk_size.y * chunk_key.y, chunk_size.z * chunk_key.z)
		var new_chunk = Chunk.new(grid_size, chunk_key, graph)
		new_chunk.scale = chunk_size
		new_chunk.translation = new_pos
		new_chunk.material_override = material
		new_chunk.generate_content()

		pending_mutex.lock()
		pending[chunk_key] = new_chunk
		pending_mutex.unlock()

func queue_chunk(var chunk_key):
	if not chunks.has(chunk_key) and not pending.has(chunk_key) and not queue.has(chunk_key):
		queue_mutex.lock()
		queue.push_back(chunk_key)
		queue_mutex.unlock()

func is_ready(chunk_key):
	var chunk = false
	if pending.has(chunk_key):
		chunk = pending[chunk_key]
		pending_mutex.lock()
		pending.erase(chunk_key)
		pending_mutex.unlock()
	return chunk

func _exit_tree():
	self.gen_chunks = false
	thread.wait_to_finish()

