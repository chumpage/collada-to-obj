#!/usr/bin/ruby
require 'rexml/document'
require 'optparse'

$epsilon = 1e-6

class ColladaError < StandardError  
end

class NormalizeZeroLengthVectorError < ColladaError
end

def str_to_int(str)
  Integer(str) rescue raise ColladaError.new("#{str} isn't a valid integer")
end

def str_to_float(str)
  Float(str) rescue raise ColladaError.new("#{str} isn't a valid float")
end

def partition_array(array, sub_array_length, stride=sub_array_length)
  if stride < sub_array_length
    raise ColladaError.new("partition_array error: stride (#{stride}) < sub_array_length (#{sub_array_length})")
  end
  if array.count % stride != 0
    raise ColladaError.new("partition_array error: array.count (#{array.count}) % stride (#{stride}) != 0")
  end
  sub_arrays = []
  0.step(array.count-1, stride) do |i|
    sub_arrays << array[i, sub_array_length]
  end
  sub_arrays
end

def read_numeric_array(elem, conversion_fn)
  elem.text.to_s.split.map {|str_val| send(conversion_fn, str_val)}
end

def read_int_array(elem)
  read_numeric_array(elem, :str_to_int)
end

def read_float_array(elem)
  read_numeric_array(elem, :str_to_float)
end

def nested_array_equal(a1, a2, epsilon=$epsilon)
  # base case: compare two numbers
  if a1.kind_of?(Numeric) or a2.kind_of?(Numeric)
    if not (a1.kind_of?(Numeric) and a2.kind_of?(Numeric))
      return false
    else
      return (a1-a2).abs < epsilon
    end
  end

  # array (recursive) case: compare array counts, then compare each element
  if a1.count != a2.count
    return false
  end

  (0...a1.count).each do |i|
    if not nested_array_equal(a1[i], a2[i], epsilon)
      return false
    end
  end

  true
end

def vector_length(v)
  Math.sqrt(v.map { |val| val*val }.reduce(:+))
end

def vector_normalize(v)
  len = vector_length(v)
  if len < $epsilon
    raise NormalizeZeroLengthVectorError.new("can't normalize 0-length vector")
  end
  v.map { |val| val /= len }
end

def vector_cross(a, b)
  ax, ay, az = a
  bx, by, bz = b
  [ay*bz-az*by, az*bx-ax*bz, ax*by-ay*bx]
end

def new_matrix(rows, cols, vals=nil)
  if vals != nil and vals.count != rows*cols
    raise
  end
  if vals != nil
    partition_array(vals, cols)
  else
    partition_array(Array.new(rows*cols, 0), cols)
  end
end

def identity_matrix(n)
  m = new_matrix(n, n)
  0.upto(n-1) { |i| m[i][i] = 1 }
  m
end

def matrix_dimensions(m)
  [m.count, m[0].count]
end

def matrix_element_count(m)
  rows, cols = matrix_dimensions(m)
  rows*cols
end

def matrix_mult_2(a, b)
  a_rows, a_cols = matrix_dimensions(a)
  b_rows, b_cols = matrix_dimensions(b)
  if a_cols != b_rows
    raise ColladaError.new("matrix_mult_2 error: cols/rows mismatch")
  end
  c = new_matrix(a_rows, b_cols)
  0.upto(a_rows-1) do |i|
    0.upto(b_cols-1) do |j|
      c[i][j] = 0
      0.upto(a_cols-1) { |k| c[i][j] += a[i][k]*b[k][j] }
    end
  end
  c
end

def matrix_mult(*matrices)
  if matrices.count == 0
    raise ColladaError.new("can't do matrix multiplication with 0 matrices")
  elsif matrices.count == 1
    matrices[0].clone
  else
    result = matrices[0]
    (1...matrices.count).each do |i|
      result = matrix_mult_2(result, matrices[i])
    end
    result
  end
end

def matrix_mult_vec(m, v)
  matrix_mult(m, matrix_transpose([v])).flatten()
end

def matrix_mult_scalar(m, s)
  mnew = m.flatten()
  (0...mnew.count).each do |i| mnew[i] = s*mnew[i] end
  partition_array(mnew, matrix_dimensions(m)[1])
end

