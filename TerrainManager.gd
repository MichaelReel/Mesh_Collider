extends Spatial

var Chunk = load("res://Land.gd")
var Graph = load("res://Graph.gd")
var HeightHash = load("res://HeightHash.gd")

var chunk_refs = {} # LOD and Pos details for loaded and yet to be loaded chunks

# These are coupled to the movement ratios in CameraControl
export (Array, Vector2) var grid_sizes
export (Array, Vector3) var chunk_sizes
export (Array, float) var graph_scales

export (ShaderMaterial) var material

var player
var graphs = []

# LODs
var lods

var queue = []   # Chunks not yet created
var queue_mutex

var pending = {} # Chunks to be added to the scene
var pending_mutex

var active = {}  # Chunks loaded into the scene

var thread
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
const CHUNK_ORDERS = [ CO[0], CO[1], CO[7], CO[2], CO[6], CO[3], CO[5], CO[4] ]

class ChunkRef:
	var lod
	var pos
	func _init(level_of_detail, position):
		lod = level_of_detail
		pos = position
	
	func key():
		return str(lod) + "," + str(pos)

func _ready():
	print("readying chunk manager")
	status_output = $"/root/Root/HUD/Panel/TerrainLabel"
	player = $"/root/Root/Viewports/Near/PlayerBody"
	lods = [ $Near, $Far, $Further ]

	var primary_lod_ind = 0

	# Create the re-usable graph layer we dump meshes from
	var hhash = HeightHash.new()
	var lod = 0
	for grid_size in grid_sizes:
		var graph = Graph.new(hhash, graph_scales[lod])
		graph.create_base_square_grid(grid_size.x, grid_size.y)
		graphs.append(graph)
		lod += 1

	# Set up the threading components
	# mutex = Mutex.new()
	queue_mutex = Mutex.new()
	pending_mutex = Mutex.new()
	thread = Thread.new()

	# Need to load/create the first chunk before starting loading thread
	var key_str = get_centered_chunk_key_strs()[primary_lod_ind]
	queue_chunk(key_str)
	chunk_loader()
	load_keyed_chunk(key_str)

	# TODO: Not sure I like this coupling, may need to rethink:
	player.translation.y = chunk_sizes[primary_lod_ind].y * graphs[primary_lod_ind].max_height * 1.1

	# Kick off the loading thread
	thread.start(self, "chunk_generation", 0)

func get_chunk_key_str(lod, pos):
	var chunk_ref = ChunkRef.new(lod, pos)
	var key_str = chunk_ref.key()
	if not chunk_refs.has(key_str):
		chunk_refs[key_str] = chunk_ref
	return key_str

func get_chunk_by_key_str(key_str):
	return chunk_refs[key_str]

func get_all_chunk_key_strs():
	return chunk_refs.keys()

func get_centered_chunk_key_strs():
	var center = player.translation
	var key_strs = []
	
	var lod = 0
	for chunk_size in chunk_sizes:
		var pos = Vector3()
		pos.x = floor(center.x / chunk_size.x)
		pos.y = 0.0
		pos.z = floor(center.z / chunk_size.z)

		key_strs.append(get_chunk_key_str(lod, pos))
		lod += 1

	return key_strs

func get_chunk_key_strs_viewable():
	var center_chunk_key_strs = get_centered_chunk_key_strs()

	# Queue by direction facing
	var rotation = player.rotation.y
	var rot_index = int(floor( (rotation + PI) * 4 / PI + 0.5)) % 8
	var chunk_queue = []

	var lod = 0
	for center_chunk_key_str in center_chunk_key_strs:
		var center_chunk_pos = get_chunk_by_key_str(center_chunk_key_str).pos

		chunk_queue.append(center_chunk_key_str)

		for offset_ind in range(len(CHUNK_ORDERS)):
			offset_ind += rot_index
			offset_ind %= len(CHUNK_ORDERS)
			var offset = CHUNK_ORDERS[offset_ind]
			var key_str = get_chunk_key_str(lod, center_chunk_pos + offset)
			chunk_queue.append(key_str)
		lod += 1
	
	return chunk_queue

