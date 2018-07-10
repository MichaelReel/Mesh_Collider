extends MeshInstance

var graph

var Graph = load("res://Graph.gd")
var Perlin = load("res://PerlinRef.gd")

const render_options = [
	Mesh.PRIMITIVE_POINTS,
	Mesh.PRIMITIVE_LINES,
	Mesh.PRIMITIVE_TRIANGLES,
]

var render_as = 2

func _ready():
	graph = Graph.new()

	# Update the input graph to give variable heights
	add_base_height_features()

	# Creating drawing elements
	# Create a mesh from the voronoi site info
	self.set_mesh(create_mesh())

	var parent = $"/root/Root/Terrain"
	var shape = self.create_trimesh_collision()
	parent.add_child(shape)

func add_base_height_features():

	graph.create_base_square_grid(64, 64)

	var zoom = 0.5
	var procs = [
		Perlin.new(0.125, 0.125, 1.0, zoom),
		Perlin.new(0.03125, 0.03125, 1.0, zoom),
		Perlin.new(0.0078125, 0.0078125, 1.0, zoom),
	]

	graph.create_height_features(procs, 0.125, 0.25, 0.125)

func create_mesh():
	if not graph:
		print("No input or no surface tool supplied!")
		return

	# Update the vertex indices
	graph.update_vertex_indices()
	
	# Create a new mesh
	var mesh = Mesh.new()
	var surfTool = SurfaceTool.new()

	match render_options[render_as]:
		Mesh.PRIMITIVE_POINTS:
			surfTool.begin(Mesh.PRIMITIVE_POINTS)
			surfTool.add_color(Color(1.0, 1.0, 1.0, 1.0))
			for vert in graph.vertices:
				surfTool.add_vertex(vert.pos)
				surfTool.add_index(vert.index)

		Mesh.PRIMITIVE_LINES:
			surfTool.begin(Mesh.PRIMITIVE_LINES)
			surfTool.add_color(Color(1.0, 1.0, 1.0, 1.0))
			for vert in graph.vertices:
				surfTool.add_vertex(vert.pos)
			for edge in graph.edges:
				surfTool.add_index(edge.v1.index)
				surfTool.add_index(edge.v2.index)

		Mesh.PRIMITIVE_TRIANGLES:
			# Recalculate the colour scale
			var color_scale = (2.0 / (graph.max_height - graph.min_height))
			
			surfTool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for tri in graph.triangles:
				add_coloured_vertex(surfTool, tri.v1.pos, color_scale)
				add_coloured_vertex(surfTool, tri.v3.pos, color_scale)
				add_coloured_vertex(surfTool, tri.v2.pos, color_scale)
			
			# surfTool.index()
			surfTool.generate_normals()

		_:
			print("Unsupported render type!")

	# Create mesh with SurfaceTool
	surfTool.commit(mesh)
	return mesh

func add_coloured_vertex(surfTool, pos, color_scale):
	var height = pos.y
	var red = max(((height - graph.min_height) * color_scale) - 1.0, 0.0)
	var green = min((height - graph.min_height) * color_scale, 1.0)
	var blue = max(((height - graph.min_height) * color_scale) - 1.0, 0.0)
	surfTool.add_color(Color(red, green, blue, 1.0))
	surfTool.add_vertex(pos)