def matrix_transpose(m)
  rows, cols = matrix_dimensions(m)
  trans = new_matrix(cols, rows)
  rows, cols = matrix_dimensions(trans)
  0.upto(rows-1) do |i|
    0.upto(cols-1) do |j|
      trans[i][j] = m[j][i]
    end
  end
  trans
end

# the minor matrix is the sub-matrix formed by deleting the specified row and column
def minor_matrix(m, row, col)
  m_flat = m.flatten()
  rows, cols = matrix_dimensions(m)
  raise if rows != cols
  minor = []
  0.upto(rows-1) do |i|
    0.upto(cols-1) do |j|
      if i != row and j != col
        minor << m[i][j]
      end
    end
  end
  partition_array(minor, cols-1)
end

def matrix_determinant(m)
  rows, cols = matrix_dimensions(m)
  raise if rows != cols
  if rows == 1
    return m[0][0]
  end
  # cofactor expansion along the top row
  cofactor_accumulator = 0
  0.upto(cols-1) do |i|
    cofactor_accumulator += ((-1)**i)*m[0][i]*(matrix_determinant(minor_matrix(m, 0, i)))
  end
  cofactor_accumulator
end

# the adjugate matrix is the transpose of the matrix of cofactors
def adjugate_matrix(m)
  rows, cols = matrix_dimensions(m)
  raise if rows != cols
  cofactor_matrix = new_matrix(rows, cols)
  0.upto(rows-1) do |i|
    0.upto(cols-1) do |j|
      cofactor_matrix[i][j] = ((-1)**(i+j))*matrix_determinant(minor_matrix(m, i, j))
    end
  end
  matrix_transpose(cofactor_matrix)
end

def matrix_inverse(m)
  det = matrix_determinant(m)
  # i bumped into an error with the epsilon check where i couldn't invert a .001
  # uniform scale matrix. obviously the epsilon was too high. maybe i should go back
  # and set epsilon to a higher value, but for now i'll just change this to check
  # directly against 0 instead of epsilon
  #if det.abs() < $epsilon
  if det.abs() == 0
    raise ColladaError.new("found a non-invertible matrix")
  end
  matrix_mult_scalar(adjugate_matrix(m), Float(1)/det)
end

def matrix_33_to_44(m)
  m = m.flatten
  new_matrix(4, 4, [m[0],m[1],m[2],0, m[3],m[4],m[5],0, m[6],m[7],m[8],0, 0,0,0,1])
end

def translation_matrix(tx, ty, tz)
  new_matrix(4, 4, [1,0,0,tx, 0,1,0,ty, 0,0,1,tz, 0,0,0,1])
end

# rotate r radians around the vector v
def rotation_matrix(r, v)
  v = vector_normalize(v)
  cosr = Math.cos(r)
  sinr = Math.sin(r)
  vx, vy, vz = v
  new_matrix(4, 4, [   cosr + (1-cosr)*vx*vx, (1-cosr)*vx*vy - vz*sinr, (1-cosr)*vx*vz + vy*sinr, 0,
                    (1-cosr)*vx*vy + vz*sinr,    cosr + (1-cosr)*vy*vy, (1-cosr)*vy*vz - vx*sinr, 0,
                    (1-cosr)*vx*vz - vy*sinr, (1-cosr)*vy*vz + vx*sinr,    cosr + (1-cosr)*vz*vz, 0,
                                           0,                        0,                        0, 1 ])
end

def x_rotation_matrix(r)
  rotation_matrix(r, [1,0,0])
end

def y_rotation_matrix(r)
  rotation_matrix(r, [0,1,0])
end

def z_rotation_matrix(r)
  rotation_matrix(r, [0,0,1])
end

def scale_matrix(sx, sy, sz)
  new_matrix(4, 4, [sx,0,0,0, 0,sy,0,0, 0,0,sz,0, 0,0,0,1])
end

def uniform_scale_matrix(s)
  scale_matrix(s, s, s)
end

class Node
  attr_accessor :id, :transform, :child_node_elems, :instance_nodes, :instance_geoms

  def initialize
    @id = nil
    @transform = nil # matrix transform, of nil if no transform
    @child_node_elems = [] # Element array
    @instance_nodes = [] # string array
    @instance_geoms = [] # string array
  end

  def ==(node)
    @id == node.id and
      @transform == node.transform and
      @child_node_elems == node.child_node_elems and
      @instance_nodes == node.instance_nodes and
      @instance_geoms == node.instance_geoms
  end
end