func _process(_delta):
	var chunk_key_strs_viewable = get_chunk_key_strs_viewable()

	var chunks_releasable = get_all_chunk_key_strs()
	# Listed the view direction chunks first
	# Load chunks in that order
	for key_str in chunk_key_strs_viewable:
		chunks_releasable.erase(key_str)
		if not active.has(key_str):
			load_keyed_chunk(key_str)
	
	for key_str in chunks_releasable:
		release_chunk_by_key_str(key_str)

	var status = ""
	status += "height difference : from " + str(graphs[0].min_height) + " to " + str(graphs[0].max_height) + "\n"
	status += "queue   : " + str(queue) + "\n"
	status += "pending : " + str(pending) + "\n"
	status += "active  : " + str(active) + "\n"

	status_output.text = status

func release_chunk_by_key_str(key_str):
	var chunk_key = get_chunk_by_key_str(key_str)
	# Only release active keys
	if active.has(key_str) and not pending.has(key_str):
		if queue.has(key_str):
			queue_mutex.lock()
			queue.erase(key_str)
			queue_mutex.unlock()
		var loaded_chunk = active[key_str]
		lods[chunk_key.lod].remove_child(loaded_chunk)
		loaded_chunk.free()
		active.erase(key_str)
		chunk_refs.erase(key_str)

func load_keyed_chunk(key_str):
	var new_chunk = is_ready(key_str)
	if (new_chunk):
		new_chunk.set_name(key_str)
		# print ("Adding chunk to scene: " + key_str)
		# print ("              os time: " + str(OS.get_unix_time()))
		var lod_ind = get_chunk_by_key_str(key_str).lod
		lods[lod_ind].add_child(new_chunk)
		active[key_str] = new_chunk
	else:
		queue_chunk(key_str)

const once_per = 0.03

func chunk_generation(_unused):
	print("Starting chunk checker")
	
	gen_chunks = true
	var next_time = OS.get_unix_time() + once_per
	while gen_chunks:
		if next_time < OS.get_unix_time():
			next_time += once_per
			chunk_loader()

func chunk_loader():
	if not queue.empty():
		queue_mutex.lock()
		var key_str = queue.pop_front()
		queue_mutex.unlock()

		if active.has(key_str) or pending.has(key_str):
			return

		print ("create: " + key_str)
		var chunk_key = get_chunk_by_key_str(key_str)
		var chunk_pos = chunk_key.pos
		var lod_ind = chunk_key.lod
		var new_pos = Vector3(chunk_sizes[lod_ind].x * chunk_pos.x, chunk_sizes[lod_ind].y * chunk_pos.y, chunk_sizes[lod_ind].z * chunk_pos.z)

		var new_chunk = Chunk.new(grid_sizes[lod_ind], chunk_pos, graphs[lod_ind])
		new_chunk.scale = chunk_sizes[lod_ind]
		new_chunk.translation = new_pos
		new_chunk.material_override = material
		new_chunk.layers = 1 << lod_ind
		new_chunk.generate_content(true if lod_ind == 0 else false)

		pending_mutex.lock()
		pending[key_str] = new_chunk
		pending_mutex.unlock()

func queue_chunk(var key_str):
	if not active.has(key_str) and not pending.has(key_str) and not queue.has(key_str):
		queue_mutex.lock()
		queue.push_back(key_str)
		queue_mutex.unlock()

func is_ready(key_str):
	var chunk = false
	if pending.has(key_str):
		chunk = pending[key_str]
		pending_mutex.lock()
		pending.erase(key_str)
		pending_mutex.unlock()
	return chunk

func _exit_tree():
	self.gen_chunks = false
	thread.wait_to_finish()

	for key_str in get_all_chunk_key_strs():
		release_chunk_by_key_str(key_str)