def build_id_elem_hash(root)
  table = root.attributes['id'] ? {root.attributes['id'] => root} : {}
  root.each_recursive do |elem|
    if elem.attributes['id'] != nil
      table[elem.attributes['id']] = elem
    end
  end
  table
end

def get_attr_str(elem, attr_name)
  val = elem.attributes[attr_name]
  if val == nil
    raise ColladaError.new("<#{elem.name}> element missing '#{attr_name}' attr")
  end
  val
end

def get_attr_int(elem, attr_name)
  str_to_int(get_attr_str(elem, attr_name))
end

def read_url(elem, attr_name)
  url = elem.attributes[attr_name]
  if url == nil or url.empty? or url[0] != "#" or url.length == 1
    raise ColladaError.new("missing or incorrectly formatted '#{attr_name}' attribute")
    nil
  else
    url[1..-1]
  end
end

def id_to_elem(id, id_elem_hash)
  elem = id_elem_hash[id]
  if elem == nil
    raise ColladaError.new("couldn't find element with id=#{id}")
  end
  elem
end

def elem_url_ref_to_elem(elem, attr_name, id_elem_hash)
  url_ref = read_url(elem, attr_name)
  id_to_elem(url_ref, id_elem_hash)
end

def get_child_elem(elem, child_name)
  child_elem = elem.elements[child_name]
  if child_elem == nil
    raise ColladaError.new("couldn't find <#{child_name}> child of <#{elem.name}> element")
  end
  child_elem
end

def read_matrix(matrix_elem)
  array = read_float_array(matrix_elem)
  if array.count != 16
    raise ColladaError.new("incorrectly formatted <matrix> element")
  end
  partition_array(array, 4)
end

def read_node(node_elem)
  node = Node.new
  node.id = node_elem.attributes['id']
  node.child_node_elems = node_elem.get_elements('node')
  node_elem.elements.each('instance_node') do |instance_node_elem|
    node.instance_nodes << read_url(instance_node_elem, 'url')
  end
  node_elem.elements.each('instance_geometry') do |instance_geom_elem|
    node.instance_geoms << read_url(instance_geom_elem, 'url')
  end
  if node_elem.get_elements('matrix').count > 1
    raise ColladaError.new("more than one <matrix> element in a node. unsupported for now.")
  end
  if node_elem.elements['matrix']
    node.transform = read_matrix(node_elem.elements['matrix'])
  end
  node
end

# returns a list of Nodes
def read_nodes(elem)
  return [] if elem == nil
  nodes = []
  elem.elements.each('node') do |node_elem|
    nodes << read_node(node_elem)
  end
  nodes
end

class Mesh
  # valid vertex formats
  #   - :pos
  #   - :pos_norm
  #   - :pos_tex
  #   - :pos_norm_tex

  attr_accessor :vertex_format, :vertices, :indices

  def initialize(vertices, indices, vertex_format)
    @vertices = vertices
    @indices = indices
    @vertex_format = vertex_format
  end

  def initialize_copy(source)
    super
    @vertices = source.vertices.clone
    @indices = source.indices.clone
  end

  def ==(mesh)
    @vertex_format == mesh.vertex_format and
      nested_array_equal(@vertices, mesh.vertices) and
      @indices == mesh.indices
  end
end

def get_vertex_format(has_normals, has_texcoords)
  case [!!has_normals, !!has_texcoords]
  when [false, false]
    :pos
  when [true, false]
    :pos_norm
  when [false, true]
    :pos_tex
  when [true, true]
    :pos_norm_tex
  end
end

def vertex_format_has_normals(vertex_format)
  vertex_format == :pos_norm  or  vertex_format == :pos_norm_tex
end

# XXX needs test
def vertex_format_has_tex_coords(vertex_format)
  vertex_format == :pos_tex  or  vertex_format == :pos_norm_tex
end

# returns an array containing the indices of each of the pos/normal/tex coord in a
# vertex, or nil if a component isn't present
# XXX needs test
def vertex_format_indices(vertex_format)
  p = 0
  n = vertex_format_has_normals(vertex_format) ? 1 : nil
  t = vertex_format_has_tex_coords(vertex_format) ? (n ? 2 : 1) : nil
  [p, n, t]
end

# returns a hash
#   {:vertex => {:source => "source_url", :offset => <int>},
#    :normal => ...,
#    :texcoord => ...}
def read_triangles_inputs(triangles_elem)
  inputs = {}
  triangles_elem.elements.each('input') do |input_elem|
    semantic = get_attr_str(input_elem, 'semantic')
    source = read_url(input_elem, 'source')
    offset = get_attr_int(input_elem, 'offset')
    set_str = input_elem.attributes['set']
    set = set_str == nil ? 0 : str_to_int(set_str)

    hash_val = {:source => source, :offset => offset}
    inputs[:vertex] = hash_val if semantic.upcase == "VERTEX" and inputs[:vertex] == nil
    inputs[:normal] = hash_val if semantic.upcase == "NORMAL" and inputs[:normal] == nil
    inputs[:texcoord] = hash_val if semantic.upcase == "TEXCOORD" and set == 0 and inputs[:texcoord] == nil
  end
  raise ColladaError.new("missing <input> with semantic=VERTEX") if inputs[:vertex] == nil
  inputs
end

# returns the url of the position <source>
def get_vertices_position_source(vertices_id, id_elem_hash)
  vertices_elem = id_to_elem(vertices_id, id_elem_hash)
  vertices_elem.elements.each('input') do |input_elem|
    semantic = get_attr_str(input_elem, 'semantic')
    if semantic.upcase == "POSITION"
      return read_url(input_elem, 'source')
    end
  end
  raise ColladaError.new("couldn't read <input> with semantic=POSITION from <vertices>")
end

def get_triangles_index_stride(triangles_elem)
  max_offset = -1
  triangles_elem.elements.each('input') do |input_elem|
    offset_str = input_elem.attributes['offset']
    if offset_str
      offset = str_to_int(offset_str)
      max_offset = [max_offset, offset].max
    end
  end
  max_offset + 1
end

# returns an array of arrays, where each sub-array is a position, normal, or tex coord
def read_source(source_id, id_elem_hash, *expected_param_names)
  source_elem = id_to_elem(source_id, id_elem_hash)
  technique_common_elem = get_child_elem(source_elem, 'technique_common')
  accessor_elem = get_child_elem(technique_common_elem, 'accessor')
  param_names = []
  accessor_elem.elements.each('param') do |param_elem|
    param_name = get_attr_str(param_elem, 'name')
    param_type = get_attr_str(param_elem, 'type')
    if param_type != "float"
      raise ColladaError.new("<param>s with type=#{param_type} are not supported")
    end
    param_names << param_name.upcase
  end
  expected_param_names = expected_param_names.map {|name| name.upcase}
  if expected_param_names != param_names
    raise ColladaError.new("got unexpected params #{param_names} in <accessor>. expected #{expected_param_names}.")
  end

  accessor_count = get_attr_int(accessor_elem, 'count')
  accessor_stride = get_attr_int(accessor_elem, 'stride')
  if param_names.count != accessor_stride
    raise ColladaError.new("number of <param>s should match <accessor> stride value")
  end

  array_elem = elem_url_ref_to_elem(accessor_elem, 'source', id_elem_hash)
  array_count = get_attr_int(array_elem, 'count')
  if array_count != accessor_count*accessor_stride
    raise ColladaError.new("<float_array> and <accessor> counts don't match")
  end

  array_vals = read_float_array(array_elem)
  if array_vals.count != array_count
    raise ColladaError.new("actual number of vals in <float_array> doesn't match count attribute")
  end
  if array_vals.count%accessor_stride != 0
    raise ColladaError.new("internal error")
  end

  partition_array(array_vals, param_names.count, accessor_stride)
end

def sort_non_unified_index(non_unified_index, inputs)
  sorted_non_unified_index = [non_unified_index[inputs[:position][:offset]]]
  if inputs[:normal]
    sorted_non_unified_index << non_unified_index[inputs[:normal][:offset]]
  end
  if inputs[:texcoord]
    sorted_non_unified_index << non_unified_index[inputs[:texcoord][:offset]]
  end
  sorted_non_unified_index
end

# non_unified_indices input is [[ip0, in0, iuv0], [ip1, in1, iuv1], ...]
# output is [indices, vertices]
# indices = [i0, i1, i2, ...] <--- three integers == one triangle
# vertices = [[[px, py, pz], [nx, ny, nz], [u, v]], ...]
# note that the normals and tex coords are optional. they'll be in the output only if
# they're supplied in the input.
def convert_to_unified_indices(non_unified_indices, positions, normals, texcoords)
  indices = []
  vertices = []
  index_hash = {}

  non_unified_indices.each do |non_unified_index|
    if index_hash[non_unified_index] != nil
      indices << index_hash[non_unified_index]
    else
      new_index = vertices.count
      indices << new_index
      index_hash[non_unified_index] = new_index
      vertex = [positions[non_unified_index[0]]]
      if normals
        vertex << normals[non_unified_index[1]]
      end
      if texcoords
        vertex << texcoords[non_unified_index[normals ? 2 : 1]]
      end
      vertices << vertex
    end
  end

  [indices, vertices]
end

# returns a Mesh
def read_triangles(triangles_elem, id_elem_hash)
  inputs = read_triangles_inputs(triangles_elem)
  position_source = get_vertices_position_source(inputs[:vertex][:source], id_elem_hash)
  inputs[:position] = inputs[:vertex].clone
  inputs[:position][:source] = position_source

  positions = read_source(inputs[:position][:source], id_elem_hash, 'X', 'Y', 'Z')
  normals = inputs[:normal] ? read_source(inputs[:normal][:source], id_elem_hash, 'X', 'Y', 'Z') : nil
  texcoords = inputs[:texcoord] ? read_source(inputs[:texcoord][:source], id_elem_hash, 'S', 'T') : nil

  index_stride = get_triangles_index_stride(triangles_elem)
  p_elem = get_child_elem(triangles_elem, 'p')

  indices = partition_array(read_int_array(p_elem), index_stride)
  indices = indices.map { |non_unified_index| sort_non_unified_index(non_unified_index, inputs) }
  indices, vertices = convert_to_unified_indices(indices, positions, normals, texcoords)

  Mesh.new(vertices, indices, get_vertex_format(!!normals, !!texcoords))
end

# returns a Mesh array
def read_geometry(geom_elem, id_elem_hash)
  mesh_elem = get_child_elem(geom_elem, 'mesh')
  meshes = []
  mesh_elem.elements.each('triangles') do |triangles_elem|
    meshes << read_triangles(triangles_elem, id_elem_hash)
  end
  meshes
end

def transform_pos(transform, p)
  pnew = matrix_mult_vec(transform, [p[0], p[1], p[2], 1])
  pnew = pnew.map { |val| val /= pnew[3] }
  pnew[0..2]
end

def transform_normal(transform, n)
  vector_normalize(matrix_mult_vec(transform, [n[0], n[1], n[2], 0])[0..2])
end

def pretransform_mesh(mesh, transform)
  new_mesh = mesh.clone
  has_normals = vertex_format_has_normals(mesh.vertex_format)
  normal_transform = matrix_transpose(matrix_inverse(transform))
  (0...mesh.vertices.count).each do |i|
    new_mesh.vertices[i][0] = transform_pos(transform, new_mesh.vertices[i][0])
    if has_normals
      begin
        new_mesh.vertices[i][1] = transform_normal(normal_transform, new_mesh.vertices[i][1])
      rescue NormalizeZeroLengthVectorError
        new_mesh.vertices[i][1] = [0, 0, 0]
      end
    end
  end
  new_mesh
end

# XXX needs test
def traverse_node(node_elem, parent_transform, id_elem_hash)
  node = read_node(node_elem)
  transform = node.transform ? matrix_mult(parent_transform, node.transform) : parent_transform

  # read geoms
  meshes = []
  node.instance_geoms.each do |geom_id|
    geom_elem = id_to_elem(geom_id, id_elem_hash)
    geom_meshes = read_geometry(geom_elem, id_elem_hash)
    meshes.concat(geom_meshes)
  end

  # pretransform meshes
  meshes = meshes.map { |mesh| pretransform_mesh(mesh, transform) }

  child_node_meshes = node.child_node_elems.map do |child_node_elem|
    traverse_node(child_node_elem, transform, id_elem_hash)
  end

  instance_node_meshes = node.instance_nodes.map do |node_id|
    traverse_node(id_to_elem(node_id, id_elem_hash), transform, id_elem_hash)
  end

  [meshes, child_node_meshes, instance_node_meshes].flatten
end

# XXX needs test
# returns a list of Meshes with all positions and normals pre-transformed
def traverse_scene(doc)
  id_elem_hash = build_id_elem_hash(doc.root)
  scene = doc.elements['COLLADA/scene']
  if scene == nil
    raise ColladaError.new("couldn't find <scene>")
  end
  visual_scene = elem_url_ref_to_elem(get_child_elem(scene, 'instance_visual_scene'), 'url', id_elem_hash)
  meshes = []
  visual_scene.elements.each('node') do |node_elem|
    meshes.concat(traverse_node(node_elem, identity_matrix(4), id_elem_hash))
  end
  meshes
end

# XXX needs test
def to_obj(filename, meshes)
  print_vertex = lambda do |io, vertex, vertex_format|
    # XXX currently we output dummy texture coordinates and normals for meshes that
    # don't have those, to keep the absolute-based indexing happy. i should switch to
    # either relative (-1-based) indexing or non-unified indices, so that i don't have
    # to output dummy values.
    p_index, n_index, t_index = vertex_format_indices(vertex_format)
    p = vertex[p_index]
    io.printf("v %f %f %f\n", p[0], p[1], p[2])
    if n_index
      n = vertex[n_index]
      io.printf("vn %f %f %f\n", n[0], n[1], n[2])
    else
      io.printf("vn 0 0 0\n")
    end
    if t_index
      t = vertex[t_index]
      io.printf("vt %f %f\n", t[0], t[1])
    else
      io.printf("vt 0 0\n")
    end
  end

  print_triangle_indices = lambda do |io, indices, vertex_format, vertex_offset|
    # obj indices are 1-based, not 0-based, and start at the first vertex in the entire
    # file, rather than the first vertex of the mesh. we need to adjust the indices for
    # this.
    i0, i1, i2 = indices.map { |i| 1 + i + vertex_offset }
    case vertex_format
    when :pos
      io.printf("f %d %d %d\n", i0, i1, i2)
    when :pos_norm
      io.printf("f %d//%d %d//%d %d//%d\n", i0, i0, i1, i1, i2, i2)
    when :pos_tex
      io.printf("f %d/%d %d/%d %d/%d \n", i0, i0, i1, i1, i2, i2)
    when :pos_norm_tex
      io.printf("f %d/%d/%d %d/%d/%d %d/%d/%d \n", i0, i0, i0, i1, i1, i1, i2, i2, i2)
    else
      raise ColladaError.new("unknown vertex format")
    end
  end

  print_mesh = lambda do |io, mesh, vertex_offset|
    mesh.vertices.each do |vertex|
      print_vertex.call(io, vertex, mesh.vertex_format)
    end

    triangle_indices = partition_array(mesh.indices, 3)
    triangle_indices.each do |indices|
      print_triangle_indices.call(io, indices, mesh.vertex_format, vertex_offset)
    end
  end

  f = File.open(filename, 'w')
  total_vertex_count = 0
  meshes.each do |mesh|
    print_mesh.call(f, mesh, total_vertex_count)
    total_vertex_count += mesh.vertices.count
  end
end

# main
if $0 == __FILE__
  options = {}

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: dae-to-obj [options] dae-file obj-file"

    opts.on('-h', '--help', 'print help and exit') do
      puts opts
      exit
    end

    # XXX remove this at some point
    options[:blender_shrink] = false
    opts.on('', '--blender-shrink', 'shrink and rotate the model to fit in blender (temporary hack)') do
      options[:blender_shrink] = true
    end
  end

  optparse.parse!

  if ARGV.empty?
    puts "missing .dae file to convert"
    exit
  end

  input_file = ARGV[0]
  if not File.exists?(input_file)
    puts "file '#{input_file}' doesn't exist"
    exit
  end

  output_file = File.basename(input_file, '.*') + '.obj'
  if ARGV.count > 1
    output_file = ARGV[1]
  end

  # XXX why does File.writable? return false for files I can in fact write to? we'll
  # disable this check for now.
  # if not File.writable?(output_file)
  #   puts "file '#{output_file}' is not writable"
  #   exit
  # end

  doc = REXML::Document.new(File.open(input_file))
  meshes = traverse_scene(doc)

  if options[:blender_shrink]
    # apply a scale and rotation to make the model easier to view in blender
    transform = matrix_mult(x_rotation_matrix(-Math::PI/2), uniform_scale_matrix(0.001))
    meshes = meshes.map { |mesh| pretransform_mesh(mesh, transform) }
  end

  to_obj(output_file, meshes)
end
